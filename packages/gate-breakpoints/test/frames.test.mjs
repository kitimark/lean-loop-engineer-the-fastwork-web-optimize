// frames.mjs: the strip decisions. `usable` is the TS stand-in of Lean Fw.Gate.Frames.usable (its #guard cases are repeated here);
// shot intervals, columns and the index are glue checked on small cases.
import test from 'node:test';
import assert from 'node:assert/strict';
import { MIN_SHOTS, usable, labelOf, shotsOfFrames, columnsOf, cropOf, pooled } from '../src/trajectory/frames.mjs';

test('usable: both arms need MIN_SHOTS shots (Lean usable_iff, not_usable_faithful, not_usable_flag, usable_comm)', () => {
  assert.equal(MIN_SHOTS, 10);
  for (const [f, g] of [[35, 36], [10, 10], [17, 19]]) assert.equal(usable(f, g), true, `${f},${g}`);
  for (const [f, g] of [[1, 4], [9, 10], [10, 9], [2, 7]]) assert.equal(usable(f, g), false, `${f},${g}`);
  for (const [f, g] of [[3, 30], [30, 3], [10, 11]]) assert.equal(usable(f, g), usable(g, f));
});

test('shotsOfFrames: the frame in effect at the wheel event starts at 0, each lasts until the next, the last until the end', () => {
  const frames = [{ ts: 900 }, { ts: 1000 }, { ts: 1040 }, { ts: 1100 }, { ts: 2600 }];
  assert.deepEqual(shotsOfFrames(frames, 1000, 1500), [
    { frame: 1, from: 0, to: 40 },
    { frame: 2, from: 40, to: 100 },
    { frame: 3, from: 100, to: 1500 },
  ]);
  assert.deepEqual(shotsOfFrames(frames, 1050, 1500), [
    { frame: 2, from: 0, to: 50 },
    { frame: 3, from: 50, to: 1500 },
  ]);
  assert.deepEqual(shotsOfFrames([{ ts: 1200 }, { ts: 1300 }], 1000, 1500), [{ frame: 0, from: 200, to: 300 }, { frame: 1, from: 300, to: 1500 }]);
  assert.deepEqual(shotsOfFrames([], 1000, 1500), []);
});

test('labelOf is the number, the repeat and the from-to range', () => {
  assert.equal(labelOf({ i: 3, rep: 1, from: 40, to: 100 }), '#3 r1 40-100 ms');
});

test('pooled: the shots of one push over all repeats, ordered by time and numbered; other pushes and their shots stay out', () => {
  const run = { pushes: [
    { push: 'open', rep: 0, shots: [{ file: 'a', ms: 10 }, { file: 'b', ms: 300 }], rows: [1] },
    { push: 'close', rep: 0, shots: [{ file: 'c', ms: 5 }], rows: [2] },
    { push: 'open', rep: 1, shots: [{ file: 'd', ms: 120 }, { file: 'e', ms: 300 }], rows: [3] },
  ] };
  const o = pooled(run, 'open');
  assert.deepEqual(o.shots.map((x) => [x.i, x.file, x.rep]), [[0, 'a', 0], [1, 'd', 1], [2, 'b', 0], [3, 'e', 1]]);
  assert.deepEqual(o.rows, [1, 3]);
  assert.equal(usable(pooled(run, 'close').shots.length, o.shots.length), false);
});

test('columnsOf: a screencast shows the frame in effect, a screenshot the nearest in time; repeats are dropped', () => {
  const a = { shots: [{ i: 0, ms: 0, from: 0, to: 60 }, { i: 1, ms: 60, from: 60, to: 600 }, { i: 2, ms: 600, from: 600, to: 1000 }] };
  const b = { shots: [{ i: 0, ms: 10, from: 10, to: 20 }, { i: 1, ms: 500, from: 480, to: 520 }] };
  const cast = columnsOf(a, b, 5, 'screencast').map((c) => [c.a.i, c.b.i]);
  assert.deepEqual(cast, [[0, 0], [1, 0], [2, 1]]);
  const shot = columnsOf(a, b, 5, 'screenshot').map((c) => [c.a.i, c.b.i]);
  assert.deepEqual(shot, [[0, 0], [1, 0], [1, 1], [2, 1]]);
});

test('cropOf: the union of the actions group over both arms, padded 24 px, clamped to the band', () => {
  const run = (actions) => ({ clip: { width: 390 }, pushes: [{ push: 'open', rep: 0, shots: [], rows: [{ actions, earn: null }] }] });
  assert.deepEqual(cropOf(run([100, 0, 200, 40]), run([120, 0, 250, 40])), { x: 76, width: 314 });
  assert.deepEqual(cropOf(run(null), run(null)), { x: 0, width: 390 });
});
