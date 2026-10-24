// The probe's table: which passes count, and that the verdict is the twin's on the summed arms.
import test from 'node:test';
import assert from 'node:assert/strict';
import { armRow, excludeReason, reportMd, verdictOf } from '../src/throttle/report.mjs';

/** A recorder record of a scroll that advances once every `period` frames through the hero exit (value 400 per mille); the toolbar collapses (+40 px) from the middle on. */
function recorderRecord({ period, moves, height = 7750 }) {
  const y = [], v = [], t = [], ih = [], vh = [];
  for (let m = 0; m < moves; m++) {
    for (let k = 0; k < period; k++) {
      y.push(1000 + m * 10); v.push(400); t.push(y.length * 16.7); ih.push(height); vh.push(height + (m * 2 >= moves ? 400 : 0));
    }
  }
  return { start: { ih: height, vh: height, y: 0, scale: 1 }, hero: true, frames: y.length, t, y, v, ih, vh, maxY: y.length ? Math.max(...y) / 10 : 0, total: y.length };
}

const pass = (arm, rec, drag = { code: 0 }) => ({ arm, round: 1, vm: '1', rec, drag });

test('a pass counts only with touches that worked, a hero value and real travel', () => {
  const ok = recorderRecord({ period: 6, moves: 40 });
  assert.equal(excludeReason(pass('rewrite', ok)), null);
  assert.equal(excludeReason(pass('rewrite', ok, { code: 65 })), 'touch driver failed');
  assert.equal(excludeReason(pass('rewrite', ok, { code: null, timedOut: true })), 'touch driver timed out');
  assert.equal(excludeReason(pass('rewrite', { ...ok, hero: false })), 'hero value not found');
  assert.match(excludeReason(pass('rewrite', { ...ok, maxY: 40 })), /moved less than/);
  assert.match(excludeReason(pass('rewrite', recorderRecord({ period: 6, moves: 3 }))), /fewer than/);
});

test('an arm that moves every sixth frame has one still run of 5 frames per move', () => {
  const r = armRow([pass('rewrite', recorderRecord({ period: 6, moves: 40 }))]);
  assert.equal(r.usable, 1);
  assert.equal(r.band, 39);
  assert.equal(r.moved, 1);
});

test('lifted when the flag arm has no band runs, not-lifted when it keeps them, confounded at another height', () => {
  const base = pass('rewrite', recorderRecord({ period: 6, moves: 40 }));
  const lifted = pass('lift', recorderRecord({ period: 1, moves: 240 }));
  assert.equal(verdictOf([base, lifted]).verdict, 'lifted');
  assert.equal(verdictOf([base, pass('lift', recorderRecord({ period: 6, moves: 40 }))]).verdict, 'not-lifted');
  assert.equal(verdictOf([base, pass('lift', recorderRecord({ period: 1, moves: 240, height: 8150 }))]).verdict, 'confounded');
  assert.equal(verdictOf([pass('rewrite', recorderRecord({ period: 6, moves: 1 }))]).verdict, 'no-data');
});

test('the table has a row per job and arm, the pooled rows and the verdict lines', () => {
  const passes = [pass('rewrite', recorderRecord({ period: 6, moves: 40 })), pass('lift', recorderRecord({ period: 1, moves: 240 }))];
  const md = reportMd([{ vm: 'job 1', passes }, { vm: 'job 2', passes }]);
  assert.match(md, /\| job 1 \| rewrite \|/);
  assert.match(md, /\| all jobs \| original \|/);
  assert.match(md, /- job 2: lifted/);
  assert.match(md, /- all jobs: lifted/);
});

test('the shipped arm gets its own rows and verdict lines, beside the diagnostic arm', () => {
  const passes = [pass('rewrite', recorderRecord({ period: 6, moves: 40 })), pass('unthrottle', recorderRecord({ period: 1, moves: 240 })),
    pass('unthrottle', recorderRecord({ period: 6, moves: 40 }))];
  assert.equal(verdictOf(passes, 'unthrottle').verdict, 'not-lifted');
  assert.equal(verdictOf(passes.slice(0, 2), 'unthrottle').verdict, 'lifted');
  const md = reportMd([{ vm: 'job 1', passes: passes.slice(0, 2) }]);
  assert.match(md, /\| all jobs \| unthrottle \|/);
  assert.match(md, /- all jobs \(unthrottle\): lifted/);
});
