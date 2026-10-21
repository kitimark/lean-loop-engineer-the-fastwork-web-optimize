// Reducers of the Linux WebKit probe (src/linux/reduce.mjs): percentiles, rAF gaps, Timeline record flattening and per-step counts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { countByType, flatten, framesIn, intervals, percentile, reduceRun, stampTime, stepCounts, summarize } from '../src/linux/reduce.mjs';

test('percentile is nearest-rank on an ascending array', () => {
  const s = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
  assert.equal(percentile(s, 50), 50);
  assert.equal(percentile(s, 90), 90);
  assert.equal(percentile(s, 99), 100);
  assert.equal(percentile(s, 0), 10);
  assert.equal(percentile([], 50), null);
});

test('summarize and intervals', () => {
  assert.deepEqual(intervals([0, 16, 33, 150]), [16, 17, 117]);
  assert.deepEqual(intervals([5]), []);
  const s = summarize([16, 17, 117]);
  assert.equal(s.n, 3);
  assert.equal(s.p50, 17);
  assert.equal(s.max, 117);
  assert.equal(s.mean, 50);
  assert.equal(summarize([]).p50, null);
});

// A Timeline tree in the protocol's shape: seconds, children nested.
const rec = (type, a, b, extra = {}) => ({ type, startTime: a, endTime: b, ...extra });
const stamp = (label, t) => rec('TimeStamp', t, t, { data: { message: label } });

test('flatten walks children depth first and converts nothing but the duration to ms', () => {
  const flat = flatten([rec('FireAnimationFrame', 1, 1.01, { children: [rec('FunctionCall', 1.002, 1.004)] }), rec('Layout', 1.02, 1.03)]);
  assert.deepEqual(flat.map((r) => [r.type, r.depth]), [['FireAnimationFrame', 0], ['FunctionCall', 1], ['Layout', 0]]);
  assert.ok(Math.abs(flat[1].ms - 2) < 1e-9);
  assert.equal(flat[0].start, 1);
});

test('countByType counts nested records and adds inclusive time', () => {
  const c = countByType(flatten([rec('Layout', 0, 0.002), rec('Layout', 1, 1.004), rec('Paint', 2, 2.001)]));
  assert.deepEqual(c, { Layout: { n: 2, ms: 6 }, Paint: { n: 1, ms: 1 } });
});

test('stampTime finds the stamp by label in the record data, null when absent', () => {
  const flat = flatten([stamp('fw-s0', 1), rec('TimeStamp', 2, 2, { data: { label: 'fw-e0' } })]);
  assert.equal(stampTime(flat, 'fw-s0'), 1);
  assert.equal(stampTime(flat, 'fw-e0'), 2);
  assert.equal(stampTime(flat, 'fw-s1'), null);
});

test('stepCounts: records between a step\'s two stamps belong to it; stamps are left out; a missing stamp marks the step undelimited', () => {
  const flat = flatten([
    stamp('fw-s0', 1), rec('Layout', 1.1, 1.2), rec('RecalculateStyles', 1.3, 1.4), stamp('fw-e0', 1.5),
    rec('Layout', 1.6, 1.7), // between steps: counted in no step
    stamp('fw-s1', 2), rec('Paint', 2.1, 2.2), // no end stamp
  ]);
  const steps = stepCounts(flat, 2);
  assert.equal(steps[0].delimited, true);
  assert.deepEqual(Object.keys(steps[0].counts).sort(), ['Layout', 'RecalculateStyles']);
  assert.equal(steps[0].window_ms, 500);
  assert.equal(steps[1].delimited, false);
  assert.deepEqual(steps[1].counts, {});
});

test('framesIn takes the callbacks inside the window and their gaps', () => {
  const f = framesIn([0, 10, 20, 170, 190], 10, 170);
  assert.equal(f.frames, 3);
  assert.deepEqual(f.gaps, [10, 150]);
});

test('reduceRun joins rAF windows, wheel timings and Timeline steps', () => {
  const raw = {
    idleRaf: [0, 17, 34, 51],
    scrollRaf: [100, 250, 400, 417],
    steps: [{ i: 0, t0: 100, t1: 260, wheelMs: 140, scrollY: 400 }, { i: 1, t0: 300, t1: 420, wheelMs: 150, scrollY: 800 }],
    records: [stamp('fw-s0', 1), rec('Layout', 1.01, 1.02), stamp('fw-e0', 1.2), stamp('fw-s1', 2), stamp('fw-e1', 2.1)],
    fps: ['console: FPS: 7'], renderer: 'llvmpipe', timelineError: null,
  };
  const r = reduceRun(raw);
  assert.equal(r.idle.p50, 17);
  assert.equal(r.scroll.max, 150);
  assert.equal(r.wheel.p50, 140);
  assert.equal(r.timeline.stepsDelimited, 2);
  assert.equal(r.timeline.perStep[0].counts.Layout.n, 1);
  assert.equal(r.timeline.perStep[0].frames, 2);
  assert.equal(r.timeline.perStep[0].max_gap_ms, 150);
  assert.equal(r.timeline.perStep[1].moved, 800);
  assert.deepEqual(r.fps, ['console: FPS: 7']);
});

test('reduceRun of a run with no Timeline rows still reduces the rAF numbers', () => {
  const r = reduceRun({ idleRaf: [0, 20], scrollRaf: [], steps: [], records: [], timelineError: 'no session' });
  assert.equal(r.idle.p50, 20);
  assert.equal(r.timeline.records, 0);
  assert.equal(r.timelineError, 'no session');
});
