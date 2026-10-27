import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stalled, defaultStallMs, openResources } from '../src/watchdog.mjs';

const MOD = join(dirname(fileURLToPath(import.meta.url)), '../src/watchdog.mjs');

test('stalled: strictly more than the limit of silence', () => {
  assert.equal(stalled(1000, 0, 1000), false);
  assert.equal(stalled(1001, 0, 1000), true);
});

test('defaultStallMs: 90 s scaled like the other waits, FW_WK_STALL_MS overrides', () => {
  assert.equal(defaultStallMs({}), 90000);
  assert.equal(defaultStallMs({ FW_WK_TIMEOUT_SCALE: '8' }), 720000);
  assert.equal(defaultStallMs({ FW_WK_TIMEOUT_SCALE: '8', FW_WK_STALL_MS: '5000' }), 5000);
  assert.equal(defaultStallMs({ FW_WK_STALL_MS: 'x' }), 90000);
});

test('openResources counts kinds', () => {
  assert.deepEqual(openResources(['Timeout', 'TCPSocketWrap', 'Timeout']), { Timeout: 2, TCPSocketWrap: 1 });
});

const run = (body) => spawnSync(process.execPath, ['--input-type=module', '-e', `import { watch } from ${JSON.stringify(MOD)};\n${body}`], { encoding: 'utf8', timeout: 20000 });

test('a command that finished but leaves a socket-like handle open is ended with a reason and its own exit code', () => {
  const r = run(`const g = watch({ exitMs: 300 }); setInterval(() => {}, 1000); console.log('result'); g.done(0);`);
  assert.equal(r.status, 0);
  assert.match(r.stderr, /forced exit: the command finished but .* alive; open: \{.*"Timeout":1/);
  assert.match(r.stdout, /result/);
});

test('a healthy process exits by itself and says so', () => {
  const r = run(`const g = watch({ exitMs: 5000 }); console.log('result'); g.done(0);`);
  assert.equal(r.status, 0);
  assert.match(r.stderr, /cli: exit 0/);
  assert.doesNotMatch(r.stderr, /forced exit/);
});

const skewed = (extra) => `
  let skew = 0; const now = () => Date.now() + skew;
  setTimeout(() => { skew += 5000; }, 100);
  watch({ stallMs: 1000, tickMs: 20, graceMs: 100, now, ${extra} });
  setTimeout(() => { console.error('still here'); process.exit(0); }, 700);
  setInterval(() => {}, 1000);
`;

test('a freeze (late tick, no host call) is not silence: the process goes on', () => {
  const r = run(skewed('pending: () => []'));
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stderr, /still here/);
  assert.doesNotMatch(r.stderr, /stalled/);
});

test('a late tick while a host call of ours runs counts in full', () => {
  const r = run(skewed("pending: () => [{ what: 'simctl list', ageMs: 5000, boundMs: 30000 }]"));
  assert.match(r.stderr, /stalled: no output for \d+ s/);
  assert.doesNotMatch(r.stderr, /the host held/);
});

test('a stall (no output) is reported with the last line and ends the process', () => {
  const r = run(`watch({ stallMs: 400, graceMs: 300 }); console.error('last words'); setInterval(() => {}, 1000);`);
  assert.equal(r.status === 3 || r.signal === 'SIGTERM', true, `status ${r.status} signal ${r.signal}`);
  assert.match(r.stderr, /error: stalled: no output for \d+ s \(limit 0 s\); last line: "last words"/);
});
