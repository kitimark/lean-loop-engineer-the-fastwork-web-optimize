import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { WK_KEYS, END_CUT, ZONES, windowSteps, windowVec, sameSteps, verdict, zoneVerdicts, passOf } from '../src/offscreen-webkit.mjs';
import { MIN_RUNS, SLACK } from '../../measure-chromium/src/offscreen.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/offscreen-webkit.jsonl', import.meta.url), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);

test('offscreen-webkit: constants match Lean', () => {
  const c = ops('constants')[0];
  assert.deepEqual(WK_KEYS, c.keys);
  assert.equal(END_CUT, c.endCut);
  assert.equal(MIN_RUNS, c.minRuns);
  assert.equal(SLACK, c.slack);
  assert.deepEqual(ZONES, c.zones);
});

test('offscreen-webkit: windows hold the steps and sums of the golden pass', () => {
  assert.equal(ops('window').length, 4);
  for (const g of ops('window')) {
    assert.deepEqual(windowSteps(g.lo, g.hi, g.pass), g.steps, `${g.lo}-${g.hi}`);
    const v = windowVec(g.lo, g.hi, g.pass);
    assert.equal(v.n, g.vec.n);
    assert.deepEqual(v.vals, g.vec.vals);
  }
});

test('offscreen-webkit: every golden verdict, and its step-set flag, matches Lean', () => {
  const vs = ops('verdict');
  assert.ok(vs.length >= 11);
  assert.deepEqual([...new Set(vs.map((g) => g.verdict))].sort(), ['gain', 'noData', 'noGain']);
  for (const g of vs) {
    assert.equal(sameSteps(g.lo, g.hi, [...g.base, ...g.flag]), g.sameSteps, `${g.case}: step sets`);
    assert.equal(verdict(g.lo, g.hi, g.base, g.flag), g.verdict, g.case);
  }
});

test('offscreen-webkit: equal counts on different steps get no verdict', () => {
  const g = ops('verdict').find((x) => x.case === 'same count, different steps');
  assert.equal(g.sameSteps, false);
  assert.equal(g.verdict, 'noData');
});

test('offscreen-webkit: zones are judged one by one', () => {
  assert.equal(ops('zones').length, 3);
  for (const g of ops('zones')) {
    assert.deepEqual(zoneVerdicts(g.base, g.flag), g.zones.map((z) => [z.zone, z.verdict]), g.case);
  }
});

test('offscreen-webkit: no zone reaches the page-end steps of either pass shape', () => {
  for (const z of ZONES) assert.ok(z.hi <= END_CUT && END_CUT < 5231);
});

test('offscreen-webkit: passOf reads a session pass', () => {
  const p = passOf({ scroll: { ys: [0, 50], reduced: { perStep: [[1], [2]] } } });
  assert.deepEqual(p, { ys: [0, 50], rows: [[1], [2]] });
});
