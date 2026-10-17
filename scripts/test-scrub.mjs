#!/usr/bin/env node
// test-scrub.mjs: fixtures for every scrub rule and allow case, run in a throwaway git repo.
// Positive strings are assembled from pieces so this file itself never trips the scrub.
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dir = mkdtempSync(join(tmpdir(), 'scrub-test-'));
const sh = (a) => execFileSync('git', a, { cwd: dir, stdio: 'pipe' });
sh(['init', '-q']);
mkdirSync(join(dir, 'scripts'));
copyFileSync(join(here, 'scrub.mjs'), join(dir, 'scripts/scrub.mjs'));

const at = '@';
const cases = [
  // [name, path, content, expected rule or null]
  ['email bad', 'a.txt', `mail me: someone${at}gmail.com\n`, 'email'],
  ['email example.com ok', 'a.txt', `x${at}example.com\n`, null],
  ['email example.invalid ok', 'a.txt', `x${at}mail.example.invalid\n`, null],
  ['email noreply ok', 'a.txt', `noreply${at}anthropic.com\n`, null],
  ['npm/asset @ ok', 'a.txt', `pkg${at}1.2.3 icon${at}2x.png build${at}main.zip\n`, null],
  ['home mac', 'a.txt', 'see /Users/' + 'alice/work\n', 'home-path'],
  ['home linux', 'a.txt', 'see /home/' + 'bob/work\n', 'home-path'],
  ['home runner ok', 'a.txt', 'at /home/runner/work\n', null],
  ['lan 10/8', 'a.txt', 'host 10.0.' + '3.4\n', 'lan-ip'],
  ['lan 172.16/12', 'a.txt', 'host 172.' + '20.1.1\n', 'lan-ip'],
  ['lan 172.32 ok', 'a.txt', 'host 172.' + '32.1.1\n', null],
  ['lan 192.168', 'a.txt', 'host 192.' + '168.1.20\n', 'lan-ip'],
  ['loopback ok', 'a.txt', 'host 127.0.0.1 and 0.0.0.0\n', null],
  ['version string ok', 'a.txt', 'v1.10.2.3 x\n', null],
  ['uuid upper', 'a.txt', 'dev 3F2A9C41-' + '7B1D-4E55-9A0C-1D2E3F405162\n', 'device-id'],
  ['uuid lower ok', 'a.txt', 'id 3f2a9c41-7b1d-4e55-9a0c-1d2e3f405162\n', null],
  ['udid', 'a.txt', 'udid 00008110-' + '001A3C4E0A12801E\n', 'device-id'],
  ['private key', 'a.txt', '-----BEGIN ' + 'RSA PRIVATE KEY-----\n', 'secret'],
  ['secret file', '.fw-console/secret.key', 'abc\n', 'secret'],
  ['non-secret console file ok', '.fw-console/state.json', '{}\n', null],
  ['snapshot skipped', 'snapshot/site/a.js', `t${at}gmail.com /Users/` + 'al/x 10.1.' + '1.1\n', null],
  ['binary skipped', 'b.bin', Buffer.concat([Buffer.from([0, 1, 2]), Buffer.from(`t${at}gmail.com\n`)]), null],
];

function run(name, files, extra = () => {}) {
  sh(['reset', '-q']);
  mkdirSync(join(dir, 'scripts'), { recursive: true });
  for (const [p, c] of files) {
    mkdirSync(dirname(join(dir, p)), { recursive: true });
    writeFileSync(join(dir, p), c);
    sh(['add', '-f', '--', p]);
  }
  extra();
  const r = spawnSync('node', [join(dir, 'scripts/scrub.mjs')], { cwd: dir, encoding: 'utf8' });
  return { code: r.status, err: r.stderr };
}

let fail = 0;
const check = (name, ok, detail = '') => { if (!ok) fail++; console.log(`${ok ? 'ok  ' : 'FAIL'} ${name} ${detail}`); };

for (const [name, p, c, rule] of cases) {
  const r = run(name, [[p, c]]);
  const want = rule ? 1 : 0;
  const named = !rule || r.err.includes(`${p}:`) && r.err.includes(`rule=${rule}`);
  const hidden = !r.err.includes('gmail') && !r.err.includes('alice') && !r.err.includes('168.1.20');
  check(name, r.code === want && named && hidden, `(exit ${r.code})`);
}

// line number reporting: only added lines, correct line
{
  writeFileSync(join(dir, 'l.txt'), 'one\ntwo\n');
  sh(['add', '--', 'l.txt']);
  sh(['-c', 'user.name=t', '-c', 'user.email=t@example.com', '-c', 'core.hooksPath=/dev/null', 'commit', '-q', '-m', 'x']);
  writeFileSync(join(dir, 'l.txt'), `one\ntwo\nhost 10.9.` + '8.7\n');
  sh(['add', '--', 'l.txt']);
  const r = spawnSync('node', [join(dir, 'scripts/scrub.mjs')], { cwd: dir, encoding: 'utf8' });
  check('reports file:line', r.status === 1 && r.stderr.includes('l.txt:3:'), `(exit ${r.status})`);
}

// allowlist: with reason passes; without reason is a config error; other path still fails
{
  const bad = 'x 192.' + '168.0.9\n';
  const allowJson = (reason) => () => writeFileSync(join(dir, 'scripts/scrub-allow.json'),
    JSON.stringify([{ rule: 'lan-ip', path: 'doc/', ...(reason ? { reason } : {}) }]));
  check('allowlist with reason', run('a', [['doc/n.md', bad]], allowJson('documented example')).code === 0);
  check('allowlist without reason rejected', run('b', [['doc/n.md', bad]], allowJson('')).code === 2);
  check('allowlist other path still fails', run('c', [['src/n.md', bad]], allowJson('documented example')).code === 1);
}

rmSync(dir, { recursive: true, force: true });
console.log(fail ? `${fail} FAILED` : 'all passed');
process.exit(fail ? 1 : 0);
