// The glue that feeds the Lean pass machine (Fw.Device.SimTouch) its events: pass-run.mjs with fake sessions, touches and Simulator.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { makePassRunner } from '../src/throttle/pass-run.mjs';

function lane(script, { reasonOf = () => null } = {}) {
  let touch = null;
  const calls = { shutdown: 0, warm: 0, passes: 0 };
  const state = { passes: [], failed: [], machine: [] };
  const deps = {
    withSession: async (fn) => fn({ c: { evaluate: async () => 'complete' } }),
    shutdownDevice: () => { calls.shutdown++; return true; },
    loadFresh: async () => {},
    dragPass: async () => { calls.warm++; return { code: 0 }; },
    setTouchHooks: () => {},
    lastTouch: () => touch,
    resetTouch: () => { touch = null; },
  };
  const passOf = async () => {
    const step = script[calls.passes++] ?? 'ok';
    if (step === 'driver') { touch = { tag: 't', ready: { ready: true }, code: null, logFile: '/nonexistent' }; return { drag: { code: null } }; }
    if (step === 'recorder') { touch = { tag: 't', ready: { ready: true }, code: 0, logFile: '/nonexistent' }; throw new Error('recorder not started'); }
    if (step === 'session') throw new Error('simctl launch Safari failed: ETIMEDOUT');
    touch = { tag: 't', ready: { ready: true }, code: 0, logFile: '/nonexistent' };
    return { drag: { code: 0 }, rec: { frames: 1 } };
  };
  const r = makePassRunner({ driver: {}, udid: 'u', drag: {}, log: () => {}, vm: '1', keep: true, settleMs: 0, outDir: mkdtempSync(join(tmpdir(), 'stt-')),
    siteOf: () => null, firstSiteArm: 'original', passOf, reasonOf, state, save: () => {} }, deps);
  return { r, state, calls };
}

test('a clean pass is done with no restart', async () => {
  const { r, state, calls } = lane(['ok']);
  await r.runArm('rewrite', 0);
  assert.deepEqual([state.machine[0].phase, state.machine[0].restarts, state.passes.length, state.failed], ['done', 0, 1, []]);
  assert.equal(calls.shutdown, 0);
});

test('a touch-driver failure restarts the Simulator once and the second try is the pass', async () => {
  const { r, state, calls } = lane(['driver', 'ok']);
  await r.runArm('lift', 0);
  assert.deepEqual([state.machine[0].phase, state.machine[0].restarts, state.machine[0].attempt, state.passes.length, state.failed], ['done', 1, 2, 1, []]);
  assert.deepEqual([calls.shutdown, calls.warm], [1, 1]);
});

test('two touch-driver failures end as a named failure after exactly one restart, and failed[] lists it', async () => {
  const { r, state, calls } = lane(['driver', 'driver', 'ok']);
  await r.runArm('lift', 0);
  assert.deepEqual([state.machine[0].phase, state.machine[0].restarts, calls.shutdown], ['failed:touchesFailed', 1, 1]);
  assert.deepEqual(state.failed, ['lift-r1: failed:touchesFailed']);
  assert.equal(state.passes.length, 1); // the record of the failed try is kept, named by failed[]
});

test('a session that never came up (no touch run started) is notReady and restarts', async () => {
  const { r, state, calls } = lane(['session', 'ok']);
  await r.runArm('original', 0);
  assert.deepEqual([state.machine[0].events.slice(0, 2), state.machine[0].phase, calls.shutdown], [['readyNo', 'restartOk'], 'done', 1]);
});

test('clean touches then a recorder failure are not a driver fault: no restart, one extra run', async () => {
  const { r, state, calls } = lane(['recorder', 'ok'], { reasonOf: (p) => (p.drag ? null : 'touch driver failed') });
  await r.runArm('rewrite', 0);
  assert.deepEqual([state.machine[0].restarts, state.machine[0].extra, state.machine[0].phase, state.passes.length, calls.shutdown], [0, 1, 'done', 1, 0]);
});

test('the extra run is not taken after a restart: a pass restarts the Simulator at most once in total', async () => {
  const { r, state, calls } = lane(['driver', 'recorder', 'ok'], { reasonOf: (p) => (p.drag ? null : 'touch driver failed') });
  await r.runArm('rewrite', 0);
  assert.deepEqual([state.machine[0].restarts, state.machine[0].extra, calls.shutdown, state.passes.length], [1, 0, 1, 0]);
  assert.deepEqual(state.failed, ['rewrite-r1: done without a record']);
});
