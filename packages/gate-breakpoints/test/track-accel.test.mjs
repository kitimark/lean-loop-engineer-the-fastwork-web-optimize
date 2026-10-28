import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeReasons, judge, loadGolden, reduceTrace, windowsOf } from '../src/track-accel.mjs';

const golden = loadGolden();
const g1440 = golden.find((l) => l.in.w === 1440 && l.in.eng === 'chromium');

test('the Lean golden lists one main-thread constant track and the blur tracks for Chromium geom-timed', () => {
  assert.ok(g1440);
  const why = g1440.out.timedMainWhy;
  assert.equal(why.filter((w) => w === 'no-visible-change').length, 1);
  assert.equal(why.filter((w) => w === 'filter-moves-pixels').length, g1440.out.blur);
});

test('failure bits decode to the named reasons', () => {
  assert.deepEqual(decodeReasons((1 << 12) | (1 << 17)), ['filter-moves-pixels', 'no-visible-change']);
});

test('judge: a timed cell passes when exactly the Lean main-thread tracks fail, and images beyond the sample are judged apart', () => {
  const keys = g1440.out.timedMain;
  const tags = g1440.out.keys.map((k, n) => ({ mg: k.split(':')[0], prop: k.split(':').slice(-1)[0], idx: n }));
  const extraImg = { mg: 'image', prop: 'transform', idx: 99 };
  const decided = [...tags, extraImg].map((t, n) => ({
    id: `fwx${n}`, mg: t.mg, prop: t.prop, idx: t.idx, began: true,
    fails: keys.includes(`${t.mg}:0:0:${t.prop}`) ? ['x'] : t === extraImg ? ['no-visible-change'] : [],
  }));
  const all = { arm: 'all', table: [...tags, extraImg], decided, ccStarts: {} };
  const v = judge('timed', 1440, [all], golden);
  assert.equal(v.ok, true);
  assert.deepEqual(v.extra, ['image:transform x1']);
  assert.equal(v.byProp.find((r) => r.prop === 'transform').failedExtraTracks, 1);
});

test('windowsOf tallies the invalidation reasons between the marks of one arm stage', () => {
  const ev = [
    { name: 'fwx:all:flip:start', ph: 'R', ts: 0, pid: 1, tid: 1 },
    { name: 'UpdateLayoutTree', ph: 'X', ts: 10, dur: 1000, pid: 1, tid: 1, args: { elementCount: 7 } },
    { name: 'StyleRecalcInvalidationTracking', ph: 'I', ts: 9, pid: 1, tid: 1, args: { data: { reason: 'Animation', nodeName: 'DIV' } } },
    { name: 'StyleRecalcInvalidationTracking', ph: 'I', ts: 99999, pid: 1, tid: 1, args: { data: { reason: 'late', nodeName: 'P' } } },
    { name: 'fwx:all:flip:end', ph: 'R', ts: 50, pid: 1, tid: 1 },
  ];
  const red = reduceTrace(ev);
  const [w] = windowsOf(red.marks, red.work, red.inval);
  assert.equal(w.work.UpdateLayoutTree.el, 7);
  assert.deepEqual(w.why, { 'StyleRecalc:Animation': { n: 1, nodes: { DIV: 1 } } });
});
