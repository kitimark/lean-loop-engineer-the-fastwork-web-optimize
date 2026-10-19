import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bezier, compareSweeps, easingOf, pathError, transitions, wheelEdges } from '../src/navscroll-analyze.mjs';
import { gridOf, settledGrid } from '../src/navscroll.mjs';

const rec = (uw, hidden, extra = {}) => ({ uw, u: uw, y: uw + 1000, hidden, cls: hidden ? 'is-scroll-hidden' : '', vis: hidden ? 'hidden' : 'visible', top: hidden ? -88 : 16, stTop: 48, op: hidden ? 0 : 1, ...extra });

test('bezier: endpoints, linear, and the nav easing is fast at the start', () => {
  const lin = bezier(0, 0, 1, 1);
  assert.equal(lin(0), 0);
  assert.equal(lin(1), 1);
  assert.ok(Math.abs(lin(0.37) - 0.37) < 1e-5);
  const e = easingOf('cubic-bezier(0.16, 1, 0.3, 1)');
  assert.ok(e(0.1) > 0.45 && e(0.1) < 0.55);
  assert.equal(easingOf('steps(3)'), null);
});

test('transitions: the edges of the hidden flag with the step before them', () => {
  const steps = [rec(0, false), rec(16, false), rec(32, true), rec(48, true), rec(64, false)];
  assert.deepEqual(transitions(steps).map((t) => [t.to, t.u, t.uBefore]), [[true, 32, 16], [false, 64, 48]]);
  assert.deepEqual(transitions([rec(0, false)]), []);
});

test('compareSweeps: identical sweeps agree, a shifted onset is reported at its grid value', () => {
  const a = [rec(0, false), rec(16, true), rec(32, true)];
  assert.equal(compareSweeps(a, a).diff.hidden.length, 0);
  const b = [rec(0, false), rec(16, false), rec(32, true)];
  const d = compareSweeps(a, b);
  assert.deepEqual(d.diff.hidden.map((x) => x.uw), [16]);
  assert.equal(d.diff.cls.length, 1);
  assert.equal(d.diff.vis.length, 1);
  assert.equal(d.matched, 3);
});

test('compareSweeps: unmatched grid values are skipped, not counted as differences', () => {
  const a = [rec(0, false), rec(16, true)];
  const b = [rec(16, true), rec(32, true)];
  const d = compareSweeps(a, b);
  assert.equal(d.matched, 1);
  assert.equal(d.diff.hidden.length, 0);
});

test('pathError: frames on the browser easing curve have zero error, one off the curve is found', () => {
  const ease = easingOf('cubic-bezier(0.16, 1, 0.3, 1)');
  const anims = [{ prop: 'transform', startTime: 100, duration: 320, delay: 0, easing: 'cubic-bezier(0.16, 1, 0.3, 1)' }];
  const frames = [0, 16, 33, 50, 100, 200, 300].map((el) => ({ ct: 100 + el, ty: -88 * ease(el / 320), op: 1 }));
  assert.equal(pathError(frames, anims, { ty: 0, op: 1 }, { ty: -88, op: 0 }).transform.maxErr, 0);
  frames[3].ty += 5;
  assert.equal(pathError(frames, anims, { ty: 0, op: 1 }, { ty: -88, op: 0 }).transform.maxErr, 5);
  assert.equal(pathError(frames, anims, { ty: 0, op: 1 }, { ty: -88, op: 0 }).opacity, null);
});

test('wheelEdges: first hidden and first visible frame in each direction', () => {
  const r = (y, hidden) => ({ y, u: y - 1000, hidden });
  const rec2 = [r(900, false), r(1100, true), r(1500, true), r(2100, false), r(2400, false), r(2000, false), r(1600, true), r(1200, true), r(1000, false)];
  assert.deepEqual(wheelEdges(rec2), { downOn: 100, downOff: 1100, upOn: 600, upOff: 0, peakU: 1400, frames: 9 });
});

test('grids: sweep from one viewport above to half a viewport past the section, same values for equal geometry', () => {
  const g = { vh: 800, secH: 3200 };
  const us = gridOf(g, 16);
  assert.equal(us[0], -800);
  assert.ok(us.at(-1) <= 3600 && us.at(-1) > 3600 - 16);
  assert.deepEqual(settledGrid(g), [-800, -400, 0, 400, 800, 1200, 1600, 2000, 2400, 2800, 3200, 3600]);
});
