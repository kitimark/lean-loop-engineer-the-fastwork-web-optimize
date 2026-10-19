// scrub.test.mjs: node --test for the session-path, encoded-home and account-name rules (invented names only).
// Run: node --test scripts/scrub.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir, userInfo } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dir = mkdtempSync(join(tmpdir(), 'scrub-t2-'));
const sh = (a) => execFileSync('git', a, { cwd: dir, stdio: 'pipe' });
sh(['init', '-q']);
mkdirSync(join(dir, 'scripts'));
copyFileSync(join(here, 'scrub.mjs'), join(dir, 'scripts/scrub.mjs'));
after(() => rmSync(dir, { recursive: true, force: true }));

// env: FW_SCRUB_ACCOUNT '' = no account rule; a name = injected; null = unset (read from the OS).
function scan(content, account = '', allow) {
  sh(['reset', '-q']);
  writeFileSync(join(dir, 'a.txt'), content);
  sh(['add', '-f', '--', 'a.txt']);
  if (allow) writeFileSync(join(dir, 'scripts/scrub-allow.json'), JSON.stringify(allow));
  const env = { ...process.env };
  if (account === null) delete env.FW_SCRUB_ACCOUNT; else env.FW_SCRUB_ACCOUNT = account;
  const r = spawnSync('node', [join(dir, 'scripts/scrub.mjs')], { cwd: dir, encoding: 'utf8', env });
  return { code: r.status, err: r.stderr };
}
const SP = '/private/tmp/claude-' + '501/-Users-' + 'zed-source-x/scratchpad/n.md';

test('session path refused (mac and linux encodings)', () => {
  const r = scan(`see ${SP}\n`);
  assert.equal(r.code, 1);
  assert.match(r.err, /rule=session-path/);
  assert.ok(!r.err.includes('zed'));
  assert.equal(scan('at /tmp/claude-' + '77/-home-' + 'qux-src/x\n').code, 1);
});
test('session path without an encoded home passes', () => {
  const r = scan('/private/tmp/claude-501/scratchpad/n.md\n');
  assert.equal(r.code, 0);
});
test('encoded home refused', () => {
  const r = scan('projects/-Users-' + 'zed-source-x/mem.md\n');
  assert.equal(r.code, 1);
  assert.match(r.err, /rule=encoded-home/);
  assert.equal(scan('p -home-' + 'qux-src\n').code, 1);
});
test('encoded home look-alikes pass', () => {
  assert.equal(scan('class nav-home-page-hero and --home-banner-x and -Users-runner-x\n').code, 0);
});
test('account name refused: whole word, case-insensitive, injected', () => {
  const r = scan('built by quillfoo today\n', 'Quillfoo');
  assert.equal(r.code, 1);
  assert.match(r.err, /rule=account-name/);
  assert.ok(!r.err.toLowerCase().includes('quillfoo'));
  assert.equal(scan('path-QUILLFOO-x\n', 'quillfoo').code, 1);
});
test('account name: substrings, other names, generic names pass', () => {
  assert.equal(scan('quillfoobar and xquillfoo\n', 'quillfoo').code, 0);
  assert.equal(scan('quillfoo\n', 'otherperson').code, 0);
  assert.equal(scan('apps/runner root\n', 'runner').code, 0);
});
test('account name is read at run time from the OS when not injected', () => {
  const real = userInfo().username;
  const generic = ['runner', 'root', 'user', 'admin', 'ubuntu', 'circleci', 'node', 'nobody'].includes(real.toLowerCase()) || real.length < 3;
  assert.equal(scan(`hello ${real}\n`, null).code, generic ? 0 : 1);
});
test('allowlist per rule and path, reason mandatory', () => {
  // session-path allowed still leaves encoded-home matching the same text, so allow both for a clean pass
  const both = [{ rule: 'session-path', path: 'a.txt', reason: 'invented' }, { rule: 'encoded-home', path: 'a.txt', reason: 'invented' }];
  assert.equal(scan(`see ${SP}\n`, '', both).code, 0);
  assert.equal(scan(`see ${SP}\n`, '', [{ rule: 'session-path', path: 'a.txt', reason: 'invented' }]).code, 1);
  assert.equal(scan('built by quillfoo\n', 'quillfoo', [{ rule: 'account-name', path: 'a.txt', reason: 'invented' }]).code, 0);
  assert.equal(scan(`see ${SP}\n`, '', [{ rule: 'session-path', path: 'a.txt', reason: '' }]).code, 2);
});
