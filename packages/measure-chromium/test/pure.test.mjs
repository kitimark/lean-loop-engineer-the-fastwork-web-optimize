// Unit tests of the pure extraction module (no Docker). Zone sums moved to Lean (fwcore measure.zoneSums): see
// test/fwcore.test.mjs and packages/contracts/golden/measure/.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { traceToFrameCounts } from '../src/trace.mjs';

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
