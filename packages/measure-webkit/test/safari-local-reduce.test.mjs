import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { judge, stat, slotOf, outcome, kept, hitchesRecorded, Q } from '../src/safari-local-reduce.mjs';

const rows = readFileSync(new URL('../../contracts/golden/sup/measure.jsonl', import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const byOp = (op) => rows.filter((r) => r.request.op === op);

test('the golden has every kind of row', () => {
  for (const op of ['measure.params', 'measure.judge', 'measure.stat', 'measure.outcome', 'measure.kept', 'measure.trace']) assert.ok(byOp(op).length > 0, op);
});

test('judge replays the golden decisions (Fw.Sup.Measure.judge)', () => {
  for (const r of byOp('measure.judge')) {
    const got = judge(r.request.before, r.request.after);
    const want = r.response;
    assert.equal(got.decision, want.decision, r.name);
    if (want.decision === 'refuse') { assert.equal(got.phase, want.phase, r.name); assert.deepEqual(got.why, want.why, r.name); }
  }
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
  assert.equal(Q.longTenths, 250);
});
