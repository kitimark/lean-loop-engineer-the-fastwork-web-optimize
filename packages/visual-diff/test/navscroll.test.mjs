import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bezier, compareSweeps, compareTransitionFrames, easingOf, eventSequence, frameIndexes, lagSummary, pathError, transitions, wheelEdges } from '../src/navscroll-analyze.mjs';
import { gridOf, settledGrid } from '../src/navscroll.mjs';
import { edgeDeltas, settledDiffs, wheelDelta } from '../src/navscroll-report.mjs';

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

test('settledDiffs: only positions whose final hidden flag differs, with the flag over time', () => {
  const e = (h) => [50, 250, 500].map((t) => ({ t, hidden: h }));
  const o = [{ uw: 0, u: 51, hidden: true, early: e(true) }, { uw: 540, u: 591, hidden: true, early: e(true) }];
  const p = [{ uw: 0, u: 49, hidden: false, early: e(false) }, { uw: 540, u: 589, hidden: true, early: e(true) }];
  assert.deepEqual(settledDiffs(o, p), [{ uw: 0, u: { orig: 51, rewrite: 49 }, orig: '50ms H, 250ms H, 500ms H, end H', rewrite: '50ms V, 250ms V, 500ms V, end V' }]);
});

test('grids: sweep from one viewport above to half a viewport past the section, same values for equal geometry', () => {
  const g = { vh: 800, secH: 3200 };
  const us = gridOf(g, 16);
  assert.equal(us[0], -800);
  assert.ok(us.at(-1) <= 3600 && us.at(-1) > 3600 - 16);
  assert.deepEqual(settledGrid(g), [-800, -400, 0, 400, 800, 1200, 1600, 2000, 2400, 2800, 3200, 3600]);
});

// A captured transition: `tys` is translateY per frame, `flipAt` the frame whose hidden flag turns, `st` the transform start time.
const trec = (tys, flipAt, { before = 0, st = null } = {}) => ({
  before: { hidden: false, ty: before },
  frames: tys.map((ty, i) => ({ ct: 1000 + i * 16.667, hidden: i >= flipAt, ty, run: st == null ? [] : [{ prop: 'transform', st, pend: false, cur: 0 }] })),
});

test('frameIndexes: flip frame, first move frame, lag and start frame', () => {
  const r = trec([0, 0, 0, -25, -44, -58], 2, { st: 1000 + 3 * 16.667 });
  assert.deepEqual(frameIndexes(r), { flip: 2, move: 3, start: 3, lagMove: 1, lagStart: 1 });
  // moved in the same frame as the flip (lag 0), no start time recorded
  assert.deepEqual(frameIndexes(trec([0, 0, -25, -44], 2)), { flip: 2, move: 2, start: null, lagMove: 0, lagStart: null });
  // never flips, never moves
  assert.deepEqual(frameIndexes(trec([0, 0, 0], 9)), { flip: -1, move: -1, start: null, lagMove: null, lagStart: null });
});

test('compareTransitionFrames: a later start shows as a longer lag; the curve from the first move is equal', () => {
  const o = trec([0, 0, 0, -25, -44, -58, -67, -73, -77, -80], 2);
  const p = trec([0, 0, 0, 0, -25, -44, -58, -67, -73, -77], 2);
  const c = compareTransitionFrames(o, p);
  assert.deepEqual([c.flip.orig, c.flip.port, c.move.orig, c.move.port, c.lag.orig, c.lag.port, c.lagDelta], [2, 2, 3, 4, 1, 2, 1]);
  assert.equal(c.aligned, 0);
  assert.deepEqual(c.ty.orig.slice(0, 5), [0, 0, 0, -25, -44]);
  assert.deepEqual(c.ty.port.slice(0, 5), [0, 0, 0, 0, -25]);
  // a missing edge in one arm gives null, not 0
  assert.equal(compareTransitionFrames(o, trec([0, 0, 0], 9)).lagDelta, null);
});

test('eventSequence: events up to the first move, repeats collapsed; null without a log', () => {
  const r = { ...trec([0, 0, 0, -25, -44], 2), ev: [
    { e: 'frame' }, { e: 'scroll' }, { e: 'frame' }, { e: 'class' }, { e: 'transitionrun:transform' }, { e: 'frame' }, { e: 'transitionstart:transform' }, { e: 'frame' }, { e: 'frame' }, { e: 'frame' },
  ] };
  assert.equal(eventSequence(r), 'f s f c tr f ts f');
  assert.equal(eventSequence(trec([0, 0, 0], 9)), null);
});

test('lagSummary: counts longer / shorter / equal per engine, width and edge; skips edges missing in an arm', () => {
  const rows = [
    { run: 'a', engine: 'chromium', id: 'w1280', key: 'down:off', orig: 1, port: 2 },
    { run: 'b', engine: 'chromium', id: 'w1280', key: 'down:off', orig: 1, port: 1 },
    { run: 'c', engine: 'chromium', id: 'w1280', key: 'down:off', orig: 2, port: 1 },
    { run: 'd', engine: 'chromium', id: 'w1280', key: 'down:off', orig: 1, port: null },
  ];
  const [g] = lagSummary(rows);
  assert.deepEqual([g.orig, g.port, g.longer, g.shorter, g.equal], [[1, 1, 2], [2, 1, 1], 1, 1, 1]);
});

test('edgeDeltas: live-u difference per edge, port minus original; different edge counts are named', () => {
  const orig = [rec(0, false, { u: 0 }), rec(16, true, { u: 16.5 }), rec(32, false, { u: 32.5 })];
  const port = [rec(0, false, { u: 0 }), rec(16, true, { u: 15.5 }), rec(32, false, { u: 31.5 })];
  assert.equal(edgeDeltas(orig, port), 'on -1.00, off -1.00');
  assert.equal(edgeDeltas(orig, orig), 'on +0.00, off +0.00');
  assert.equal(edgeDeltas(orig, [rec(0, false), rec(16, false)]), 'edges 2 vs 0');
});

test('wheelDelta: the largest edge difference; null when an edge is missing in an arm', () => {
  const e = { downOn: 100, downOff: 2500, upOn: 2600, upOff: 200 };
  assert.equal(wheelDelta({ orig: e, rewrite: { ...e, downOff: 2400 } }), 100);
  assert.equal(wheelDelta({ orig: e, rewrite: { ...e, upOn: null } }), null);
  assert.equal(wheelDelta({ orig: e, rewrite: null }), null);
});
