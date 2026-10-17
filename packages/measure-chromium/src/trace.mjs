// Trace events -> raw per-frame counts. Pure functions of the trace event list (no clock, no I/O, no decisions).
//
// Frame attribution, by thread class (renderer process only):
//  - main (CrRendererMain): the driver evaluates console.timeStamp('F<n>') on this thread right before frame n's
//    BeginFrame, so every event with ts >= mark n and < mark n+1 belongs to frame n.
//  - compositor (Compositor): `Scheduler::BeginImplFrame` fires exactly once per BeginFrame the driver sends; frame n is
//    the window from the n-th such event to the next.
//  - worker (ThreadPoolForegroundWorker): raster and decode tasks have no frame marker. They are attributed by ts to the
//    compositor window they started in. That is only as deterministic as the task scheduling: the run-to-run comparison
//    decides whether the per-frame value is trusted (see README, determinism classes).
export const TRACE_CATEGORIES = [
  'devtools.timeline', 'disabled-by-default-devtools.timeline', 'blink.animations', 'cc', 'benchmark',
  'disabled-by-default-devtools.timeline.frame', 'blink,devtools.timeline', 'blink,benchmark',
  'blink_style', 'blink', // N1: StyleEngine::updateActiveStyleSheets and scheduleInvalidationsForRuleSets are "blink,blink_style", InvalidateStyleAndLayoutForFontUpdates is "blink" only (style_engine.cc@f842f52 :681, :2515, :1351)
  'disabled-by-default-devtools.timeline.layers', // LayerTreeHostImpl:snapshot per frame: layer census and per-layer raster invalidation regions
].filter((c) => !(process.env.FW_NO_LAYERS && c.endsWith('timeline.layers')));

// spec: { key, ph?: [phases counted], b?: {argName: key} summed from the begin/complete event args (also beginData),
//         e?: {argName: key} summed from the end event args (or the complete event's own args) }
const MAIN = {
  UpdateLayoutTree: { key: 'trace.UpdateLayoutTree', e: { elementCount: 'trace.UpdateLayoutTree.elementCount' } },
  Layout: { key: 'trace.Layout', b: { dirtyObjects: 'trace.Layout.dirtyObjects', totalObjects: 'trace.Layout.totalObjects', partialLayout: 'trace.Layout.partial' } },
  InvalidateLayout: { key: 'trace.InvalidateLayout' },
  ScheduleStyleRecalculation: { key: 'trace.ScheduleStyleRecalculation' },
  PrePaint: { key: 'trace.PrePaint' },
  Paint: { key: 'trace.Paint' },
  PaintImage: { key: 'trace.PaintImage' },
  Layerize: { key: 'trace.Layerize' },
  Commit: { key: 'trace.Commit' },
  UpdateLayer: { key: 'trace.UpdateLayer' },
  'Layer:created': { key: 'trace.Layer.created', ph: ['I'] },
  'Layer:deleted': { key: 'trace.Layer.deleted', ph: ['I'] },
  ScrollLayer: { key: 'trace.ScrollLayer' },
  'LocalFrameView::NotifyResizeObservers': { key: 'trace.ResizeObserverNotify' },
  'IntersectionObserverController::computeIntersections': { key: 'trace.IntersectionObserverCompute' },
  HitTest: { key: 'trace.HitTest' }, // HitTests inside OverlayInterstitialAdDetector::MaybeFireDetection are counted under SPLITS instead
  // N1 (PLAN 6.7): the engine-side style-sheet update slices. Zero on a page that never changes its sheets after load.
  'StyleEngine::updateActiveStyleSheets': { key: 'trace.N1.updateActiveStyleSheets' },
  'StyleEngine::scheduleInvalidationsForRuleSets': { key: 'trace.N1.scheduleInvalidationsForRuleSets' },
  'StyleEngine::InvalidateStyleAndLayoutForFontUpdates': { key: 'trace.N1.fontUpdateInvalidation' },
  CullRectUpdate: { key: 'trace.CullRectUpdate' },
  FireAnimationFrame: { key: 'trace.FireAnimationFrame' },
  RequestAnimationFrame: { key: 'trace.RequestAnimationFrame' },
  FunctionCall: { key: 'trace.FunctionCall' },
  EvaluateScript: { key: 'trace.EvaluateScript' },
  EventDispatch: { key: 'trace.EventDispatch' },
  TimerFire: { key: 'trace.TimerFire' },
  ResourceSendRequest: { key: 'trace.ResourceSendRequest' },
  ParseHTML: { key: 'trace.ParseHTML' },
  MinorGC: { key: 'trace.MinorGC' },
  MajorGC: { key: 'trace.MajorGC' },
  Animation: { key: 'trace.Animation.begin', ph: ['b'] },
  'Animation@n': { key: 'trace.Animation.instant', ph: ['n'], b: { compositeFailed: 'trace.Animation.compositeFailedBits' } },
};
// Chromium's overlay-interstitial-ad detector (core/ad_tracker/overlay_interstitial_ad_detector.cc@f842f52, called from
// LocalFrameView::RunIntersectionObserverSteps) hit-tests the viewport centre inside Commit at most once per second of
// WALL time (base::Time::Now() against kFireInterval, line 84-90). On the 100 ms barrier lane that is one run of
// the detector every 8-9 frames, and which of two adjacent frames gets it follows real time. It is browser-internal
// work, not page work, so it is counted under its own type and kept out of trace.HitTest.
const DETECTOR = 'OverlayInterstitialAdDetector::MaybeFireDetection';
// The same containment split for N1: a page that shows SVG images makes Blink build one isolated SVG document per image
// (IsolatedSVGDocumentHost, SVGImage), and each one runs its own first StyleEngine::updateActiveStyleSheets while
// its parse finishes (Document::FinishedParsing > UpdateLayoutTree > Document::updateActiveStyle). That is image decoding,
// not a change to the page's sheets, so a slice inside an SVG-image host is counted as trace.N1.svgImageDocument.
const SVG_HOST = 'IsolatedSVGDocumentHost::IsolatedSVGDocumentHost';
const SPLITS = {
  HitTest: { within: DETECTOR, spec: { key: 'trace.HitTest.overlayAdDetector' } },
  'StyleEngine::updateActiveStyleSheets': { within: SVG_HOST, spec: { key: 'trace.N1.svgImageDocument' } },
};
export const N1_KEYS = [...Object.values(MAIN).map((s) => s.key), 'trace.N1.svgImageDocument'].filter((k) => k.startsWith('trace.N1.'));
const COMP = {
  'LayerTreeHostImpl::ActivateSyncTree': { key: 'trace.cc.Activate', ph: ['X'] },
  'ProxyImpl::Commit': { key: 'trace.cc.Commit', ph: ['X'] },
  'TreeSynchronizer::SynchronizeTrees': { key: 'trace.cc.SynchronizeTrees', ph: ['X'] },
  'ProxyImpl::ScheduledActionDraw': { key: 'trace.cc.Draw', ph: ['X'] },
};
const WORKER = {
  RasterTask: { key: 'trace.RasterTask', ph: ['X'] },
  'DisplayItemList::Raster': { key: 'trace.DisplayItemListRaster', ph: ['X'] },
  ImageDecodeTask: { key: 'trace.ImageDecodeTask', ph: ['X'] },
  'Decode Image': { key: 'trace.DecodeImage', ph: ['X'] },
};

