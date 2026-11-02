import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { RESET_CALL_MS, RESET_LATE, RESET_FAILED, GATE_OVERLAP, GATE_UNSURE, resetAct, callEnd, nameWith, launchUntilReady, READY_CFG } from '../src/touch-ready.mjs';
import { restartReset, DRIVER_APPS } from '../src/touch-push.mjs';
import { beginServer, launchesView } from '../src/touchlock-run.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/touch-ready.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ofOp = (op) => golden.filter((g) => g.op === op);

test('the reset constants, callEnd and nameWith replay the Lean golden, every branch present', () => {
  const [g] = ofOp('constants');
  assert.equal(RESET_CALL_MS, g.resetCallMs);
  assert.deepEqual([RESET_LATE, RESET_FAILED], g.resetNames);
  const calls = ofOp('call');
  for (const c of calls) assert.equal(callEnd(c.timedOut, c.code, c.nothingToTerminate), c.end);
  for (const e of ['ended', 'absent', 'late', 'failed']) assert.ok(calls.some((c) => c.end === e), e);
  const resets = ofOp('reset');
  const gateAct = (c) => (c.overlap || c.unsure ? `launch:${[...(c.overlap ? [GATE_OVERLAP] : []), ...(c.unsure ? [GATE_UNSURE] : [])].join(',')}` : 'launch');
  for (const c of resets) {
    assert.equal(resetAct(gateAct(c)), c.reset);
    assert.equal(nameWith(gateAct(c), c.ends), c.act);
  }
  for (const r of ['run', 'skip']) assert.ok(resets.some((c) => c.reset === r), r);
  assert.equal(resetAct('wait-exit'), 'skip');
  assert.equal(resetAct('recheck'), 'skip');
});

const udid = 'u';
const never = () => new Promise(() => {});
const ended = async (_u, app) => ({ app, end: 'ended', ms: 1 });

test('restartReset terminates both apps when the old xcodebuild exited and records the trace', async () => {
  const asked = [];
  const server = { stopTrace: {} };
  const got = await restartReset(server, 'launch', { udid, timer: never, terminate: async (u, app, ms) => { asked.push([u, app, ms]); return { app, end: app === DRIVER_APPS[0] ? 'ended' : 'absent', ms: 3 }; } });
  assert.deepEqual(got, { act: 'launch', ends: ['ended', 'absent'] });
  assert.deepEqual(asked, DRIVER_APPS.map((a) => [udid, a, RESET_CALL_MS]));
  assert.equal(server.stopTrace.reset.state, 'done');
  assert.deepEqual(server.stopTrace.reset.calls.map((c) => c.end), ['ended', 'absent']);
});

test('restartReset kills nothing when the old xcodebuild is still alive (overlap)', async () => {
  const server = { stopTrace: {} };
  const act = `launch:${GATE_OVERLAP}`;
  const got = await restartReset(server, act, { udid, timer: never, terminate: async () => assert.fail('no terminate on an overlap') });
  assert.deepEqual(got, { act, ends: [] });
  assert.equal(server.stopTrace.reset, undefined);
  for (const a of ['wait-exit', 'recheck', `launch:${GATE_OVERLAP},${GATE_UNSURE}`]) assert.deepEqual((await restartReset(server, a, { udid, timer: never, terminate: async () => assert.fail('no terminate') })).ends, []);
});

test('a terminate that does not finish within the Lean call time is named driver-restart-reset-late, and the launch still follows', async () => {
  const asked = [];
  const server = { stopTrace: {} };
  const got = await restartReset(server, `launch:${GATE_UNSURE}`, {
    udid, terminate: (u, app) => (app === DRIVER_APPS[0] ? never() : ended(u, app)), timer: (ms) => { asked.push(ms); return asked.length === 1 ? Promise.resolve() : never(); },
  });
  assert.equal(got.act, `launch:${GATE_UNSURE},${RESET_LATE}`);
  assert.deepEqual(got.ends.sort(), ['ended', 'late']);
  assert.deepEqual(asked, [RESET_CALL_MS, RESET_CALL_MS]);
  assert.equal(server.stopTrace.reset.act, got.act);
});

