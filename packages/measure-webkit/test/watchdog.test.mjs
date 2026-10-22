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

test('a stall (no output) is reported with the last line and ends the process', () => {
  const r = run(`watch({ stallMs: 400, graceMs: 300 }); console.error('last words'); setInterval(() => {}, 1000);`);
  assert.equal(r.status === 3 || r.signal === 'SIGTERM', true, `status ${r.status} signal ${r.signal}`);
  assert.match(r.stderr, /error: stalled: no output for \d+ s \(limit 0 s\); last line: "last words"/);
});

// ---- the group-kill wrapper (`run`): task sim-step-watchdog
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';
import { BOUNDS } from '../src/inspector.mjs';
import { runBounded, endGroup, groupAlive, watchdogLine, WATCHDOG_EXIT } from '../src/watchdog.mjs';

const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };
const cli = (args, opts = {}) => new Promise((resolve) => {
  const c = spawn(process.execPath, [MOD, 'run', ...args], { stdio: ['ignore', 'pipe', 'pipe'], ...opts });
  let out = '', err = '';
  c.stdout.on('data', (d) => { out += d; }); c.stderr.on('data', (d) => { err += d; });
  c.on('exit', (code, signal) => resolve({ code, signal, out, err }));
});

test("the exit code and the kill wait are Lean's (Fw.Measure.SimBound via measure.simBounds)", () => {
  assert.equal(WATCHDOG_EXIT, BOUNDS.watchdogExit);
  assert.equal(BOUNDS.watchdogExit, 6);
  assert.equal(BOUNDS.killWaitMs, 5000);
});

test('a child that ignores SIGINT and SIGTERM, with a child of its own, is killed with its group; one watchdog line names session and pass', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'wd-'));
  const r = await cli(['--label', 'session 1', '--budget-s', '1', '--grace-ms', '300', '--stdout-file', join(dir, 'o.md'), '--stderr-file', join(dir, 'e.log'), '--', process.execPath, MOD, 'hang']);
  assert.equal(r.code, 6, r.err);
  const lines = r.err.split('\n').filter((l) => l.startsWith('watchdog:'));
  assert.equal(lines.length, 1, r.err);
  assert.match(lines[0], /^watchdog: session 1: not finished \d+ s into the step \(limit 1 s\); pass: pass 1\/2; last line: ".*"; ended process group \d+: TERM sent, KILL sent, group gone$/);
  const kid = Number(/grandchild (\d+)/.exec(r.out)[1]);
  assert.equal(alive(kid), false, 'the grandchild is dead too');
  const pg = Number(/process group (\d+)/.exec(lines[0])[1]);
  assert.equal(groupAlive(pg), false);
  assert.match(readFileSync(join(dir, 'e.log'), 'utf8'), /SIGTERM ignored/, 'the stderr file keeps what the child said');
  assert.match(readFileSync(join(dir, 'e.log'), 'utf8'), /\nwatchdog: session 1: .*group gone\n$/, 'and the watchdog line');
  assert.match(readFileSync(join(dir, 'o.md'), 'utf8'), /grandchild \d+/);
});

test('a command that finishes in time keeps its exit code and the watchdog stays silent', async () => {
  const ok = await cli(['--label', 's', '--budget-s', '30', '--grace-ms', '300', '--', process.execPath, '-e', 'console.error("pass 1/1"); process.exit(0)']);
  assert.equal(ok.code, 0);
  assert.doesNotMatch(ok.err, /^watchdog:/m);
  const bad = await cli(['--label', 's', '--budget-s', '30', '--grace-ms', '300', '--', process.execPath, '-e', 'process.exit(4)']);
  assert.equal(bad.code, 4);
});

test('a command that exits but leaves a process in its group does not outlive the session', async () => {
  const r = await cli(['--label', 's', '--budget-s', '30', '--grace-ms', '300', '--', 'sh', '-c', 'sleep 300 & echo helper $!; exit 0']);
  assert.equal(r.code, 0);
  const pid = Number(/helper (\d+)/.exec(r.out)[1]);
  assert.equal(alive(pid), false);
});

test('no time left: nothing is started and the line says so', async () => {
  const r = await cli(['--label', 'session 2', '--start-s', '1', '--budget-s', '1', '--grace-ms', '300', '--', process.execPath, '-e', 'console.log("started")']);
  assert.equal(r.code, 6);
  assert.doesNotMatch(r.out, /started/);
  assert.match(r.err, /^watchdog: session 2: .*no command started \(no time left\)$/m);
});

test('a command that cannot start gives 127 and a reason; bad flags give 2', async () => {
  const r = await cli(['--label', 's', '--budget-s', '30', '--grace-ms', '300', '--', '/nonexistent/fw-cmd']);
  assert.equal(r.code, 127);
  assert.match(r.err, /cannot start/);
  const u = await cli(['--label', 's', '--', 'true']);
  assert.equal(u.code, 2);
});

test('endGroup: a group that is gone after TERM gets no KILL; one that survives gets it', async () => {
  const sent = [];
  let up = true;
  const kill = (g, s) => { sent.push(s); if (s === 'SIGTERM') up = false; };
  assert.deepEqual(await endGroup(42, { graceMs: 100, kill, alive: () => up, pollMs: 10 }), { termSent: true, killSent: false, gone: true });
  sent.length = 0; up = true;
  const stubborn = (g, s) => { sent.push(s); if (s === 'SIGKILL') up = false; };
  assert.deepEqual(await endGroup(42, { graceMs: 50, killWaitMs: 100, kill: stubborn, alive: () => up, pollMs: 10 }), { termSent: true, killSent: true, gone: true });
  assert.deepEqual(sent, ['SIGTERM', 'SIGKILL']);
  assert.equal((await endGroup(42, { graceMs: 20, killWaitMs: 40, kill: () => {}, alive: () => true, pollMs: 10 })).gone, false);
});

test('runBounded with a past deadline starts nothing and says one line', async () => {
  const said = [];
  const r = await runBounded({ cmd: 'x', label: 'L', deadlineMs: 1000, startMs: 0, graceMs: 1, now: () => 5000, say: (s) => said.push(s) });
  assert.deepEqual(r, { code: 6, fired: true });
  assert.equal(said.length, 1);
  assert.equal(said[0], watchdogLine({ label: 'L', elapsedS: 5, budgetS: 1, pass: null, lastLine: null, pgid: null, ended: null }));
});
