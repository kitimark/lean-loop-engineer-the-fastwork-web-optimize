// The finish table: which passes count, the sums per arm and the verdict lines (the counts themselves are finish.mjs, golden-checked).
import test from 'node:test';
import assert from 'node:assert/strict';
import { armRow, excludeReason, framesOf, reportMd, toolbarMoved, verdictsOf } from '../src/throttle/finish-report.mjs';

const MX = 52000;

/** A finish record: the page advances every `period` frames from 5 px under the zone start to the end, then the morph opens `wait` frames later and bounces `bounces` times. */
function finishRecord({ period, moves, wait = 3, bounces = 2, toolbar = true }) {
  const y = [], mx = [], o = [], vh = [], t = [];
  const push = (yy, op) => { y.push(yy); mx.push(MX); o.push(op); vh.push(7750 + (toolbar ? 400 : 0)); t.push(y.length * 16.7); };
  for (let m = 0; m < moves; m++) for (let k = 0; k < period; k++) push(MX - 5000 + m * 10, 0);
  for (let k = 0; k < wait; k++) push(MX, 0);
  for (let b = 0; b < bounces; b++) { push(MX + 100, 1); push(MX, 1); }
  push(MX + 100, 1);
  const half = Math.floor(vh.length / 2);
  for (let i = 0; i < half; i++) vh[i] = 7750;
  return { start: { ih: 7750, vh: 7750, y: MX - 5000, scale: 1 }, nav: true, frames: y.length, t, y, mx, o, ih: y.map(() => 7750), vh, total: y.length };
}

const pass = (arm, rec, drag = { code: 0 }) => ({ arm, round: 1, vm: '1', rec, drag });

test('a pass counts only with touches that worked, the morph nav and real travel', () => {
  const ok = finishRecord({ period: 6, moves: 40 });
  assert.equal(excludeReason(pass('rewrite', ok)), null);
  assert.equal(excludeReason(pass('rewrite', ok, { code: 65 })), 'touch driver failed');
  assert.equal(excludeReason(pass('rewrite', ok, { code: null, timedOut: true })), 'touch driver timed out');
  assert.equal(excludeReason(pass('rewrite', { ...ok, nav: false })), 'morph nav not found');
  assert.match(excludeReason(pass('rewrite', finishRecord({ period: 1, moves: 5 }))), /fewer than/);
  const flat = { ...ok, y: ok.y.map(() => 100) };
  assert.match(excludeReason(pass('rewrite', flat)), /moved less than/);
  assert.match(excludeReason(pass('rewrite', { ...ok, start: { ...ok.start, scale: 1.5 } })), /zoomed/);
});

test('an arm that moves every sixth frame has one band run per move, and the morph opens late and bounces', () => {
  const rec = finishRecord({ period: 6, moves: 40, wait: 3, bounces: 2 });
  const r = armRow([pass('rewrite', rec)]);
  assert.equal(r.usable, 1);
  assert.equal(r.band, 40);
  assert.equal(r.reversals, 3);
  assert.deepEqual(r.late, [3]);
  assert.equal(r.reachedPasses, 1);
  assert.equal(r.moved, 1);
  assert.equal(toolbarMoved(rec), true);
  assert.equal(framesOf(rec).length, rec.frames);
});

test('lifted when the flag arm has no band runs, not-lifted when it keeps them, no-signature without a baseline, no-data without passes', () => {
  const base = pass('rewrite', finishRecord({ period: 6, moves: 40 }));
  const lifted = pass('lift', finishRecord({ period: 1, moves: 240 }));
  assert.equal(verdictsOf([base, lifted]).rewrite, 'lifted');
  assert.equal(verdictsOf([base, pass('lift', finishRecord({ period: 6, moves: 40 }))]).rewrite, 'not-lifted');
  assert.equal(verdictsOf([pass('rewrite', finishRecord({ period: 1, moves: 240 })), lifted]).rewrite, 'no-signature');
  assert.equal(verdictsOf([base, lifted]).original, 'no-data');
  assert.equal(verdictsOf([]).rewrite, 'no-data');
});

test('the table has a row per job and arm, the pooled rows and the verdict lines', () => {
  const passes = [pass('rewrite', finishRecord({ period: 6, moves: 40 })), pass('lift', finishRecord({ period: 1, moves: 240 })),
    pass('original', finishRecord({ period: 6, moves: 40 }), { code: 65 })];
  const md = reportMd([{ vm: 'job 1', passes }, { vm: 'job 2', passes }]);
  assert.match(md, /\| job 1 \| rewrite \| 1 \(1\) \| \d+ \| 40 \|/);
  assert.match(md, /\| all jobs \| original \| 2 \(0\) \|/);
  assert.match(md, /- job 2: lift against rewrite lifted; lift against original no-data/);
  assert.match(md, /Excluded passes: touch driver failed\./);
});