const bump = (o, k, v = 1) => { o[k] = (o[k] ?? 0) + v; };
const num = (v) => (typeof v === 'boolean' ? +v : typeof v === 'number' ? v : null);
function specOf(table, e) { return table[e.name === 'Animation' && e.ph === 'n' ? 'Animation@n' : e.name]; }

function addCounts(into, spec, e) {
  if (spec.ph ? !spec.ph.includes(e.ph) : !(e.ph === 'B' || e.ph === 'X' || e.ph === 'I' || e.ph === 'i' || e.ph === 'R')) return false;
  bump(into, spec.key);
  const a = { ...(e.args?.data ?? {}), ...(e.args?.beginData ?? {}), ...(e.args ?? {}) };
  for (const [k, key] of Object.entries(spec.b ?? {})) { const v = num(a[k]); if (v !== null) bump(into, key, v); }
  if (e.ph === 'X') for (const [k, key] of Object.entries(spec.e ?? {})) { const v = num(a[k]); if (v !== null) bump(into, key, v); }
  return true;
}

export function traceToFrameCounts(events, nFrames) {
  const threadName = new Map();
  for (const e of events) if (e.ph === 'M' && e.name === 'thread_name') threadName.set(`${e.pid}:${e.tid}`, e.args?.name);
  const mainKeys = new Set(), rendererPids = new Set();
  for (const [k, n] of threadName) if (n === 'CrRendererMain') { mainKeys.add(k); rendererPids.add(+k.split(':')[0]); }
  const perFrame = Array.from({ length: nFrames }, () => Object.fromEntries(N1_KEYS.map((k) => [k, 0]))); // N1 zeros are recorded, not omitted
  const runLevel = {};
  const stable = (a, b) => a.ts - b.ts;

  // ---- main thread: windows by console.timeStamp marks
  const main = events.filter((e) => mainKeys.has(`${e.pid}:${e.tid}`) && e.ph !== 'M').sort(stable);
  let cur = -1;
  const stacks = new Map();
  const outer = new Map(Object.values(SPLITS).map((x) => [x.within, main.filter((e) => e.name === x.within && e.ph === 'X').map((e) => [e.ts, e.ts + (e.dur ?? 0)])]));
  const inside = (e, within) => e.ph === 'X' && outer.get(within).some(([a, b]) => a <= e.ts && e.ts + (e.dur ?? 0) <= b);
  for (const e of main) {
    if (e.name === 'TimeStamp' && /^F\d+$/.test(e.args?.data?.message ?? '')) { cur = +e.args.data.message.slice(1); continue; }
    if (cur < 0 || cur >= nFrames) continue;
    const split = SPLITS[e.name];
    const spec = split && inside(e, split.within) ? split.spec : specOf(MAIN, e);
    const tid = `${e.pid}:${e.tid}`;
    if (!stacks.has(tid)) stacks.set(tid, []);
    if (e.ph === 'B') stacks.get(tid).push({ spec, frame: cur });
    if (e.ph === 'E') {
      const top = stacks.get(tid).pop();
      if (top?.spec?.e) for (const [k, key] of Object.entries(top.spec.e)) { const v = num(e.args?.[k] ?? e.args?.data?.[k]); if (v !== null) bump(perFrame[top.frame], key, v); }
      continue;
    }
    if (spec) addCounts(perFrame[cur], spec, e);
  }

  // ---- compositor windows
  const comp = events.filter((e) => rendererPids.has(e.pid) && threadName.get(`${e.pid}:${e.tid}`) === 'Compositor' && e.ph !== 'M').sort(stable);
  const bounds = comp.filter((e) => e.name === 'Scheduler::BeginImplFrame' && e.ph === 'X').map((e) => e.ts);
  const frameAt = (ts) => { let lo = 0, hi = bounds.length; while (lo < hi) { const m = (lo + hi) >> 1; if (bounds[m] <= ts) lo = m + 1; else hi = m; } return lo - 1; };
  runLevel['trace.cc.BeginImplFrame'] = bounds.length;
  for (const e of comp) { const spec = COMP[e.name]; if (!spec) continue; const f = frameAt(e.ts); if (f >= 0 && f < nFrames) addCounts(perFrame[f], spec, e); }

  // ---- layer census (one LayerTreeHostImpl:snapshot per BeginImplFrame)
  for (const e of comp) {
    if (e.name !== 'LayerTreeHostImpl:snapshot' || e.ph !== 'I' || !e.args?.snapshot) continue;
    const f = frameAt(e.ts);
    if (f < 0 || f >= nFrames) continue;
    for (const [k, v] of Object.entries(snapshotCounts(e.args.snapshot))) bump(perFrame[f], k, v);
  }

  // ---- workers: attributed to the compositor window of their start
  for (const e of events) {
    if (!rendererPids.has(e.pid) || e.ph === 'M') continue;
    if (threadName.get(`${e.pid}:${e.tid}`) !== 'ThreadPoolForegroundWorker') continue;
    const spec = WORKER[e.name]; if (!spec) continue;
    const f = frameAt(e.ts);
    if (addCounts({}, spec, e)) { bump(runLevel, spec.key); if (f >= 0 && f < nFrames) addCounts(perFrame[f], spec, e); }
  }

  const threads = {};
  for (const n of threadName.values()) bump(threads, n);
  const sortObj = (o) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => (a < b ? -1 : 1)));
  return { perFrame: perFrame.map(sortObj), runLevel: sortObj(runLevel), threads: sortObj(threads) };
}

