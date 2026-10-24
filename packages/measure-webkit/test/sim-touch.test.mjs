// The touch-driver readiness / watchdog / retry machine against the Lean golden (Fw.Device.SimTouch, packages/contracts/golden/device/sim-touch.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SIM_TOUCH, presses, capS, stall, ready, initPass, terminal, step, exec, touchWatch, probeLoop, runGroup } from '../src/throttle/driver.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/sim-touch.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every golden kind has lines', () => {
  for (const k of ['consts', 'stall', 'cap', 'ready', 'exec']) assert.ok(of(k).length > 0, k);
});

test('constants', () => {
  const [c] = of('consts');
  for (const [k, v] of Object.entries(SIM_TOUCH)) assert.equal(c[k], v, k);
  assert.equal(Object.keys(c).length - 1, Object.keys(SIM_TOUCH).length);
});

test('the stall rule', () => {
  for (const g of of('stall')) assert.equal(stall(g.presses, g.elapsed, g.marks, g.since), g.verdict, JSON.stringify(g));
});

test('caps and the worst-case seconds', () => {
  for (const g of of('cap')) {
    assert.equal(presses(g.mode, g.cycles), g.presses, `${g.mode} ${g.cycles}`);
    assert.equal(capS(g.presses), g.capS);
    const passWorst = 2 * (SIM_TOUCH.probeBudgetS + g.capS) + SIM_TOUCH.restartS;
    assert.equal(passWorst, g.passWorstS);
    assert.equal(capS(2) + 5 * SIM_TOUCH.typicalPassS + passWorst, g.jobWorstS);
    assert.ok(g.jobWorstS <= SIM_TOUCH.stepLimitS || g.cycles > 4);
  }
});

test('readiness is all three', () => {
  for (const g of of('ready')) assert.equal(ready(g.sim, g.page, g.driver), g.ready, JSON.stringify(g));
});

test('the pass machine', () => {
  for (const g of of('exec')) {
    const { state, used } = exec(initPass(), g.events);
    assert.deepEqual([state.phase, state.attempt, state.restarts, terminal(state), used], [g.phase, g.attempt, g.restarts, g.terminal, g.used], g.name);
  }
});

test('a pass ends within passEvents events and restarts at most once, over every event sequence up to that length', () => {
  const evs = ['readyYes', 'readyNo', 'touchesOk', 'touchesFail', 'restartOk', 'restartFail'];
  let seqs = [[]];
  for (let len = 1; len <= SIM_TOUCH.passEvents; len++) {
    seqs = seqs.flatMap((s) => evs.map((e) => [...s, e]));
    for (const s of seqs) {
      const { state } = exec(initPass(), s);
      assert.ok(state.restarts <= 1 && state.attempt <= 2, s.join());
      if (len === SIM_TOUCH.passEvents) assert.ok(terminal(state), s.join());
      // a touching step is reached only by readyYes from probing; attempt 2 only after restartOk
      let st = initPass();
      for (const e of s) {
        const nx = step(st, e);
        if (nx.phase === 'touching') assert.ok(st.phase === 'probing' && e === 'readyYes');
        if (nx.attempt === 2 && st.attempt === 1) assert.ok(st.phase === 'restarting' && e === 'restartOk');
        st = nx;
      }
    }
  }
});

test('the touch watch keeps when each mark was first seen and applies the stall rule', () => {
  const w = touchWatch(8);
  assert.equal(w.verdict(10, []), 'ok');
  assert.equal(w.verdict(299, []), 'ok');
  assert.equal(w.verdict(300, []), 'startup');
  const v = touchWatch(8);
  assert.equal(v.verdict(100, ['started']), 'ok');
  assert.equal(v.verdict(150, ['started', 'press-1']), 'ok');
  assert.equal(v.verdict(269, ['started', 'press-1']), 'ok');
  assert.equal(v.verdict(270, ['started', 'press-1']), 'press');
  assert.equal(v.verdict(271, ['started', 'press-1', 'press-2']), 'ok');
  assert.deepEqual(v.seen.map((m) => [m.name, m.atS]), [['started', 100], ['press-1', 150], ['press-2', 271]]);
  assert.equal(v.verdict(capS(8), ['started', 'press-1', 'press-2']), 'cap');
});

test('the probe loop stops at the first yes, asks again after the gap, and gives up after the tries', async () => {
  const naps = [];
  const nap = async (ms) => { naps.push(ms); };
  let calls = 0;
  const flaky = { sim: () => true, page: () => ++calls >= 3, driver: () => true };
  const ok = await probeLoop(flaky, { nap });
  assert.deepEqual([ok.ready, ok.tries, naps], [true, 3, [10000, 10000]]);
  naps.length = 0;
  const never = await probeLoop({ sim: () => true, page: () => { throw new Error('no page'); }, driver: () => true }, { nap });
  assert.deepEqual([never.ready, never.tries, never.page, naps.length], [false, SIM_TOUCH.probeTries, false, SIM_TOUCH.probeTries - 1]);
});

test('runGroup stops a group the watch names, and kills it even when it ignores SIGTERM', async () => {
  const r = await runGroup(process.execPath, ['-e', "process.on('SIGTERM', () => {}); setInterval(() => {}, 1000)"],
    { timeoutMs: 60000, graceMs: 300, watch: { everyMs: 50, check: (ms) => (ms > 200 ? 'press' : null) } });
  assert.deepEqual([r.timedOut, r.killedBy, r.signal], [true, 'press', 'SIGKILL']);
  const ok = await runGroup(process.execPath, ['-e', ''], { timeoutMs: 60000 });
  assert.deepEqual([ok.code, ok.timedOut, ok.killedBy], [0, false, null]);
});
