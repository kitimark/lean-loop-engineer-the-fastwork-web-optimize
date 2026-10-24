// The moving-frame table of the unthrottle-follow comparison: denominators, ratios and the max step on a built record.
import test from 'node:test';
import assert from 'node:assert/strict';
import { movingRow, movingMd } from '../src/throttle/follow-report.mjs';

/** A scroll that advances 10 tenths-px once every `period` frames, hero value 400 per mille, toolbar collapsing (+40 px) from the middle on. */
function record({ period, moves, height = 7750 }) {
  const y = [], v = [], t = [], ih = [], vh = [];
  for (let m = 0; m < moves; m++) {
    for (let k = 0; k < period; k++) {
      y.push(1000 + m * 10); v.push(400); t.push(y.length * 16.7); ih.push(height); vh.push(height + (m * 2 >= moves ? 400 : 0));
    }
  }
  return { start: { ih: height, vh: height, y: 0, scale: 1 }, hero: true, frames: y.length, t, y, v, ih, vh, maxY: Math.max(...y) / 10, total: y.length };
}
const pass = (arm, rec) => ({ arm, round: 1, vm: '1', rec, drag: { code: 0 } });

test('a pass moving every sixth frame has one still run of 5 per move among the moving frames', () => {
  const r = movingRow([pass('rewrite', record({ period: 6, moves: 40 }))]);
  assert.equal(r.usable, 1);
  assert.ok(r.moving > 0 && r.moving <= 240);
  assert.equal(r.mid, r.moving);
  assert.equal(r.stills, r.band);
  assert.equal(r.band, r.short);
  assert.equal(r.maxStepPx, 1);
  assert.equal(r.bandPer1000Mid, Math.round((r.band * 10000) / r.mid) / 10);
});

test('a pass that moves every frame has no still run', () => {
  const r = movingRow([pass('unthrottle-follow', record({ period: 1, moves: 60 }))]);
  assert.equal(r.stills, 0);
  assert.equal(r.band, 0);
  assert.equal(r.stillsPer1000Moving, 0);
});

test('an unusable pass is not counted and the table has a row per arm', () => {
  const bad = { ...pass('rewrite', record({ period: 6, moves: 40 })), drag: { code: 65 } };
  assert.equal(movingRow([bad]).usable, 0);
  const md = movingMd([{ vm: 'job 1', passes: [bad, pass('unthrottle-follow', record({ period: 1, moves: 60 }))] }], ['rewrite', 'unthrottle-follow']);
  assert.match(md, /\| job 1 \| rewrite \| 1 \(0\) \|/);
  assert.match(md, /\| all jobs \| unthrottle-follow \| 1 \(1\) \|/);
});
