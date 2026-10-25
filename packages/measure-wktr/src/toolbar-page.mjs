// The forced-inset fixture page of the toolbar gate (task toolbar-wktr-gate). One page per flag; the page drives WebKit's
// interactive obscured-insets change through WKTR's UI-script hooks, the same calls as LayoutTests/resources/ui-helper.js:2018-2050
// (UIHelper.beginInteractiveObscuredInsetsChange / setObscuredInsets / endInteractiveObscuredInsetsChange @862f17d):
//   uiController.beginInteractiveObscuredInsetsChange()      Tools/WebKitTestRunner/ios/UIScriptControllerIOS.mm:1486-1489
//   uiController.setObscuredInsets(top, right, bottom, left) Tools/WebKitTestRunner/cocoa/UIScriptControllerCocoa.mm:683-692
//   uiController.endInteractiveObscuredInsetsChange()        Tools/WebKitTestRunner/ios/UIScriptControllerIOS.mm:1491-1494
// A UI script that starts no async task completes at once and calls its callback with the script's value
// (Tools/TestRunnerShared/UIScriptContext/UIScriptContext.cpp:60-65@862f17d), so `typeof uiController.<hook>` answers whether the
// hook is bound in the running WKTR: the page reports it (hooks.*) as the in-process proof the hooks exist.
//
// The page does not use UIHelper.setObscuredInsets: that helper waits for a visible-content-rect update and a presentation
// update after every set, which hides the 100 ms wait it would have to observe (WKWebViewIOS.mm:3256-3268@862f17d). Each set here
// waits only for the UI script to return; then native requestAnimationFrame samples visualViewport.height every frame until it
// changes. `latencyMs` is the time from the set's return to the first frame that sees the new height. Sets follow each other
// without a pause, so every set after the first falls inside the 100 ms window of the update before it.
//
// Flags (the page decides nothing about them; Lean Fw.Parts.MorphMountToolbar.Flag does):
//   default, touch-first, open-once   the page runs no scroll-driven animation
//   unthrottle                        the page runs the production engine.scroll:unthrottle style and flag element
//                                     (apps/site/src/parts/engine.scroll/unthrottle.ts, imported, not copied)
// The platform stand-in is a fixed element of height 3/5 vh0 whose bottom edge is vh0 - 15 (vh0 = visualViewport.height before the
// first set); `gate.mjs` turns the rects the page reports into arm and take decisions.
import { unthrottleCss } from '../../../apps/site/src/parts/engine.scroll/unthrottle.ts';

export const FLAGS = ['default', 'touch-first', 'open-once', 'unthrottle'];
/** Insets in CSS px, applied to the top edge in this order (down), then back (up). */
export const INSETS_DOWN = [10, 20, 30, 40];
export const INSETS_UP = [30, 20, 10, 0];
/** Scroll offset requested before each set (one per step, down then up), so every set is interleaved with a scrollTo. */
export const SCROLLS = [120, 240, 360, 480, 360, 240, 120, 0];

