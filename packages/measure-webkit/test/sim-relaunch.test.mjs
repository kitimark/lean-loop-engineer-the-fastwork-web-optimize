import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGuard, initPass, step, exec, used, timeUsed, terminal, callWorstS, RECOVER } from '../src/guard.mjs';
import { CALL, deviceBooted, rebootDevice, listDevices } from '../src/sim.mjs';
import { withRetry, wait } from '../src/simretry.mjs';
import { InspectorDeadError } from '../src/inspector.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(join(HERE, '../../contracts/golden/device/sim-relaunch.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => golden.filter((g) => g.kind === kind);

test('the golden is non-empty and every kind is replayed', () => {
  assert.deepEqual([...new Set(golden.map((g) => g.kind))].sort(), ['call', 'callWorst', 'consts', 'exec']);
  assert.ok(of('exec').length >= 20 && of('call').length >= 8);
});

test('constants: the limits and the seconds of the recover path are the Lean ones', () => {
  const [c] = of('consts');
  assert.equal(CALL.tries, c.callTries);
  assert.equal(wait(1) / 1000, c.callGapS);
  assert.deepEqual([CALL.stateMs, CALL.listMs, CALL.shutdownMs, CALL.bootMs, CALL.bootstatusMs].map((x) => x / 1000),
    [c.stateCallS, c.listCallS, c.shutdownCallS, c.bootCallS, c.bootstatusCallS]);
  assert.equal(RECOVER.detectS, c.detectS);
  assert.equal(RECOVER.relaunchS, c.relaunchS);
  assert.equal(RECOVER.rebootS, c.rebootS);
  assert.equal(RECOVER.worstS, c.recoverWorstS);
  assert.equal(RECOVER.passEvents, c.passEvents);
  assert.ok(c.recoverMin * 60 >= c.rebootS, 'the step bound would need recoverMin more minutes for a reboot');
});

test('callWorst: two tries at the limit and one wait', () => {
  for (const g of of('callWorst')) assert.equal(callWorstS(g.limitS), g.worstS, `limit ${g.limitS}`);
});

const R = { answers: { status: 0, stdout: '', stderr: '' }, transient: { status: 1, stderr: 'ETIMEDOUT' }, permanent: { status: 1, stderr: 'boom' } };
test('call: the retry policy of a bounded simctl call replays the Lean call machine', () => {
  for (const g of of('call')) {
    const left = [...g.events];
    let used_ = 0, out = null;
    const stop = Symbol('script ends');
    try {
      out = withRetry(() => { if (!left.length) throw stop; used_++; return R[left.shift()]; }, { max: CALL.tries, text: (r) => r.stderr, sleepSync: () => {} });
    } catch (e) { if (e !== stop) throw e; }
    const phase = out === null ? `trying:${used_ + 1}` : out.status === 0 ? 'done' : /ETIMEDOUT/.test(out.stderr) ? 'failed:exhausted' : 'failed:refused';
    assert.equal(used_, g.used, g.name);
    assert.equal(out !== null, g.terminal, g.name);
    if (g.terminal) assert.equal(phase, g.phase, g.name);
  }
});

test('exec: the pass machine replays the Lean golden', () => {
  for (const g of of('exec')) {
    const s = exec(initPass(), g.events);
    assert.equal(s.phase, g.phase, g.name);
    assert.equal(s.attempt, g.attempt, g.name);
    assert.equal(s.relaunches, g.relaunches, g.name);
    assert.equal(s.reboots, g.reboots, g.name);
    assert.equal(terminal(s), g.terminal, g.name);
    assert.equal(used(initPass(), g.events), g.used, g.name);
    assert.equal(timeUsed(initPass(), g.events), g.timeS, g.name);
  }
});

