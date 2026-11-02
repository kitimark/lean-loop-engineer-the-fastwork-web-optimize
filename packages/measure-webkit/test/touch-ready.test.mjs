import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { READY_CFG, RESTART_CFG, LAUNCH_FAULTS, STOP_LATE, verdict, stopStep, replay, tallyJobs, launchUntilReady, jobOf, firstStart } from '../src/touch-ready.mjs';
import { READY_ALLOW_MS } from '../src/walk-budget.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/touch-ready.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ofOp = (op) => golden.filter((g) => g.op === op);

test('touch-ready constants and fault names equal the Lean golden', () => {
  const [g] = ofOp('constants');
  for (const k of ['launches', 'launchMs', 'killMs', 'stopWaitMs']) assert.equal(READY_CFG[k], g[k], k);
  assert.equal(READY_ALLOW_MS, g.readyAllowMs);
  assert.deepEqual([RESTART_CFG.launches, RESTART_CFG.launchMs], [g.restartLaunches, g.restartLaunchMs]);
  assert.ok(RESTART_CFG.launches * (RESTART_CFG.launchMs + RESTART_CFG.killMs) <= READY_ALLOW_MS);
  assert.deepEqual([LAUNCH_FAULTS.launchStuck, LAUNCH_FAULTS.bodyStuck, LAUNCH_FAULTS.ended], g.names);
  assert.equal(STOP_LATE, g.stopLateName);
  assert.ok(READY_CFG.launches * (READY_CFG.launchMs + READY_CFG.killMs) <= READY_ALLOW_MS);
});

test('verdict replays the Lean golden decisions, one case per branch', () => {
  const cases = ofOp('decide');
  for (const g of cases) assert.equal(verdict(READY_CFG, g.n, g.obs), g.act, g.case);
  for (const kind of ['ready', 'wait', 'relaunch:driver-launch-stuck', 'relaunch:driver-body-stuck', 'relaunch:driver-ended', 'give:driver-launch-stuck', 'give:driver-body-stuck', 'give:driver-ended']) {
    assert.ok(cases.some((g) => g.act === kind), kind);
  }
});

test('replay replays the Lean golden runs', () => {
  const runs = ofOp('run');
  for (const g of runs) assert.deepEqual(replay(READY_CFG, g.trajs), { ready: g.ready, faults: g.faults, ms: g.ms }, g.case);
  assert.ok(runs.length >= 10);
});

/** The real loop (launchUntilReady) on a virtual clock over the same recorded trajectories. */
function drive(trajs, cfg = READY_CFG) {
  let t = 0;
  const never = new Promise(() => {});
  const started = [];
  const start = (n) => {
    const tr = trajs[n - 1] ?? { aliveAt: null, readyAt: null, endedAt: null };
    const t0 = t;
    const at = (x) => x != null && t - t0 >= x;
    const state = { get ended() { return at(tr.endedAt); } };
    const h = { state, exited: never, kill() { h.killed = true; }, tr, at };
    started.push(h);
    return h;
  };
  const look = (h) => ({ alive: h.at(h.tr.aliveAt), ready: h.at(h.tr.readyAt) });
  return launchUntilReady({ start, look, now: () => t, sleep: async (ms) => { t += ms; }, cfg }).then((r) => ({ ...r, t, started }));
}

test('launchUntilReady agrees with the Lean runs: same readiness and faults, never more time', async () => {
  for (const g of ofOp('run')) {
    const r = await drive(g.trajs);
    assert.equal(r.handle != null, g.ready, g.case);
    assert.deepEqual(r.launches.map((l) => l.fault).filter(Boolean), g.faults, g.case);
    assert.ok(r.t <= g.ms, `${g.case}: ${r.t} <= ${g.ms}`);
    if (!g.trajs.some((x) => x.endedAt != null)) assert.equal(r.t, g.ms, g.case);
    assert.ok(r.t <= READY_ALLOW_MS, g.case);
  }
});

test('a restart gets one long launch: the Lean restart runs replay and the loop never relaunches', async () => {
  const runs = ofOp('runRestart');
  assert.ok(runs.length >= 5);
  for (const g of runs) {
    assert.deepEqual(replay(RESTART_CFG, g.trajs), { ready: g.ready, faults: g.faults, ms: g.ms }, g.case);
    const r = await drive(g.trajs, RESTART_CFG);
    assert.equal(r.handle != null, g.ready, g.case);
    assert.deepEqual(r.launches.map((l) => l.fault).filter(Boolean), g.faults, g.case);
    assert.equal(r.started.length, 1, g.case);
    assert.ok(r.t <= g.ms && r.t <= READY_ALLOW_MS, g.case);
  }
});

test('launchUntilReady kills every cut launch, keeps the ready one, and records alive and ready times', async () => {
  const r = await drive([{ aliveAt: null, readyAt: null, endedAt: null }, { aliveAt: 20000, readyAt: 50000, endedAt: null }]);
  assert.deepEqual(r.started.map((h) => !!h.killed), [true, false]);
  assert.deepEqual(r.launches.map((l) => ({ n: l.n, fault: l.fault, aliveAt: l.aliveAt, readyAt: l.readyAt })), [
    { n: 1, fault: 'driver-launch-stuck', aliveAt: null, readyAt: null }, { n: 2, fault: null, aliveAt: 20000, readyAt: 50000 }]);
});

test('launchUntilReady never starts a fourth launch and hands each cut launch to onCut before the kill', async () => {
  const cuts = [];
  let t = 0;
  const never = new Promise(() => {});
  let starts = 0;
  const r = await launchUntilReady({
    start: () => { starts++; const h = { state: { ended: false }, exited: never, kill() { h.killed = true; } }; return h; },
    look: () => ({ alive: false, ready: false }), now: () => t, sleep: async (ms) => { t += ms; },
    onCut: (rec, h) => cuts.push([rec.fault, h.killed === true]),
  });
  assert.equal(starts, READY_CFG.launches);
  assert.equal(r.handle, null);
  assert.deepEqual(cuts, Array(3).fill(['driver-launch-stuck', false]));
});

test('stopStep replays the Lean golden', () => {
  const cases = ofOp('stop');
  for (const g of cases) assert.equal(stopStep(READY_CFG, g.exited, g.waitedMs), g.act);
  assert.ok(cases.some((g) => g.act === STOP_LATE));
});

test('tallyJobs replays the Lean golden', () => {
  const cases = ofOp('tally');
  for (const g of cases) assert.deepEqual(tallyJobs(g.jobs), g.out, g.case);
  assert.ok(cases.length >= 4);
});

test('jobOf and firstStart read the launch records of the first start in either snapshot shape', () => {
  const recs = [{ n: 1, fault: 'driver-launch-stuck' }, { n: 2, fault: null }];
  assert.deepEqual(jobOf(recs), { faults: ['driver-launch-stuck'], ready: true });
  assert.deepEqual(jobOf([{ n: 1, fault: 'driver-ended' }]), { faults: ['driver-ended'], ready: false });
  assert.deepEqual(jobOf([]), { faults: [], ready: false });
  assert.deepEqual(firstStart({ touch: { launches: [{ tag: 'serve', launches: recs }, { tag: 'serve-r1', launches: [] }] } }), recs);
  assert.deepEqual(firstStart({ push: { launches: recs } }), recs);
  assert.deepEqual(firstStart({}), []);
});
