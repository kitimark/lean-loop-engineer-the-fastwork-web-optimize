// wave2.mjs: the staging, the whole-run totals and the labels it adds around fwcore's verdicts.
import assert from 'node:assert/strict';
import test from 'node:test';
import { bandCells, confounds, deltaRow, f6, median, pageDeltas, stageAs, totalsOf } from '../src/wave2.mjs';
import { variantKeys } from '../../../apps/runner/src/engine-check.ts';

const file = (frames, runLevel = {}) => ({ profile: { id: 'swipe-v1' }, meta: { target: 'rewrite', search: '?only=g2&stage=vw:430,vh:932' }, frames: frames.map((counts) => ({ counts })), runLevel });

test('totalsOf adds the frames and the run-level count', () => {
  assert.deepEqual(totalsOf(file([{ a: 1, b: 2 }, { a: 3 }], { b: 10, c: 4 })), { a: 4, b: 12, c: 4 });
});

test('median is the observed value at index floor((n-1)/2)', () => {
  assert.equal(median([5, 1, 3]), 3);
  assert.equal(median([4, 1, 3, 2]), 2);
});

test('deltaRow: below and above only when every arm run is outside the base range', () => {
  assert.equal(deltaRow([10, 11, 12], [8, 9, 9]).where, 'below');
  assert.equal(deltaRow([10, 11, 12], [13, 14, 13]).where, 'above');
  assert.equal(deltaRow([10, 11, 12], [9, 11, 13]).where, 'within');
  assert.deepEqual(deltaRow([10, 11, 12], [8, 9, 9]), { base: 11, arm: 9, delta: -2, baseRuns: [10, 11, 12], armRuns: [8, 9, 9], baseLo: 10, baseHi: 12, where: 'below' });
});

test('pageDeltas covers a type present in one arm only', () => {
  const d = pageDeltas([file([{ a: 1 }]), file([{ a: 1 }]), file([{ a: 1 }])], [file([{ a: 1, z: 2 }]), file([{ a: 1, z: 2 }]), file([{ a: 1, z: 2 }])]);
  assert.equal(d.z.base, 0);
  assert.equal(d.z.delta, 2);
});

test('stageAs: base answers rewrite, every arm file answers each declared variant, nothing else', () => {
  const staged = stageAs([{ path: 'b1', counts: file([{ a: 1 }]) }], [{ path: 'a1', counts: file([{ a: 2 }]) }], ['v1', 'v2']);
  assert.deepEqual(staged.map((s) => [s.source, s.variant]), [['b1', 'rewrite'], ['a1', 'v1'], ['a1', 'v2']]);
  for (const s of staged) assert.deepEqual(variantKeys(s.counts), [s.variant]);
  assert.equal(new Set(staged.map((s) => s.name)).size, 3);
});

test('confounds names other active variants that predict a change on the same type', () => {
  const rows = [
    { variant: 'x', countType: 't', prediction: '=o' },
    { variant: 'y', countType: 't', prediction: '<o' },
    { variant: 'z', countType: 't', prediction: '=o' },
    { variant: 'w', countType: 'u', prediction: '<o' },
    { variant: 'off', countType: 't', prediction: '<o' },
  ];
  assert.deepEqual(confounds(rows[0], rows, ['x', 'y', 'z', 'w']), ['y <o']);
  assert.deepEqual(confounds(rows[1], rows, ['x', 'y', 'z', 'w']), []);
});

test('bandCells compares per-run values of two baselines, a type missing on one side reads 0', () => {
  const cells = bandCells({ a: { perRun: [10, 10, 10], class: 'deterministic' } }, { a: { perRun: [7, 7, 7], class: 'deterministic' }, b: { perRun: [2, 2, 2], class: 'stable' } });
  assert.deepEqual(cells.map((c) => [c.type, c.class, c.delta, c.where]), [['a', 'deterministic', -3, 'below'], ['b', 'stable', 2, 'above']]);
});

test('f6: residual of the combined delta against the part sum, margin by class, quarantined not decidable', () => {
  const d = (x) => deltaRow([10, 10, 10], [10 + x, 10 + x, 10 + x]);
  const classes = { det: { class: 'deterministic', k: 0 }, st: { class: 'stable', k: 2 }, q: { class: 'quarantined', k: 6 } };
  const rows = f6(
    { det: d(-5), st: d(-6), q: d(-9), still: d(0) },
    [{ name: 'p1', deltas: { det: d(-3), st: d(-2), q: d(-4) } }, { name: 'p2', deltas: { det: d(-2), st: d(-3), q: d(-4) } }],
    classes);
  assert.deepEqual(rows.map((r) => [r.type, r.residual, r.strict, r.widened]), [['det', 0, true, true], ['q', -1, null, null], ['st', -1, true, true]]);
  const off = f6({ st: d(-8) }, [{ name: 'p1', deltas: { st: d(-2) } }, { name: 'p2', deltas: { st: d(-2) } }], classes);
  assert.deepEqual([off[0].residual, off[0].strict, off[0].widened], [-4, false, true]);
});

test('f6 with frames: the per-frame rates of the parts are summed against the combined rate', () => {
  const d = (x) => deltaRow([10, 10, 10], [10 + x, 10 + x, 10 + x]);
  const classes = { st: { class: 'stable', k: 2 } };
  const [r] = f6({ st: d(-10) }, [{ name: 'p1', deltas: { st: d(-18) } }, { name: 'p2', deltas: { st: d(-2) } }], classes, { combined: 5, parts: [10, 10] });
  assert.deepEqual([r.rate, r.rates, r.rateSum, r.rateWithin10pct, r.strict], [-2, [-1.8, -0.2], -2, true, false]);
});
