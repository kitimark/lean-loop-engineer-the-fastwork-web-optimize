// The page script (served as /__fw/harness.js and loaded by a <script src> that is the first child of <head>).
//
// It runs inside WebKitTestRunner's page, where WKTR has installed `window.testRunner` and `window.internals`
// (Tools/WebKitTestRunner/InjectedBundle/InjectedBundlePage.cpp:667@862f17d, injectInternalsObject, every frame).
// It scrolls the page with the page's own native requestAnimationFrame (nothing is replaced or seeked) and samples the
// internals counters at the START of every animation-frame callback, i.e. once per rendering update:
//
//   for step k:  frame A_k : sample S(k,0); scrollTo(ys[k])        (sample first, so the scroll is inside the window)
//                frame f   : sample S(k,f)  for f = 1 .. frames-1
//   last      :  frame A_K : sample S(K,0)                          (closes the last window)
//
// Counters used (all `Source/WebCore/testing/Internals.idl` @e1c510bc, the archive's commit, lines 1005-1024; the
// implementations are cited in README.md):
//   styleRecalcCount()           Document::styleRecalcCount, +1 per Document::resolveStyle that ran
//   lastStyleUpdateSize          size of the Style::Update of the LAST resolveStyle (elements + text nodes)
//   renderingUpdateCount()       +1 per Page::updateRendering (counted only after startTrackingRenderingUpdates())
//   layerFlushCount(), layoutUpdateCount(), compositingUpdateCount(), styleInvalidationTraversalCount
// Nothing here reads scrollY / innerHeight inside the loop: LocalDOMWindow::scrollY forces a layout update, which would
// add style recalcs of its own. The scroll positions are the REQUESTED ones; the real one is read once at the end.
//
// Output: console lines `FWWKTR <tag> <json>` (WKTR prints page console messages into the test output, prefixed with
// "CONSOLE MESSAGE:"); the driver parses them. The test ends with testRunner.notifyDone().
import { bootstrapSource } from '../../measure-webkit/src/page.mjs';
import { VT_SRC, TRACE_SRC } from './vtime.mjs';

/** Scroll schedule, as measure-webkit's: y = 0, step, 2*step ... below maxY, then maxY. */
export function schedule(maxY, step) {
  const ys = [];
  for (let y = 0; y < maxY; y += step) ys.push(y);
  ys.push(maxY);
  return ys;
}

