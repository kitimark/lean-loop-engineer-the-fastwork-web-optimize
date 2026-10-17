// Unit tests of the pure extraction module (no Docker). Zone sums moved to Lean (fwcore measure.zoneSums): see
// test/fwcore.test.mjs and packages/contracts/golden/measure/.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { traceToFrameCounts, N1_KEYS } from '../src/trace.mjs';

const N1_ZERO = Object.fromEntries(N1_KEYS.map((k) => [k, 0]));
const sorted = (o) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => (a < b ? -1 : 1)));

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
  assert.deepEqual(r.perFrame[0], sorted({ ...N1_ZERO, 'trace.Layout': 1, 'trace.Layout.dirtyObjects': 3, 'trace.Layout.partial': 0, 'trace.Layout.totalObjects': 10, 'trace.UpdateLayoutTree': 1, 'trace.UpdateLayoutTree.elementCount': 7, 'trace.cc.Activate': 1 }));
  assert.deepEqual(r.perFrame[1], sorted({ ...N1_ZERO, 'trace.Layout': 1, 'trace.Layout.dirtyObjects': 1, 'trace.Layout.partial': 1, 'trace.Layout.totalObjects': 10 }));
});

test('traceToFrameCounts: HitTest inside the overlay-ad detector is its own type; N1 slices are counted and zero-filled', () => {
  const M = (pid, tid, name) => ({ ph: 'M', name: 'thread_name', pid, tid, args: { name } });
  const ev = [
    M(1, 1, 'CrRendererMain'),
    { ph: 'I', name: 'TimeStamp', pid: 1, tid: 1, ts: 100, args: { data: { message: 'F0' } } },
    { ph: 'X', name: 'HitTest', pid: 1, tid: 1, ts: 110, dur: 4, args: {} },
    { ph: 'X', name: 'OverlayInterstitialAdDetector::MaybeFireDetection', pid: 1, tid: 1, ts: 200, dur: 30, args: {} },
    { ph: 'X', name: 'HitTest', pid: 1, tid: 1, ts: 205, dur: 20, args: {} },
    { ph: 'X', name: 'StyleEngine::updateActiveStyleSheets', pid: 1, tid: 1, ts: 300, dur: 3, args: {} },
    { ph: 'I', name: 'TimeStamp', pid: 1, tid: 1, ts: 400, args: { data: { message: 'F1' } } },
    { ph: 'X', name: 'HitTest', pid: 1, tid: 1, ts: 410, dur: 4, args: {} },
  ];
  const r = traceToFrameCounts(ev, 2);
  assert.equal(r.perFrame[0]['trace.HitTest'], 1);
  assert.equal(r.perFrame[0]['trace.HitTest.overlayAdDetector'], 1);
  assert.equal(r.perFrame[0]['trace.N1.updateActiveStyleSheets'], 1);
  assert.equal(r.perFrame[0]['trace.N1.scheduleInvalidationsForRuleSets'], 0);
  assert.equal(r.perFrame[1]['trace.HitTest'], 1);
  assert.equal(r.perFrame[1]['trace.HitTest.overlayAdDetector'], undefined);
  assert.equal(r.perFrame[1]['trace.N1.updateActiveStyleSheets'], 0);
});

test('n0Windows: events go to the first frame at or after their time; load, preroll and after are separate', async () => {
  const { n0Windows, n0FrameCounts } = await import('../src/n0.mjs');
  const dt = 10;
  const frameVts = [20100, 20110, 20120]; // recorded frames; the last pre-roll frame is at 20090
  const E = (kind, vt) => ({ kind, vt });
  const evs = [E('cssom.sheet', 5), E('cssom.sheet', 20050), E('cssom.sheet', 20090), E('sheetNode.added', 20095), E('cssom.keyframes', 20110), E('sheetNode.text', 20111), E('cssom.sheet', 20999)];
  const { win, perFrame } = n0Windows(evs, frameVts, 20000, dt);
  assert.deepEqual([win.load.length, win.preroll.length, win.after.length], [1, 2, 1]);
  assert.deepEqual(perFrame.map((l) => l.length), [1, 1, 1]);
  assert.deepEqual(n0FrameCounts(perFrame[1]), { 'n0.events': 1, 'n0.cssom': 1, 'n0.sheetNode': 0 });
  assert.deepEqual(n0FrameCounts(perFrame[2]), { 'n0.events': 1, 'n0.cssom': 0, 'n0.sheetNode': 1 });
});
