import { test } from 'node:test';
import assert from 'node:assert/strict';
import { quadArea, flattenRecords, tally, markTimes, markTime, bucketBySteps, reduceSteps, zones, classify, symDiff, TOL, COUNT_TYPES, layerKey, compositeCuts, reduceWindows } from '../src/reduce.mjs';

test('quadArea of a rectangle and of nothing', () => {
  assert.equal(quadArea([0, 0, 10, 0, 10, 5, 0, 5]), 50);
  assert.equal(quadArea(null), 0);
  assert.equal(quadArea([1, 2, 3]), 0);
});

const rec = (type, t, extra = {}) => ({ type, startTime: t, endTime: t + 0.001, ...extra });

test('flattenRecords walks children and keeps clip / mark message', () => {
  const rows = flattenRecords([
    rec('FireAnimationFrame', 1, { children: [rec('FunctionCall', 1.1)] }),
    rec('Paint', 2, { data: { clip: [0, 0, 2, 0, 2, 2, 0, 2] } }),
    rec('TimeStamp', 3, { data: { message: 'wk:s0' } }),
  ]);
  assert.deepEqual(rows.map((r) => r[0]), ['FireAnimationFrame', 'FunctionCall', 'Paint', 'TimeStamp']);
  assert.deepEqual(rows[2][3], [0, 0, 2, 0, 2, 2, 0, 2]);
  assert.equal(rows[3][3], 'wk:s0');
});

test('tally counts the fixed types, area, and reports other types', () => {
  const t = tally([['Layout', 0, 0, null], ['Layout', 0, 0, null], ['Paint', 0, 0, [0, 0, 4, 0, 4, 4, 0, 4]], ['EvaluateScript', 0, 0, null], ['TimeStamp', 0, 0, 'x']]);
  assert.equal(t.counts.Layout, 2);
  assert.equal(t.counts.Paint, 1);
  assert.equal(t.paintArea, 16);
  assert.deepEqual(t.other, { EvaluateScript: 1 });
  assert.deepEqual(Object.keys(t.counts), [...COUNT_TYPES]);
});

test('markTimes / markTime find named TimeStamp rows', () => {
  const rows = [['TimeStamp', 1, null, 'wk:s0'], ['TimeStamp', 2, null, 'wk:s1'], ['TimeStamp', 9, null, 'wk:end']];
  assert.deepEqual(markTimes(rows, 'wk:s', 3), [1, 2, null]);
  assert.equal(markTime(rows, 'wk:end'), 9);
  assert.equal(markTime(rows, 'nope'), null);
});

test('bucketBySteps: half-open windows, rows before the first mark and after the end are dropped', () => {
  const rows = [['Layout', 0.5], ['Layout', 1], ['Layout', 1.9], ['Paint', 2], ['Layout', 3.5], ['Layout', 4]].map((r) => [r[0], r[1], null, null]);
  const { steps, before } = bucketBySteps(rows, [1, 2, 3], 4);
  assert.equal(before, 1);
  assert.deepEqual(steps.map((s) => s.length), [2, 1, 1]);
});

test('reduceSteps and zones', () => {
  const rows = [['RecalculateStyles', 1, null, null], ['Layout', 2.5, null, null], ['Layout', 3.5, null, null], ['Paint', 3.6, null, [0, 0, 1, 0, 1, 1, 0, 1]]];
  const r = reduceSteps(rows, [1, 2, 3], 4);
  assert.equal(r.total.Layout, 2);
  assert.equal(r.perStep.length, 3);
  assert.equal(r.perStepPaintArea[2], 1);
  const z = zones([0, 400, 800], r.perStep, r.perStepPaintArea, 500);
  assert.equal(z.length, 2);
  assert.equal(z[0].steps, 2);
  assert.equal(z[1].counts[COUNT_TYPES.indexOf('Layout')], 1);
});

test('classify: deterministic, stable, quarantined, length mismatch', () => {
  assert.equal(classify([[1, 2, 3], [1, 2, 3]], TOL.step).cls, 'deterministic');
  assert.equal(classify([[1, 2, 3], [1, 3, 3]], TOL.step).cls, 'stable');
  assert.equal(classify([[1, 2, 3], [1, 5, 3]], TOL.step).cls, 'quarantined');
  assert.equal(classify([[100], [104]], TOL.total).cls, 'stable'); // 4 <= max(2, 5)
  assert.equal(classify([[100], [110]], TOL.total).cls, 'quarantined');
  assert.equal(classify([[1, 2], [1]], TOL.step).cls, 'quarantined');
  assert.equal(classify([[0], [1]], TOL.exact).cls, 'quarantined');
  assert.equal(classify([[1], [1], [2]], TOL.step).cls, 'stable'); // spread over three runs
  assert.throws(() => classify([[1]], TOL.step));
});

test('symDiff is a multiset symmetric difference', () => {
  assert.equal(symDiff(['a', 'b'], ['b', 'a']), 0);
  assert.equal(symDiff(['a', 'a', 'b'], ['a', 'c']), 3);
});

test('layerKey leaves session ids out', () => {
  const l = { name: 'div.x', pseudo: null, bounds: '0,0,1,1', compositedBounds: '0,0,1,1', memory: 4, reasons: ['a', 'b'], layerId: '0.9', nodeId: 7 };
  assert.equal(layerKey(l), 'div.x||0,0,1,1|0,0,1,1|4|a+b');
});

test('compositeCuts: the cut is the end of the first Composite of the step; no Composite -> next mark', () => {
  const rows = [
    ['Layout', 0.5, 0.6, null],
    ['Composite', 1.2, 1.3, null], ['Composite', 1.5, 1.6, null],
    ['Layout', 2.1, 2.2, null],
    ['Composite', 3.2, null, null],
  ];
  // steps: [1,2) [2,3) [3,4); step 1 has no Composite
  assert.deepEqual(compositeCuts(rows, [1, 2, 3], 4), [1.3, 3, 3.2]);
});

test('reduceWindows counts from the first Composite on and keeps the window sum below the step sum', () => {
  const rows = [
    ['Layout', 1.1, 1.15, null], // before step 0's first Composite: not in its window
    ['Composite', 1.2, 1.3, null],
    ['Layout', 1.4, 1.5, null],
    ['Layout', 2.1, 2.2, null], ['Composite', 2.3, 2.4, null], ['Layout', 2.5, 2.6, null],
  ];
  const w = reduceWindows(rows, [1, 2], 3);
  const i = COUNT_TYPES.indexOf('Layout'), c = COUNT_TYPES.indexOf('Composite');
  assert.deepEqual(w.perStep.map((r) => r[i]), [2, 1]);
  assert.deepEqual(w.perStep.map((r) => r[c]), [1, 0]);
  assert.equal(w.total.Layout, 3);
  // the Layout at 1.1 is dropped (before cut[0]); the Composite at 2.3 lies in window 0 (window 1 starts at its end 2.4)
  assert.equal(reduceSteps(rows, [1, 2], 3).total.Layout, 4);
});
