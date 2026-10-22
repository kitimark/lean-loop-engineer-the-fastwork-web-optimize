import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { judge, stat, slotOf, outcome, kept, hitchesRecorded, baselineFloor, simFloor, quiet, ceilCenti, probeAct, mayRecord, Q, PROBE } from '../src/safari-local-reduce.mjs';

const rows = readFileSync(new URL('../../contracts/golden/sup/measure.jsonl', import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const byOp = (op) => rows.filter((r) => r.request.op === op);

test('the golden has every kind of row', () => {
  for (const op of ['measure.params', 'measure.judge', 'measure.floor', 'measure.simFloor', 'measure.stat', 'measure.outcome', 'measure.kept', 'measure.trace', 'measure.probeParams', 'measure.probeAct', 'measure.mayRecord']) assert.ok(byOp(op).length > 0, op);
});

test('judge replays the golden decisions (Fw.Sup.Measure.judge)', () => {
  for (const r of byOp('measure.judge')) {
    const got = judge(r.request.before, r.request.after, r.request.floorCenti);
    const want = r.response;
    assert.equal(got.decision, want.decision, r.name);
    if (want.decision === 'refuse') { assert.equal(got.phase, want.phase, r.name); assert.deepEqual(got.why, want.why, r.name); }
  }
});

test('baselineFloor and simFloor replay the golden (Fw.Sup.Measure.baselineFloor, simFloor)', () => {
  for (const r of byOp('measure.floor')) assert.equal(baselineFloor(r.request.readings), r.response.floorCenti, r.name);
  for (const r of byOp('measure.simFloor')) assert.equal(simFloor(r.request.boot, r.request.readings), r.response.floorCenti, r.name);
});

test('probeAct and mayRecord replay the golden (Fw.Sup.Measure.probeAct, mayRecord)', () => {
  for (const r of byOp('measure.probeAct')) assert.equal(probeAct(r.request), r.response.act, r.name);
  for (const r of byOp('measure.mayRecord')) assert.equal(mayRecord(r.request.freeMB), r.response.may, r.name);
});

test('the quiet rule never accepts a load above the idle floor plus the margin (Fw.Sup.Measure.quiet_load_le, judge_accept_load_le)', () => {
  const base = byOp('measure.judge')[0].request.before;
  for (const fl of [0, 150, 400, 800]) for (let load = Math.max(0, fl - 5); load <= fl + Q.loadMarginCenti + 5; load++) {
    const r = { ...base, loadCenti: load };
    assert.equal(quiet(r, fl), load <= fl + Q.loadMarginCenti, `floor ${fl} load ${load}`);
    const d = judge(r, { ...r, time: r.time + 1 }, fl);
    if (d.decision === 'accept') assert.ok(load <= ceilCenti(fl));
  }
});

test('a window with a floor, enough steady quiet readings and the median under the cap gives it; nothing else does (Fw.Sup.Measure.baselineFloor_some)', () => {
  const base = byOp('measure.floor')[0].request.readings;
  const at = (loads) => base.map((r, i) => ({ ...r, loadCenti: loads[i] }));
  assert.equal(baselineFloor(at(Array(8).fill(300))), 300);
  assert.equal(baselineFloor(at(Array(8).fill(Q.floorMaxCenti))), Q.floorMaxCenti);
  assert.equal(baselineFloor(at(Array(8).fill(Q.floorMaxCenti + 1))), null);
  assert.equal(baselineFloor(base.slice(0, Q.baseMinSamples - 1)), null);
  const f = baselineFloor(at([300, 300, 300, 300, 300, 300, 300, 300 + Q.baseSpreadCenti]));
  assert.ok(f !== null && 300 <= f && f <= 300 + Q.baseSpreadCenti);
});

test('stat and slot replay the golden (Fw.Sup.Measure.stat)', () => {
  for (const r of byOp('measure.stat')) {
    const { frames, ivs } = r.request;
    const { slot, ...s } = r.response;
    assert.deepEqual(stat(frames, ivs), s, r.name);
    assert.equal(slotOf(ivs), slot, r.name);
  }
});

test('outcome replays the golden (Fw.Sup.Measure.outcome)', () => {
  for (const r of byOp('measure.outcome')) assert.equal(outcome(r.request.arm, r.request.base), r.response.outcome, r.name);
});

test('kept leaves refused and stale passes out (Fw.Sup.Measure.kept)', () => {
  const dec = { a: 'accept', s: 'stale', rb: 'refuse', ra: 'refuse' };
  for (const r of byOp('measure.kept')) {
    const xs = r.request.decisions.map((n, i) => [dec[n], r.request.values[i]]);
    assert.deepEqual(kept(xs), r.response.kept, r.name);
  }
});

test('hitchesRecorded replays the golden (Fw.Sup.Measure.hitchesRecorded)', () => {
  for (const r of byOp('measure.trace')) assert.equal(hitchesRecorded(r.request.finalized, r.request.rows), r.response.recorded, r.name);
});

test('the parameters come from the golden', () => {
  assert.equal(Q.minPasses, 3);
  assert.equal(Q.loadMaxCenti, undefined, 'the load ceiling is no constant: it is the idle floor plus Q.loadMarginCenti');
  assert.ok(PROBE.hardGraceS >= PROBE.graceS);
  assert.equal(Q.longTenths, 250);
});