test('no pass has two reboots, and a retry follows only an answer', () => {
  const evs = ['passOk', 'deadUp', 'deadDown', 'relaunchOk', 'relaunchFail', 'rebootOk', 'rebootFail'];
  const walk = (s, depth) => {
    assert.ok(s.reboots <= 1 && s.relaunches <= 1 && s.attempt <= 3);
    if (depth === 0) return;
    for (const e of evs) {
      const n = step(s, e);
      if (n.attempt === s.attempt + 1) assert.ok((s.phase === 'relaunching' && e === 'relaunchOk') || (s.phase === 'rebooting' && e === 'rebootOk'));
      walk(n, depth - 1);
    }
  };
  walk(initPass(), 5);
});

const UP = { socket: true, proxy: true, page: true };
const GONE = { socket: false, proxy: false, page: false };
const script = (...ps) => { let i = 0; return async () => ps[Math.min(i++, ps.length - 1)]; };
const rig = (probes, { up = true, relaunchFails = [], rebootFails = false, reboot: rb } = {}) => {
  const order = [], lines = [];
  let r = 0;
  const g = createGuard({
    probe: script(...probes), log: (s) => lines.push(s), tickMs: 5,
    deviceUp: async () => (typeof up === 'function' ? up() : up),
    relaunch: async () => { order.push('relaunch'); if (relaunchFails[r++]) throw new Error('boom'); },
    reboot: rb === null ? null : async () => { order.push('reboot'); if (rebootFails) throw new Error('no boot'); },
  });
  return { g, order, lines };
};

test('the device is down: reboot once, then Safari is launched again, and the check answers', async () => {
  const { g, order } = rig([GONE, UP], { up: false });
  const r = await g.check();
  assert.deepEqual(order, ['reboot', 'relaunch']);
  assert.equal(r.relaunched, true);
  assert.equal(g.rebooted, true);
  assert.equal((await g.check()).ok, true);
});

test('a failed relaunch reboots the device once and relaunches after the answer', async () => {
  const { g, order } = rig([GONE], { relaunchFails: [true] });
  await g.check();
  assert.deepEqual(order, ['relaunch', 'reboot', 'relaunch']);
});

test('dead again after the relaunch: one reboot; dead after both: named failure, no third try', async () => {
  const { g, order, lines } = rig([GONE, GONE, GONE]);
  await g.check();
  assert.deepEqual(order, ['relaunch']);
  await g.check();
  assert.deepEqual(order, ['relaunch', 'reboot', 'relaunch']);
  await assert.rejects(g.check(), (e) => e instanceof InspectorDeadError && e.exitCode === 4 && /dead again after Safari was relaunched and the device was rebooted/.test(e.message));
  assert.equal(order.filter((x) => x === 'reboot').length, 1);
  assert.ok(lines.some((l) => /giving up/.test(l) && /exit code 4/.test(l)));
});

test('a failed reboot ends the pass with a named failure and the relaunch is not tried after it', async () => {
  const { g, order } = rig([GONE], { up: false, rebootFails: true });
  await assert.rejects(g.check(), (e) => e instanceof InspectorDeadError && /rebooting the Simulator failed: no boot/.test(e.message));
  assert.deepEqual(order, ['reboot']);
});

test('a device check that throws counts as down; no reboot function is a failed reboot', async () => {
  const a = rig([GONE], { up: () => { throw new Error('x'); } });
  await a.g.check();
  assert.deepEqual(a.order, ['reboot', 'relaunch']);
  const b = rig([GONE], { up: false, reboot: null });
  await assert.rejects(b.g.check(), /no reboot is available/);
});

test('a check that comes during the recovery waits for it', async () => {
  let release;
  const gate = new Promise((r) => { release = r; });
  const order = [];
  const g = createGuard({
    probe: script(GONE, UP), tickMs: 5, deviceUp: async () => false,
    reboot: async () => { order.push('reboot start'); await gate; order.push('reboot end'); },
    relaunch: async () => { order.push('relaunch'); },
  });
  const first = g.check().then(() => order.push('first answered'));
  const second = g.check().then(() => order.push('second answered'));
  await new Promise((r) => setTimeout(r, 20));
  assert.deepEqual(order, ['reboot start']);
  release();
  await Promise.all([first, second]);
  assert.deepEqual(order, ['reboot start', 'reboot end', 'relaunch', 'first answered', 'second answered']);
});

