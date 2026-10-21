// The cost table and the frame bucketing, on synthetic sessions (the counted predicates are in lag-cost.test.mjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import { passMetrics, collectArm, costMd } from '../src/lag/costreport.mjs';
import { frameCosts } from '../src/lag/costprobe.mjs';

const frames = (zone, ts) => ts.map((t) => [t, zone]);
const session = (skip) => ({
  passes: [{
    cost: {
      scroll: {
        frames: [...frames('scroll-A', [0, 16667, 33333, skip ? 66667 : 50000]), ...frames('scroll-B', [66667 + 16667, 100000, 116667])],
        costs: [['scroll-A', 10, 5], ['scroll-A', 10, 20], ['scroll-A', 0, 0], ['scroll-A', 4, 4], ['scroll-B', 1, 9], ['scroll-B', 1, 1], ['scroll-B', 2, 1]],
      },
      morph: { frames: frames('open', [0, 16667]), costs: [['open', 1, 2], ['open', 1, 2]], ends: { open: 680000, close: 3000000 }, paints: [700000, 900000, 1300000] },
      layersScroll: { snaps: [['scroll-A', [['1', 10, 10]]], ['scroll-A', [['1', 10, 10], ['2', 5, 5]]], ['scroll-B', [['2', 5, 6]]]] },
      layersMorph: null,
    },
  }],
});

test('per-pass metrics of a zone are fractions of the Lean counts', () => {
  const m = passMetrics(session(true).passes[0]);
  assert.deepEqual(m['scroll-A'].frames, [4, 1]);
  assert.deepEqual(m['scroll-A'].skipped100, [25, 1]);
  assert.deepEqual(m['scroll-A'].paintPF, [6, 1]);
  assert.deepEqual(m['scroll-A'].bound100, [25, 1]);
  assert.deepEqual(m['scroll-A'].fresh100, [100, 1]);
  assert.deepEqual(m.open.early, [2, 1]);
  assert.deepEqual(m.open.late, [1, 1]);
  assert.equal(m['scroll-calm'], undefined);
});

test('a difference is stated only when the per-pass ranges are separated', () => {
  const a = collectArm([session(false), session(false)]), b = collectArm([session(true), session(true)]);
  assert.equal(a.withCost, 2);
  const md = costMd([['original', a], ['rewrite', b]]);
  assert.match(md, /hero exit \(scroll A\) \| rewrite .*\| higher \|/);
  const same = costMd([['original', a], ['rewrite', collectArm([session(false)])]]);
  assert.match(same, /hero exit \(scroll A\) \| rewrite .*\| overlap \|/);
});

test('frame costs: rows bucketed by frame marks, durations in microseconds', () => {
  const rows = [['TimeStamp', 1, null, 'wk:f0'], ['Paint', 1.001, 1.002, null], ['Composite', 1.003, 1.0045, null], ['TimeStamp', 2, null, 'wk:f1'],
    ['Composite', 2.001, 2.002, null], ['Composite', 2.004, null, null]];
  assert.deepEqual(frameCosts(rows, [1, 2], 3), [[1000, 1500], [0, 1000]]);
});
