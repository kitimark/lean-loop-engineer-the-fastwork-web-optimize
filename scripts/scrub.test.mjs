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

const SCRIPT = join(dir, 'scripts/scrub.mjs');

// account: '' = no account rule; a name = injected (with FW_SCRUB_TEST=1 unless opts.noTest); null = unset (read from the OS).
// opts: { file, env, noTest }
function scan(content, account = '', allow, opts = {}) {
  const file = opts.file || 'a.txt';
  sh(['reset', '-q']);
  mkdirSync(dirname(join(dir, file)), { recursive: true });
  writeFileSync(join(dir, file), content);
  sh(['add', '-f', '--', file]);
  rmSync(join(dir, 'scripts/scrub-allow.json'), { force: true });
  if (allow) writeFileSync(join(dir, 'scripts/scrub-allow.json'), JSON.stringify(allow));
  const env = { ...process.env, ...(opts.env || {}) };
  delete env.FW_SCRUB_TEST;
  if (account === null) delete env.FW_SCRUB_ACCOUNT;
  else {
    env.FW_SCRUB_ACCOUNT = account;
    if (!opts.noTest) env.FW_SCRUB_TEST = '1';
  }
  const r = spawnSync('node', [SCRIPT], { cwd: dir, encoding: 'utf8', env });
  return { code: r.status, err: r.stderr };
}
function selfCheck(account) {
  const env = { ...process.env, FW_SCRUB_TEST: '1' };
  if (account === null) delete env.FW_SCRUB_ACCOUNT; else env.FW_SCRUB_ACCOUNT = account;
  return JSON.parse(spawnSync('node', [SCRIPT, '--self-check'], { cwd: dir, encoding: 'utf8', env }).stdout);
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
test('encoded home: name at the end of the text or before a slash', () => {
  assert.equal(scan('projects/-Users-' + 'zed\n').code, 1);
  assert.equal(scan('projects/-Users-' + 'zed/mem.md\n').code, 1);
  assert.equal(scan('p -home-' + 'qux\n').code, 1);
  assert.equal(scan('p -home-' + 'qux/x\n').code, 1);
});
test('encoded home: glued prefixes', () => {
  assert.equal(scan('claude-501-Users-' + 'zed-src\n').code, 1);
  assert.equal(scan('%2F-Users-' + 'zed-x\n').code, 1);
  assert.equal(scan('C--Users-' + 'zed-x\n').code, 1);
  assert.equal(scan('x-Users-' + 'zed-y\n').code, 1);
});
test('encoded home: lowercase -home- keeps its left edge', () => {
  assert.equal(scan('claude-501-home-' + 'qux-src\n').code, 0);
  assert.equal(scan('nav-home-page\n').code, 0);
});
test('encoded home: generic names pass in every position', () => {
  assert.equal(scan('a -Users-runner and -Users-runner/x and C--Users-user-x and -Users-runner\n').code, 0);
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
  const generic = selfCheck(null).account === false;
  assert.equal(scan(`hello ${real}\n`, null).code, generic ? 0 : 1);
});
test('path rules: a file named after the injected account (line 0)', () => {
  const r = scan('clean\n', 'Quillfoo', undefined, { file: 'notes/quillfoo-plan.md' });
  assert.equal(r.code, 1);
  assert.match(r.err, /notes\/quillfoo-plan\.md:0:0\s+rule=account-name/);
  assert.equal(scan('clean\n', 'quillfoo', undefined, { file: 'notes/plan.md' }).code, 0);
  assert.equal(scan('clean\n', 'quillfoo', undefined, { file: 'notes/quillfoobar.md' }).code, 0);
});
test('path rules: a file under an encoded home (line 0), allowlist applies', () => {
  const file = 'x/-Users-' + 'zed-src.md';
  const r = scan('clean\n', '', undefined, { file });
  assert.equal(r.code, 1);
  assert.match(r.err, /:0:0\s+rule=encoded-home/);
  const allow = [{ rule: 'encoded-home', path: 'x/', reason: 'invented' }];
  assert.equal(scan('clean\n', '', allow, { file }).code, 0);
});
test('FW_SCRUB_ACCOUNT without FW_SCRUB_TEST is ignored with a stderr note', () => {
  const r = scan('built by quillfoo\n', 'quillfoo', undefined, { noTest: true });
  assert.equal(r.code, 0);
  assert.match(r.err, /FW_SCRUB_ACCOUNT ignored/);
});
test('self-check: every name in GENERIC leaves the account rule off', () => {
  const generic = selfCheck('quillfoo').generic;
  assert.ok(generic.includes('runner') && generic.length >= 8);
  for (const g of generic) assert.equal(selfCheck(g.toUpperCase()).account, false, g);
  assert.equal(selfCheck('quillfoo').account, true);
  assert.equal(selfCheck('ab').account, false);
});
test('unset override with a fake HOME/USER: the name comes from the OS, not the environment', () => {
  const env = { HOME: '/nonexistent/fakehome', USER: 'fakeperson', LOGNAME: 'fakeperson' };
  assert.equal(scan('hello fakeperson fakehome\n', null, undefined, { env }).code, 0);
  const real = userInfo().username;
  const generic = selfCheck(null).account === false;
  assert.equal(scan(`hello ${real}\n`, null, undefined, { env }).code, generic ? 0 : 1);
});
test('allowlist per rule and path, reason mandatory', () => {
  // session-path allowed still leaves encoded-home matching the same text, so allow both for a clean pass
  const both = [{ rule: 'session-path', path: 'a.txt', reason: 'invented' }, { rule: 'encoded-home', path: 'a.txt', reason: 'invented' }];
  assert.equal(scan(`see ${SP}\n`, '', both).code, 0);
  assert.equal(scan(`see ${SP}\n`, '', [{ rule: 'session-path', path: 'a.txt', reason: 'invented' }]).code, 1);
  assert.equal(scan('built by quillfoo\n', 'quillfoo', [{ rule: 'account-name', path: 'a.txt', reason: 'invented' }]).code, 0);
  assert.equal(scan(`see ${SP}\n`, '', [{ rule: 'session-path', path: 'a.txt', reason: '' }]).code, 2);
});
