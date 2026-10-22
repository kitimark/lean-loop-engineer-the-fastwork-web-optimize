// Page-side code of the path-pix lanes. The same text runs in both engines (the Chromium lane keeps a byte-identical copy in
// packages/measure-chromium/src/pathpix.mjs, checked in test/pathpix-lane.test.mjs). The page only reports what it sees.
import { freezeAnimations } from '../../gate-breakpoints/src/page.mjs';

/** JSON of the viewport, the scroll offset and the viewport box [x, y, w, h] of every rendered `data-fw-layer` in micro CSS px. */
export const BOX_EXPR = `(() => {
  const boxes = {};
  for (const e of document.querySelectorAll('[data-fw-layer]')) {
    if (e.getClientRects().length === 0 || getComputedStyle(e).visibility === 'hidden') continue;
    const r = e.getBoundingClientRect();
    boxes[e.getAttribute('data-fw-layer')] = [Math.round(r.left * 1e6), Math.round(r.top * 1e6), Math.round(r.width * 1e6), Math.round(r.height * 1e6)];
  }
  return JSON.stringify({ dpr: devicePixelRatio, vw: innerWidth, vh: innerHeight, scrollY: Math.round(scrollY), boxes });
})()`;

/** The freeze pass of the frozen-clock gate (Lean Fw.Gate.Freeze.freezeAct): finite animations jump to their end, infinite ones pause mid first iteration. */
export const FREEZE_EXPR = `(${freezeAnimations.toString()})()`;

/** Cover the layout viewport with one opaque magenta box (its pixels give the viewport's place in a device screenshot). */
export const MARK_ON = `(() => { const d = document.createElement('div'); d.id = 'fw-pp-mark'; d.style.cssText = 'position:fixed;left:0;top:0;width:100vw;height:100vh;background:#ff00ff;z-index:2147483647;margin:0;padding:0'; document.body.appendChild(d); return 1; })()`;
export const MARK_OFF = `(() => { const d = document.getElementById('fw-pp-mark'); if (d) d.remove(); return 1; })()`;

/** Search of the path-only arm: only `layer` forced onto its own compositing layer (site-layer-opts: `?fwl=<layer>:c`). */
export const pathSearch = (layer) => `?fwl=${encodeURIComponent(layer).replace(/%2C/gi, ',')}:c`;

/** Wait for hydration and fonts, then hold the page's timers (page.mjs TIMER_HOLD_SRC): nothing the page scheduled fires by itself after this. */
export const HOLD_EXPR = `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  for (let i = 0; i < 200 && !(window.__fw && window.__fw.hydrated); i++) await raf();
  await document.fonts.ready;
  const eager = [...document.images].filter((i) => i.loading !== 'lazy');
  await Promise.race([Promise.all(eager.map((i) => (i.complete ? Promise.resolve() : new Promise((r) => { i.addEventListener('load', r, { once: true }); i.addEventListener('error', r, { once: true }); })).then(() => i.decode()).catch(() => {}))), new Promise((r) => setTimeout(r, 4000))]);
  await raf(); await raf();
  return window.__wk.hold();
})()`;

/** True once every eager image has loaded (Chromium lane: the driver pumps frames until this holds; a lazy image below the fold may never load). */
export const IMAGES_READY_EXPR = `[...document.images].every((i) => i.complete || i.loading === 'lazy')`;
