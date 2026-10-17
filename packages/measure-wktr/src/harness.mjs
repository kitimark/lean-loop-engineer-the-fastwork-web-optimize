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
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const raf = (fn) => new Promise((res) => requestAnimationFrame(() => res(fn())));
  const schedule = (maxY, step) => { const ys = []; for (let y = 0; y < maxY; y += step) ys.push(y); ys.push(maxY); return ys; };
  const TRACK = ['startTrackingStyleRecalcs', 'startTrackingRenderingUpdates', 'startTrackingLayerFlushes', 'startTrackingLayoutUpdates', 'startTrackingCompositingUpdates'];
  const num = (f) => { try { const v = f(); return typeof v === 'number' ? v : null; } catch { return null; } };
  const snap = () => ({
    rc: num(() => I.renderingUpdateCount()),
    sr: num(() => I.styleRecalcCount()),
    ls: num(() => I.lastStyleUpdateSize),
    si: num(() => I.styleInvalidationTraversalCount),
    lf: num(() => I.layerFlushCount()),
    lu: num(() => I.layoutUpdateCount()),
    cu: num(() => I.compositingUpdateCount()),
  });
  const run = async () => {
    await sleep(P.settleMs);
    // Warm-up (variant "warm"): scroll the whole page once, wait for the images it started loading, go back to the top.
    // The measured pass then meets no lazy-load arrival; trackers are not running yet, so none of this is counted.
    if (P.warm) {
      const h0 = document.documentElement.scrollHeight;
      for (const y of schedule(Math.max(0, h0 - innerHeight), 200)) { scrollTo({ top: y, behavior: 'instant' }); await raf(() => 0); await raf(() => 0); await sleep(40); }
      for (let i = 0; i < 80 && Array.from(document.images).some((im) => !im.complete); i++) await sleep(100);
      scrollTo({ top: 0, behavior: 'instant' });
      await sleep(1500);
    }
    // Layout facts, read once before the run (these reads may force layout; the trackers are started after them).
    const docH = document.documentElement.scrollHeight;
    const maxY = Math.max(0, docH - innerHeight);
    const ys = schedule(maxY, P.step);
    const missing = TRACK.filter((n) => typeof I[n] !== 'function');
    for (const n of TRACK) if (typeof I[n] === 'function') I[n]();
    // two idle frames so the trackers' first reads start from a rendering update that already ran
    await raf(() => 0); await raf(() => 0);
    const bounds = [], mids = [];
    for (let k = 0; k < ys.length; k++) {
      bounds.push(await raf(() => { const s = snap(); scrollTo({ top: ys[k], behavior: 'instant' }); return s; }));
      const m = [];
      for (let f = 1; f < P.frames; f++) m.push(await raf(() => snap()));
      mids.push(m);
    }
    bounds.push(await raf(() => snap()));
    const endY = Math.round(scrollY);
    out('meta', {
      ua: navigator.userAgent, innerWidth, innerHeight, dpr: devicePixelRatio, docH, maxY, endY,
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
export function harnessSource({ step = 50, frames = 2, settleMs = 6000, clock = 'pinned', warm = false } = {}) {
  if (!Number.isInteger(frames) || frames < 1) throw new Error('frames must be an integer >= 1');
  if (!Number.isInteger(step) || step < 1) throw new Error('step must be an integer >= 1');
  return bootstrapSource({ clock }) + '\n' + RUN_SRC.replace('__PARAMS__', JSON.stringify({ step, frames, settleMs, clock, warm: !!warm }));
}
