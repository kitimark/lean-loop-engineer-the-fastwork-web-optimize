// `merge` pairs rows across sessions by key (Lean: StepAlign.pairedRows / unpairedRows, op measure.webkit.pairRows).
// The fixture reproduces the VM2 case of CI run 39053799594: one VM measured a document 1 px taller, so its census state
// label is `y=5268` where the other VMs have `y=5267`. Needs lean/.lake/build/bin/fwcore (cd lean && lake build).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mergeSessions, rowKeys, unpairedTable } from '../src/mergerows.mjs';

const census = (y, layerCount) => ({ requestedY: y, scrollY: y, layerCount, memoryBytes: layerCount * 1000, reasonCounts: { a: 1 }, paintCountTotal: 10, paintDeltaTotal: 2, paintWindowMs: 500, layers: [] });
const step = (v) => [v, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
const pass = (ys, maxY, layerCount) => ({
  census: [census(0, layerCount), census(maxY, layerCount)],
  scroll: { ys, reduced: { perStep: ys.map(() => step(1)), perStepPaintArea: ys.map(() => 0), total: Object.fromEntries(['RecalculateStyles', 'Layout', 'Paint', 'Composite', 'RenderingFrame', 'EventDispatch', 'FireAnimationFrame', 'ObserverCallback', 'FunctionCall', 'ResizeObserver', 'IntersectionObserver', 'TimerFire'].map((t, j) => [t, j === 0 ? ys.length : 0]).concat([['paintArea', 0]])) } },
});
const session = (maxY, layerCount = 7) => [pass([0, 50, maxY], maxY, layerCount), pass([0, 50, maxY], maxY, layerCount)];

test('rowKeys makes a repeated row unique within a session', () => {
  assert.deepEqual(rowKeys([{ family: 'f', metric: 'm', level: 'l' }, { family: 'f', metric: 'm', level: 'l' }]), ['f|m|l', 'f|m|l#2']);
});

test('a census label only one VM has (y=5268) is unpaired with its count; the rest merges, no crash', async () => {
  const r = await mergeSessions([session(5267), session(5268), session(5267)]);
  // the 1 px taller VM has the label y=5268 (1 of 3 sessions), the two others y=5267 (2 of 3): neither pairs
  assert.deepEqual(r.unpaired.map((u) => [u.key, u.sessions, u.of]), [
    ['census|layerCount|y=5267', 2, 3], ['census|backing memory bytes (sum)|y=5267', 2, 3],
    ['census|layerCount|y=5268', 1, 3], ['census|backing memory bytes (sum)|y=5268', 1, 3],
  ]);
  assert.ok(r.unpaired.every((u) => new RegExp(`present in ${u.sessions} of 3 sessions`).test(u.reason)));
  const keys = r.out.map((x) => x.key);
  assert.ok(keys.includes('scroll|Layout|total') && keys.includes('census|layerCount|y=0'));
  assert.ok(!keys.some((k) => k.includes('y=5268') || k.includes('y=5267')));
  assert.ok(r.out.every((x) => x.classes.length === 3));
  assert.match(unpairedTable(r.unpaired), /census\|layerCount\|y=5268 \| 1 of 3 \|/);
});

test('same labels everywhere: nothing unpaired, worse class wins', async () => {
  const r = await mergeSessions([session(5267), session(5267, 9), session(5267)]);
  assert.deepEqual(r.unpaired, []);
  const row = r.out.find((x) => x.key === 'census|layerCount|y=0');
  assert.equal(row.classes.length, 3);
  assert.equal(unpairedTable([]), '');
});