const RUN_SRC = `(() => {
  const P = __PARAMS__;
  const out = (tag, obj) => console.log('FWWKTR ' + tag + ' ' + JSON.stringify(obj));
  if (!window.testRunner || !window.internals) { out('error', { message: 'no testRunner/internals in this page', testRunner: !!window.testRunner, internals: !!window.internals }); return; }
  testRunner.dumpAsText();
  testRunner.waitUntilDone();
  const I = window.internals;
  const nST = window.__fwN.st; // the engine's own setTimeout, captured before any shim
  const sleep = (ms) => new Promise((r) => nST(r, ms));
  const raf = (fn) => new Promise((res) => requestAnimationFrame(() => res(fn())));
  const schedule = (maxY, step) => { const ys = []; for (let y = 0; y < maxY; y += step) ys.push(y); ys.push(maxY); return ys; };
  const TRACK = ['startTrackingStyleRecalcs', 'startTrackingRenderingUpdates', 'startTrackingLayerFlushes', 'startTrackingLayoutUpdates', 'startTrackingCompositingUpdates'];
  const num = (f) => { try { const v = f(); return typeof v === 'number' ? v : null; } catch { return null; } };
  // trace gauges that do not force style or layout (Internals.cpp numberOfActiveAnimations / numberOfAnimationTimelineInvalidations):
  // active CSS/Web animations summed over the samples (animation-frames), and timeline invalidations
  const traceGauges = () => {
    const ev = window.__fwEv;
    if (!ev) return;
    ev.animActive = (ev.animActive || 0) + (num(() => I.numberOfActiveAnimations()) || 0);
    ev.animTimelineInv = num(() => I.numberOfAnimationTimelineInvalidations()) || 0;
  };
  const snap = () => (P.trace && traceGauges(), {
    rc: num(() => I.renderingUpdateCount()),
    sr: num(() => I.styleRecalcCount()),
    ls: num(() => I.lastStyleUpdateSize),
    si: num(() => I.styleInvalidationTraversalCount),
    lf: num(() => I.layerFlushCount()),
    lu: num(() => I.layoutUpdateCount()),
    cu: num(() => I.compositingUpdateCount()),
    ...(P.trace && window.__fwEv ? { ev: { ...window.__fwEv } } : {}),
  });
  // virtual time (variant vt): wait until the page clock has run the settle time, then to a whole virtual second, so every
  // pass starts its steps at the same virtual instant (real time only decides how long that took)
  const vtSettle = async () => {
    const vt = window.__fwVt;
    if (!vt) return;
    while (vt.now() < P.settleMs) await raf(() => 0);
    while (vt.frames() % 60 !== 0) await raf(() => 0);
  };
  const run = async () => {
    await sleep(P.settleMs);
    await vtSettle();
    // Diagnostic (variant still): stop CSS animations/transitions (they run on the engine's real clock, not the page clock)
    if (P.still && typeof I.suspendAnimations === 'function') I.suspendAnimations();
    // Warm-up (variant "warm"): scroll the whole page once, wait for the images it started loading, go back to the top.
    // The measured pass then meets no lazy-load arrival; trackers are not running yet, so none of this is counted.
    if (P.warm) {
      const h0 = document.documentElement.scrollHeight;
      for (const y of schedule(Math.max(0, h0 - innerHeight), 200)) { scrollTo({ top: y, behavior: 'instant' }); await raf(() => 0); await raf(() => 0); await sleep(40); }
      for (let i = 0; i < 80 && Array.from(document.images).some((im) => !im.complete); i++) await sleep(100);
      scrollTo({ top: 0, behavior: 'instant' });
      await sleep(1500);
      await vtSettle();
    }
    // Layout facts, read once before the run (these reads may force layout; the trackers are started after them).
    const docH = document.documentElement.scrollHeight;
    const maxY = Math.max(0, docH - innerHeight);
    // cases (engine premise fixtures): P.cases steps, each one call of the page's own window.__fwStep(k) at the end of the sample callback
    // (same window as the scroll: S(k) .. S(k+1)); there is no scroll position, ys is a list of zeros.
    const ys = P.cases ? new Array(P.cases).fill(0) : schedule(maxY, P.step);
    const missing = TRACK.filter((n) => typeof I[n] !== 'function');
    for (const n of TRACK) if (typeof I[n] === 'function') I[n]();
    // two idle frames so the trackers' first reads start from a rendering update that already ran
    await raf(() => 0); await raf(() => 0);
    const bounds = [], mids = [];
    for (let k = 0; k < ys.length; k++) {
      bounds.push(await raf(() => { const s = snap(); if (P.cases) window.__fwStep(k); else scrollTo({ top: ys[k], behavior: 'instant' }); return s; }));
      const m = [];
      for (let f = 1; f < P.frames; f++) m.push(await raf(() => snap()));
      mids.push(m);
    }
    bounds.push(await raf(() => snap()));
    const endY = Math.round(scrollY);
    out('meta', {
      ua: navigator.userAgent, innerWidth, innerHeight, dpr: devicePixelRatio, docH, maxY, endY,
      vt: window.__fwVt ? { frames: window.__fwVt.frames(), now: window.__fwVt.now(), timersFired: window.__fwVt.fired() } : null, trace: !!P.trace, still: !!P.still,
      hover: matchMedia('(hover: hover)').matches, pointerCoarse: matchMedia('(pointer: coarse)').matches,
      hoverElements: document.querySelectorAll(':hover').length, missing, bootstrap: window.__wkBootstrap || null,
      internalsKeys: ['lastStyleUpdateSize', 'styleRecalcCount', 'renderingUpdateCount', 'styleInvalidationTraversalCount', 'layerFlushCount', 'layoutUpdateCount', 'compositingUpdateCount'].filter((n) => n in I),
    });
    out('params', P);
    for (let k = 0; k < ys.length; k++) out('step', { k, y: ys[k], b: bounds[k], mids: mids[k] });
    out('end', { b: bounds[ys.length] });
  };
  addEventListener('load', () => {
    run().catch((e) => out('error', { message: String(e && e.message || e), stack: String(e && e.stack || '') })).then(() => { out('done', {}); testRunner.notifyDone(); });
  });
})();`;

/**
 * The harness: the same bootstrap as the Inspector lane (pinned Date, seeded Math.random; measure-webkit/src/page.mjs),
 * then the run. `params`: { step, frames, settleMs }.
 */
export function harnessSource({ step = 50, frames = 2, settleMs = 6000, clock = 'pinned', warm = false, vt = false, trace = false, still = false, cases = 0 } = {}) {
  if (!Number.isInteger(frames) || frames < 1) throw new Error('frames must be an integer >= 1');
  if (!Number.isInteger(step) || step < 1) throw new Error('step must be an integer >= 1');
  if (!Number.isInteger(cases) || cases < 0) throw new Error('cases must be an integer >= 0');
  // `vt` (virtual time, vtime.mjs) replaces the pinned Date with its own clock; Math.random stays seeded either way
  const pre = 'window.__fwN = { st: window.setTimeout.bind(window) };\n';
  return pre + bootstrapSource({ clock: vt ? 'live' : clock }) + '\n' + (vt ? VT_SRC + '\n' : '') + (trace ? TRACE_SRC + '\n' : '') +
    RUN_SRC.replace('__PARAMS__', JSON.stringify({ step, frames, settleMs, clock: vt ? 'vt' : clock, warm: !!warm, trace: !!trace, still: !!still, cases }));
}