// Layer census and raster invalidation of one LayerTreeHostImpl:snapshot (args.snapshot). Pure. All values are counts or
// pixel areas in layer space; nothing about tile resources or memory (those depend on raster timing).
// invalidation is cc::Region::AsValueInto: four integers x, y, width, height per rect (cc/base/region.cc@156.0.8078.4).
export function snapshotCounts(snap) {
  const out = { 'census.snapshots': 1, 'census.layers': 0, 'census.drawingLayers': 0, 'census.drawingAreaPx': 0, 'census.tilings': 0, 'census.tiles': snap?.tile_manager_basic_state?.tile_count ?? 0, 'census.activeTiles': 0, 'census.solidTiles': 0, 'census.activeTileAreaPx': 0, 'raster.invalidatedLayers': 0, 'raster.invalidationRects': 0, 'raster.invalidationAreaPx': 0 };
  for (const l of snap?.active_tree?.layers ?? []) {
    out['census.layers']++;
    if (l.draws_content) { out['census.drawingLayers']++; out['census.drawingAreaPx'] += (l.bounds?.width ?? 0) * (l.bounds?.height ?? 0); }
    out['census.tilings'] += (l.tilings ?? []).length;
    const inv = l.invalidation ?? [];
    if (inv.length) {
      out['raster.invalidatedLayers']++;
      for (let i = 0; i + 3 < inv.length; i += 4) { out['raster.invalidationRects']++; out['raster.invalidationAreaPx'] += inv[i + 2] * inv[i + 3]; }
    }
  }
  for (const t of snap?.active_tiles ?? []) {
    out['census.activeTiles']++;
    if (t.draw_info?.is_solid_color) out['census.solidTiles']++;
    const r = t.content_rect ?? [0, 0, 0, 0];
    out['census.activeTileAreaPx'] += r[2] * r[3];
  }
  return out;
}

// Exploration helper: histogram of event names by thread name.
export function histogram(events) {
  const tn = new Map();
  for (const e of events) if (e.ph === 'M' && e.name === 'thread_name') tn.set(`${e.pid}:${e.tid}`, e.args.name);
  const h = {};
  for (const e of events) {
    if (e.ph === 'M') continue;
    const k = `${tn.get(`${e.pid}:${e.tid}`) ?? '?'} | ${e.cat} | ${e.name} | ${e.ph}`;
    h[k] = (h[k] ?? 0) + 1;
  }
  return Object.entries(h).sort(([a], [b]) => (a < b ? -1 : 1));
}