test('a terminate that fails for another reason is named driver-restart-reset-failed; a throw counts as failed', async () => {
  const got = await restartReset({ stopTrace: {} }, 'launch', { udid, timer: never, terminate: async (_u, app) => { if (app === DRIVER_APPS[1]) throw new Error('boom'); return { app, end: 'failed', ms: 1 }; } });
  assert.equal(got.act, `launch:${RESET_FAILED}`);
  assert.deepEqual(got.ends, ['failed', 'failed']);
});

test('both reset faults are named together, after the gate names', async () => {
  const ends = { [DRIVER_APPS[0]]: 'late', [DRIVER_APPS[1]]: 'failed' };
  const got = await restartReset({ stopTrace: {} }, `launch:${GATE_UNSURE}`, { udid, timer: never, terminate: async (_u, app) => ({ app, end: ends[app], ms: 1 }) });
  assert.equal(got.act, `launch:${GATE_UNSURE},${RESET_LATE},${RESET_FAILED}`);
});

test('the driver apps are the bundle ids of the built runner and host app', () => {
  const project = readFileSync(new URL('../src/throttle/driver/project.yml', import.meta.url), 'utf8');
  const ids = [...project.matchAll(/PRODUCT_BUNDLE_IDENTIFIER: (\S+)/g)].map((m) => m[1]);
  assert.deepEqual([...DRIVER_APPS].sort(), [`${ids.find((i) => i.endsWith('throttle-driver'))}.xctrunner`, ids.find((i) => i.endsWith('throttle-host'))].sort());
});

test('beginServer records a launch in flight before the start resolves, and the snapshot view says how long it has run', async () => {
  const touch = { driver: 'd', restarts: 1, server: null, on: true, why: null, launches: [{ tag: 'serve', launches: [{ n: 1, fault: null }] }] };
  let release;
  const gate = new Promise((r) => { release = r; });
  let seenRecords = null;
  const start = async (_d, o) => { seenRecords = o.records; o.records.push({ n: 1, fault: null, ms: 0, aliveAt: null, readyAt: null }); await gate; return { launches: o.records }; };
  const begun = beginServer(touch, { udid: 'u', log: () => {}, push: {}, start, now: () => 1000 });
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(touch.launches.length, 2);
  const view = launchesView(touch.launches, 1500);
  assert.equal(view[1].tag, 'serve-r1');
  assert.equal(view[1].inFlight, true);
  assert.equal(view[1].inFlightMs, 500);
  assert.equal(view[1].launches.length, 1);
  assert.equal(view[0].inFlight, undefined);
  assert.equal(view[0].inFlightMs, undefined);
  release();
  await begun;
  assert.deepEqual(touch.launches[1], { tag: 'serve-r1', launches: seenRecords });
  assert.equal(launchesView(touch.launches, 9999)[1].inFlight, undefined);
});

test('a start that throws leaves a settled entry with its fault, not an in-flight one', async () => {
  const touch = { driver: 'd', restarts: 1, server: null, on: true, why: null, launches: [] };
  await beginServer(touch, { udid: 'u', log: () => {}, push: {}, start: async () => { throw Object.assign(new Error('x'), { launches: [{ n: 1, fault: 'driver-launch-stuck' }], fault: 'driver-launch-stuck' }); } });
  assert.deepEqual(touch.launches, [{ tag: 'serve-r1', launches: [{ n: 1, fault: 'driver-launch-stuck' }], fault: 'driver-launch-stuck' }]);
  assert.equal(touch.on, false);
});

test('launchUntilReady pushes each record into a given array when its launch begins', async () => {
  let t = 0;
  const live = [];
  let lenAtLook = -1;
  const got = await launchUntilReady({
    start: () => ({ state: { ended: false }, kill() {}, exited: new Promise(() => {}) }),
    look: () => { lenAtLook = live.length; return { alive: true, ready: true, logged: true }; },
    now: () => t, sleep: async (ms) => { t += ms; }, cfg: READY_CFG, launches: live,
  });
  assert.equal(lenAtLook, 1);
  assert.equal(got.launches, live);
});
