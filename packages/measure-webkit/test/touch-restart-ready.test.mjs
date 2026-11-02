import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, appendFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { READY_CFG, RESTART_CFG, STOP_LATE_TEARDOWN, GATE, RESTART_ALLOW_MS, GATE_OVERLAP, GATE_UNSURE, gateStep, launchUntilReady } from '../src/touch-ready.mjs';
import { stopServer, probeStop, restartGate } from '../src/touch-push.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/touch-ready.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ofOp = (op) => golden.filter((g) => g.op === op);

test('the restart gate constants and gateStep replay the Lean golden, one case per branch', () => {
  const [g] = ofOp('constants');
  assert.deepEqual([GATE.exitWaitMs, GATE.checks, GATE.gapMs, GATE.probeMs], [g.gateExitWaitMs, g.gateChecks, g.gateGapMs, g.gateProbeMs]);
  assert.equal(RESTART_ALLOW_MS, g.restartAllowMs);
  assert.deepEqual([GATE_OVERLAP, GATE_UNSURE], g.gateNames);
  const waitMs = GATE.exitWaitMs + GATE.checks * GATE.probeMs + (GATE.checks - 1) * GATE.gapMs;
  assert.equal(waitMs + RESTART_CFG.launches * (RESTART_CFG.launchMs + RESTART_CFG.killMs), g.restartMs);
  const cases = ofOp('gate');
  for (const c of cases) assert.equal(gateStep(GATE, c.exited, c.waitedMs, c.deviceOk, c.checked), c.act);
  for (const act of ['launch', 'wait-exit', 'recheck', `launch:${GATE_UNSURE}`, `launch:${GATE_OVERLAP}`, `launch:${GATE_OVERLAP},${GATE_UNSURE}`]) assert.ok(cases.some((c) => c.act === act), act);
});

test('stopServer reads the log again at the decision, and its host probes wait for probeStop', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-stop-test-'));
  const logFile = join(dir, 'x.log');
  writeFileSync(logFile, "Test Case '-[DriverUITests.PushServer testServe]' started.\n");
  const server = { dir, run: { exited: new Promise(() => {}), state: { ended: false }, logFile, kill: () => assert.fail('no kill') } };
  const cfg = { ...READY_CFG, stopWaitMs: 1000 };
  setTimeout(() => appendFileSync(logFile, "Test Case '-[DriverUITests.PushServer testServe]' passed (1 seconds).\n"), 250);
  const t0 = Date.now();
  await stopServer(server, { cfg });
  assert.ok(Date.now() - t0 >= 900);
  assert.equal(server.stopFault, STOP_LATE_TEARDOWN);
  assert.ok(server.stopAt >= t0);
  assert.equal(server.stopTrace.top, null);
  await probeStop(server, async () => ({ top: ['x'], health: { memFreePct: 40, simctlMs: 9 } }));
  assert.deepEqual(server.stopTrace.top, ['x']);
  await probeStop({ stopTrace: { top: null }, stopFault: null }, async () => assert.fail('a clean stop is not probed'));
  await probeStop(server, async () => { throw new Error('boom'); });
  assert.deepEqual(server.stopTrace.top, ['x']);
});

test('a body that ends only after the last poll is read at the final decision, not named a hung press', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-stop-test-'));
  const logFile = join(dir, 'x.log');
  writeFileSync(logFile, "Test Case '-[DriverUITests.PushServer testServe]' started.\n");
  const server = { dir, run: { exited: new Promise(() => {}), state: { ended: false }, logFile, kill: () => assert.fail('no kill') } };
  // The poll reads the log every fifth turn (500 ms); the body ends at 640 ms, after the turn at 500 ms and before the stop wait of 700 ms.
  setTimeout(() => appendFileSync(logFile, "Test Case '-[DriverUITests.PushServer testServe]' passed (1 seconds).\n"), 640);
  await stopServer(server, { cfg: { ...READY_CFG, stopWaitMs: 700 } });
  assert.equal(server.stopFault, STOP_LATE_TEARDOWN);
  assert.notEqual(server.stopTrace.bodyEndedMs, null);
});

const clock = () => { let t = 0; return { now: () => t, nap: async (ms) => { t += ms; }, at: () => t }; };
const ok = { socket: true, proxy: true, page: true };

test('restartGate with an exited driver and a live device launches at once', async () => {
  const s = { stopAt: 0, stopTrace: {}, run: { state: { ended: true }, exited: Promise.resolve() } };
  assert.equal(await restartGate(s, { ...clock(), probe: async () => ok }), 'launch');
  assert.deepEqual(s.stopTrace.gate, { act: 'launch', waitedMs: 0, checked: 1 });
});

test('restartGate names the overlap and the unsure device when the exit never comes and every check fails', async () => {
  const c = clock();
  const s = { stopAt: 0, stopTrace: {}, run: { state: { ended: false }, exited: new Promise(() => {}) } };
  let calls = 0;
  const act = await restartGate(s, { ...c, check: async () => { calls++; throw new Error('dead'); }, probe: async () => ok });
  assert.equal(act, `launch:${GATE_OVERLAP},${GATE_UNSURE}`);
  assert.ok(c.at() >= GATE.exitWaitMs);
  assert.equal(calls, GATE.checks);
  assert.equal(s.stopTrace.gate.err, 'dead');
});

test('restartGate names only the overlap when the exit never comes but the device answers', async () => {
  const s = { stopAt: 0, stopTrace: {}, run: { state: { ended: false }, exited: new Promise(() => {}) } };
  assert.equal(await restartGate(s, { ...clock(), probe: async () => ok }), `launch:${GATE_OVERLAP}`);
});

test('restartGate rechecks a device that answers late, then launches clean', async () => {
  const s = { stopAt: 0, stopTrace: {}, run: { state: { ended: true }, exited: Promise.resolve() } };
  const answers = [{ socket: true, proxy: false, page: false }, ok];
  assert.equal(await restartGate(s, { ...clock(), probe: async () => answers.shift() }), 'launch');
  assert.equal(s.stopTrace.gate.checked, 2);
});

test('restartGate counts a simctl that does not answer as an unsure device and records it', async () => {
  const s = { stopAt: 0, stopTrace: {}, run: { state: { ended: true }, exited: Promise.resolve() } };
  const act = await restartGate(s, { ...clock(), probe: async () => ({ ...ok, sim: false }) });
  assert.equal(act, `launch:${GATE_UNSURE}`);
  assert.deepEqual(s.stopTrace.gate, { act, waitedMs: GATE.gapMs * (GATE.checks - 1), checked: GATE.checks, sim: false });
  const t = { stopAt: 0, stopTrace: {}, run: { state: { ended: true }, exited: Promise.resolve() } };
  const answers = [{ ...ok, sim: false }, { ...ok, sim: true }];
  assert.equal(await restartGate(t, { ...clock(), probe: async () => answers.shift() }), 'launch');
});

test('launchUntilReady records when the first log byte appeared', async () => {
  let t = 0;
  const seen = [{ alive: false, ready: false, logged: false }, { alive: false, ready: false, logged: true }, { alive: true, ready: true, logged: true }];
  let i = 0;
  const got = await launchUntilReady({ start: () => ({ state: { ended: false }, kill() {}, exited: new Promise(() => {}) }), look: () => seen[Math.min(i++, 2)], now: () => t, sleep: async (ms) => { t += ms; }, cfg: READY_CFG });
  assert.equal(got.launches[0].loggedAt, 250);
  assert.equal(got.launches[0].readyAt, 500);
});
