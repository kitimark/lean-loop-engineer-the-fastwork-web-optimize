// Unit tests for the two pure modules (no Docker). Golden vectors here are the seed for the Lean spec of reduce.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { zoneSums } from '../src/reduce.mjs';
import { traceToFrameCounts } from '../src/trace.mjs';

test('zoneSums: swipe frames group by 500 px zone, other phases by name, sums and scrolledPx add up', () => {
  const frames = [
    { n: 0, phase: 'rest', scrollY: 0, counts: { a: 1, b: 2 } },
    { n: 1, phase: 'swipe', scrollY: 10, counts: { a: 1, b: 0 } },
    { n: 2, phase: 'swipe', scrollY: 490, counts: { a: 2, b: 1 } },
    { n: 3, phase: 'swipe', scrollY: 500, counts: { a: 4, b: 1 } },
    { n: 4, phase: 'tail', scrollY: 500, counts: { a: 0, b: 7 } },
  ];
  const z = zoneSums(frames, 500);
  assert.deepEqual(z.map((x) => x.id), ['rest', 'y00000', 'y00500', 'tail']);
  assert.deepEqual(z.map((x) => x.frames), [1, 2, 1, 1]);
  assert.deepEqual(z.map((x) => x.scrolledPx), [0, 490, 10, 0]);
  assert.deepEqual(z[1].sums, { a: 3, b: 1 });
  // totals are conserved
  assert.equal(z.reduce((s, x) => s + x.sums.a, 0), 8);
});

test('traceToFrameCounts: main-thread events are bucketed by the F<n> marks, compositor events by BeginImplFrame', () => {
  const M = (pid, tid, name) => ({ ph: 'M', name: 'thread_name', pid, tid, args: { name } });
  const ev = [
    M(1, 1, 'CrRendererMain'), M(1, 2, 'Compositor'),
    { ph: 'I', name: 'TimeStamp', pid: 1, tid: 1, ts: 100, args: { data: { message: 'F0' } } },
    { ph: 'X', name: 'Layout', pid: 1, tid: 1, ts: 110, dur: 5, args: { beginData: { dirtyObjects: 3, totalObjects: 10, partialLayout: false } } },
    { ph: 'B', name: 'UpdateLayoutTree', pid: 1, tid: 1, ts: 120, args: {} },
    { ph: 'E', name: 'UpdateLayoutTree', pid: 1, tid: 1, ts: 125, args: { elementCount: 7 } },
    { ph: 'I', name: 'TimeStamp', pid: 1, tid: 1, ts: 200, args: { data: { message: 'F1' } } },
    { ph: 'X', name: 'Layout', pid: 1, tid: 1, ts: 210, dur: 5, args: { beginData: { dirtyObjects: 1, totalObjects: 10, partialLayout: true } } },
    { ph: 'X', name: 'Scheduler::BeginImplFrame', pid: 1, tid: 2, ts: 105, dur: 1 },
    { ph: 'X', name: 'LayerTreeHostImpl::ActivateSyncTree', pid: 1, tid: 2, ts: 150, dur: 1 },
    { ph: 'X', name: 'Scheduler::BeginImplFrame', pid: 1, tid: 2, ts: 205, dur: 1 },
  ];
  const r = traceToFrameCounts(ev, 2);
  assert.deepEqual(r.perFrame[0], { 'trace.Layout': 1, 'trace.Layout.dirtyObjects': 3, 'trace.Layout.partial': 0, 'trace.Layout.totalObjects': 10, 'trace.UpdateLayoutTree': 1, 'trace.UpdateLayoutTree.elementCount': 7, 'trace.cc.Activate': 1 });
  assert.deepEqual(r.perFrame[1], { 'trace.Layout': 1, 'trace.Layout.dirtyObjects': 1, 'trace.Layout.partial': 1, 'trace.Layout.totalObjects': 10 });
});
