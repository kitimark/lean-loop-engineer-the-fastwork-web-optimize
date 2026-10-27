import test from 'node:test';
import assert from 'node:assert/strict';
import { flipTables } from '../src/device-flip-report.mjs';

const zero = { script: 0, style: 0, layout: 0, paint: 0, commit: 0, idle: 0 };
const blank = (frames) => ({ frames, clips: 10, owners: { 'a-module_x': 6, 'no animated box': 4 }, n: { RecalculateStyles: 2 * frames, Layout: frames, Paint: 4 * frames, Composite: frames, ScheduleStyleRecalculation: 0, InvalidateLayout: 0 }, cs: { RecalculateStyles: 500 * frames, Composite: 300 * frames }, ev: { touch: 3 * frames, transition: frames, animation: 0 } });
const attr = {
  visits: [{ arm: 'base', index: 0, framesTl: { p95: 6000, max: 9000, over: 4 }, framesLane: { n: 200, over: 10, max: 18400 }, worst: [{ d: 9000, work: 'commit', lead: { where: 'Composite' } }] }],
  perArm: [
    { id: 'base', n: 6, intervals: 100, over: 4, overByWork: { ...zero, commit: 3, style: 1 }, tailByWork: { ...zero, commit: 2 }, leads: [{ k: 'commit: Composite', n: 3 }], busyShareOver: 90, anim: null, byTime: { 0: { long: 3, all: 40 }, 1: { long: 1, all: 30 }, 5: { long: 0, all: 30 } }, mix: { long: blank(4), rest: blank(96) } },
    { id: 'morph.geom:on', n: 6, intervals: 90, over: 0, overByWork: zero, tailByWork: zero, leads: [], busyShareOver: null, byTime: {}, mix: { long: blank(0), rest: blank(90) }, anim: { n: 2, error: null, groups: [{ k: 'css col on .x [transform] running', n: 2 }] } },
  ],
};

test('the attribution tables list the share per work and handle empty arms', () => {
  const t = flipTables(attr, {});
  assert.match(t, /\| base \| 6 \| 100 \| 4 \| 0 \(0%\) \| 1 \(25%\) \| 0 \(0%\) \| 0 \(0%\) \| 3 \(75%\) \| 0 \(0%\) \| 90% \|/);
  assert.match(t, /\| morph\.geom:on \| 6 \| 90 \| 0 \| 0 \(-\)/);
  assert.match(t, /- base: commit: Composite x3/);
  assert.match(t, /\| base \| 3 \/ 40 \| 1 \/ 30 \| 0 \/ 0 \| 0 \/ 30 \|/);
  assert.match(t, /\| base \| over 50 ms \| 4 \| 2\.0 \| 5\.0 \| 1\.0 \| 4\.0 \| 3\.0 \| 3\.0 \| 1\.0 \| 0\.0 \|/);
  assert.match(t, /- base: 90\.0 commit \(Composite, visit 0\)/);
  assert.match(t, /\| base \| 1 \| 200 \| 10 \| 5\.0 \| 184\.0 \|/);
  assert.match(t, /- base, over 50 ms \(10 clips\): 60% a-module_x; 40% no animated box/);
  assert.match(t, /- morph\.geom:on: 2 animations; css col on \.x \[transform\] running x2/);
});