test('relaunchTab shares the one Safari relaunch with the dead-inspector rule', async () => {
  const { g, order } = rig([GONE]);
  await g.check();
  await assert.rejects(g.relaunchTab(), /relaunched already/);
  assert.deepEqual(order, ['relaunch']);
});

const fake = (() => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-relaunch-'));
  const bin = join(dir, 'xcrun');
  writeFileSync(bin, [
    '#!/bin/sh', 'echo "$*" >> "$FAKE_LOG"',
    'case "$2" in',
    '  list) if [ -n "$FAKE_LIST_FAIL" ]; then echo "$FAKE_LIST_FAIL" >&2; exit 1; fi; cat "$FAKE_LIST_JSON";;',
    '  shutdown) echo "Unable to shutdown device in current state: Shutdown" >&2; exit 164;;',
    '  boot) [ -n "$FAKE_BOOT_FAIL" ] && { echo "boom" >&2; exit 1; }; exit 0;;',
    '  bootstatus) exit 0;;', 'esac', '',
  ].join('\n'));
  chmodSync(bin, 0o755);
  const devices = (state) => JSON.stringify({ devices: { 'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [{ udid: 'U1', name: 'fw-iphone-27', state, isAvailable: true }] } });
  const env = (o) => { for (const [k, v] of Object.entries(o)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } };
  return { dir, devices, env, log: join(dir, 'calls.log'), json: join(dir, 'list.json') };
})();
const withFake = async (f) => {
  const old = { PATH: process.env.PATH };
  fake.env({ PATH: `${fake.dir}:${process.env.PATH}`, FAKE_LOG: fake.log, FAKE_LIST_JSON: fake.json, FAKE_LIST_FAIL: undefined, FAKE_BOOT_FAIL: undefined });
  writeFileSync(fake.log, '');
  try { return await f(); } finally { fake.env({ ...old, FAKE_LOG: undefined, FAKE_LIST_JSON: undefined, FAKE_LIST_FAIL: undefined, FAKE_BOOT_FAIL: undefined }); }
};
const calls = () => readFileSync(fake.log, 'utf8').trim().split('\n').filter(Boolean).map((l) => l.split(' ').slice(0, 2).join(' '));

test('deviceBooted: Booted is up, Shutdown is down, no answer is down, no device known is up', async () => {
  await withFake(async () => {
    writeFileSync(fake.json, fake.devices('Booted'));
    assert.equal(await deviceBooted('U1'), true);
    writeFileSync(fake.json, fake.devices('Shutdown'));
    assert.equal(await deviceBooted('U1'), false);
    assert.equal(await deviceBooted(null), true);
    fake.env({ FAKE_LIST_FAIL: 'permanent failure' });
    assert.equal(await deviceBooted('U1'), false);
  });
});

test('rebootDevice: shutdown (an already shut-down device is fine), boot, bootstatus -b, in that order', async () => {
  await withFake(async () => {
    await rebootDevice({ udid: 'U1' });
    assert.deepEqual(calls(), ['simctl shutdown', 'simctl boot', 'simctl bootstatus']);
    await assert.rejects(rebootDevice({ udid: null }), /no Simulator device known/);
    fake.env({ FAKE_BOOT_FAIL: '1' });
    await assert.rejects(rebootDevice({ udid: 'U1' }), /simctl boot failed: boom/);
  });
});

test('listDevices: a service that does not answer is asked once more, then named as outside this process', async () => {
  await withFake(async () => {
    fake.env({ FAKE_LIST_FAIL: 'Connection invalid' });
    assert.throws(() => listDevices(), /simctl list devices failed: Connection invalid \(CoreSimulatorService does not answer: outside this process\)/);
    assert.deepEqual(calls(), ['simctl list', 'simctl list']);
  });
});

after(() => rmSync(fake.dir, { recursive: true, force: true }));
