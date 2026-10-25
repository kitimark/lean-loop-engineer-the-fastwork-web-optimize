// WKTR UI-script hooks, as LayoutTests/resources/ui-helper.js:2018-2050@862f17d:
//   uiController.beginInteractiveObscuredInsetsChange()      Tools/WebKitTestRunner/ios/UIScriptControllerIOS.mm:1486-1489
//   uiController.setObscuredInsets(top, right, bottom, left) Tools/WebKitTestRunner/cocoa/UIScriptControllerCocoa.mm:683-692
//   uiController.endInteractiveObscuredInsetsChange()        Tools/WebKitTestRunner/ios/UIScriptControllerIOS.mm:1491-1494
import { unthrottleCss } from '../../../apps/site/src/parts/engine.scroll/unthrottle.ts';

export const FLAGS = ['default', 'touch-first', 'open-once', 'unthrottle', 'compositable'];
export const INSETS_DOWN = [10, 20, 30, 40];
export const INSETS_UP = [30, 20, 10, 0];
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
    if (P.flag === 'compositable') {
      const st = document.createElement('style');
      st.textContent = P.controlCss;
      const el = document.createElement('div');
      el.id = 'ctl';
      el.setAttribute('aria-hidden', 'true');
      document.head.appendChild(st);
      document.body.appendChild(el);
      await raf(); await raf(); await sleep(300);
      const anims = document.getAnimations();
      lift = { animations: anims.length, timelines: anims.map((a) => a.timeline && a.timeline.constructor.name), states: anims.map((a) => a.playState), transform: getComputedStyle(el).transform };
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

export const CONTROL_CSS = '@keyframes fw-ctl { from { transform: translateX(0); } to { transform: translateX(80px); } } #ctl { position: fixed; left: 200px; top: 0; width: 40px; height: 40px; background: #cc6633; animation: fw-ctl 400ms linear infinite alternate; }';

export const PLATFORM = { heightNum: 3, heightDen: 5, gap: 15 };

const HOOKS = ['beginInteractiveObscuredInsetsChange', 'setObscuredInsets', 'endInteractiveObscuredInsetsChange'];

export function stepList() {
  return [...INSETS_DOWN.map((inset, i) => ({ dir: 'down', inset, scroll: SCROLLS[i] })), ...INSETS_UP.map((inset, i) => ({ dir: 'up', inset, scroll: SCROLLS[INSETS_DOWN.length + i] }))];
}

export function toolbarHtml({ flag, settleMs = 800, timeoutMs = 600 } = {}) {
  if (!FLAGS.includes(flag)) throw new Error(`unknown flag ${flag}; known: ${FLAGS.join(', ')}`);
  const params = { flag, settleMs, timeoutMs, platform: PLATFORM, hooks: HOOKS, steps: stepList(), unthrottleCss: unthrottleCss(), unthrottleAttr: 'data-fw-unthrottle', controlCss: CONTROL_CSS };
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