const PAGE_SRC = `(() => {
  const P = __PARAMS__;
  const out = (tag, obj) => console.log('FWWKTR ' + tag + ' ' + JSON.stringify(obj));
  if (!window.testRunner) { out('error', { message: 'no testRunner in this page' }); return; }
  testRunner.dumpAsText();
  testRunner.waitUntilDone();
  const nST = window.setTimeout.bind(window);
  const sleep = (ms) => new Promise((r) => nST(r, ms));
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const ui = (script) => new Promise((ok) => testRunner.runUIScript(script, ok));
  const ev = { resize: 0, vvResize: 0, vvScroll: 0, scroll: 0 };
  addEventListener('resize', () => { ev.resize++; });
  addEventListener('scroll', () => { ev.scroll++; });
  visualViewport.addEventListener('resize', () => { ev.vvResize++; });
  visualViewport.addEventListener('scroll', () => { ev.vvScroll++; });
  const view = () => ({ vvh: visualViewport.height, vvw: visualViewport.width, vvTop: visualViewport.offsetTop, vvPageTop: visualViewport.pageTop, vvScale: visualViewport.scale, ih: innerHeight, sy: scrollY });
  const run = async () => {
    await sleep(P.settleMs);
    const hooks = {};
    for (const n of P.hooks) hooks[n] = await ui('typeof uiController.' + n);
    let lift = null;
    if (P.flag === 'unthrottle') {
      const st = document.createElement('style');
      st.textContent = P.unthrottleCss;
      const el = document.createElement('div');
      el.setAttribute(P.unthrottleAttr, '');
      el.setAttribute('aria-hidden', 'true');
      document.head.appendChild(st);
      document.body.appendChild(el);
      await raf(); await raf(); await sleep(300);
      lift = { animations: document.getAnimations().length, value: getComputedStyle(el).getPropertyValue('--fw-ut') };
    }
    const base = view();
    const vh0 = base.vvh;
    const plat = document.getElementById('p');
    const h = vh0 * P.platform.heightNum / P.platform.heightDen;
    plat.style.height = h + 'px';
    plat.style.top = (vh0 - P.platform.gap - h) + 'px';
    await raf(); await raf();
    const rect = () => { const r = plat.getBoundingClientRect(); return { height: r.height, bottom: r.bottom }; };
    const facts = { ua: navigator.userAgent, innerWidth, innerHeight, dpr: devicePixelRatio, docH: document.documentElement.scrollHeight,
      pointerCoarse: matchMedia('(pointer: coarse)').matches, timelineSupported: CSS.supports('animation-timeline', 'scroll()'), base, rect0: rect() };
    await ui('uiController.beginInteractiveObscuredInsetsChange()');
    const steps = [];
    const seq = P.steps;
    for (let k = 0; k < seq.length; k++) {
      const s = seq[k];
      const before = view();
      const e0 = { ...ev };
      scrollTo({ top: s.scroll, behavior: 'instant' });
      const t0 = performance.now();
      await ui('uiController.setObscuredInsets(' + s.inset + ', 0, 0, 0)');
      const t1 = performance.now();
      let latency = null, frames = 0;
      while (performance.now() - t1 < P.timeoutMs) {
        await raf(); frames++;
        if (visualViewport.height !== before.vvh) { latency = performance.now() - t1; break; }
      }
      await raf();
      const after = view();
      steps.push({ k, dir: s.dir, inset: s.inset, scroll: s.scroll, setMs: t1 - t0, latencyMs: latency, frames, before, after, rect: rect(),
        events: { resize: ev.resize - e0.resize, vvResize: ev.vvResize - e0.vvResize, vvScroll: ev.vvScroll - e0.vvScroll, scroll: ev.scroll - e0.scroll } });
    }
    const duringEnd = { ...ev };
    await ui('uiController.endInteractiveObscuredInsetsChange()');
    await raf(); await sleep(250);
    const afterEnd = { view: view(), eventsDuring: duringEnd, eventsAfter: { ...ev } };
    await ui('uiController.setObscuredInsets(0, 0, 0, 0)');
    out('toolbar', { flag: P.flag, params: { platform: P.platform, timeoutMs: P.timeoutMs }, hooks, lift, facts, steps, afterEnd });
  };
  addEventListener('load', () => {
    run().catch((e) => out('error', { message: String((e && e.message) || e), stack: String((e && e.stack) || '') })).then(() => { out('done', {}); testRunner.notifyDone(); });
  });
})();`;

/** The platform stand-in: height heightNum/heightDen of the viewport height before any inset, bottom edge `gap` px above it (Lean `gateRect`). */
export const PLATFORM = { heightNum: 3, heightDen: 5, gap: 15 };

const HOOKS = ['beginInteractiveObscuredInsetsChange', 'setObscuredInsets', 'endInteractiveObscuredInsetsChange'];

/** The steps the page walks: down (0 to 40) then up (40 to 0), each preceded by its scrollTo. */
export function stepList() {
  return [...INSETS_DOWN.map((inset, i) => ({ dir: 'down', inset, scroll: SCROLLS[i] })), ...INSETS_UP.map((inset, i) => ({ dir: 'up', inset, scroll: SCROLLS[INSETS_DOWN.length + i] }))];
}

/** The page of one flag as an HTML string. */
export function toolbarHtml({ flag, settleMs = 800, timeoutMs = 600 } = {}) {
  if (!FLAGS.includes(flag)) throw new Error(`unknown flag ${flag}; known: ${FLAGS.join(', ')}`);
  const params = { flag, settleMs, timeoutMs, platform: PLATFORM, hooks: HOOKS, steps: stepList(), unthrottleCss: unthrottleCss(), unthrottleAttr: 'data-fw-unthrottle' };
  const script = PAGE_SRC.replace('__PARAMS__', () => JSON.stringify(params));
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>toolbar-wktr-gate fixture: ${flag}</title>
<style>
html, body { margin: 0; }
#tall { height: 6000px; background: #e8e8ee; }
#p { position: fixed; left: 0; width: 120px; background: #3366cc; }
</style>
</head>
<body>
<div id="tall"></div>
<div id="p"></div>
<script>${script.replace(/<\/script/gi, '<\\/script')}</script>
</body>
</html>
`;
}
