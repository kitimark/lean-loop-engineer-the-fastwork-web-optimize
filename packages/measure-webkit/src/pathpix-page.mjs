import { freezeAnimations } from '../../gate-breakpoints/src/page.mjs';

export const BOX_EXPR = `(() => {
  const boxes = {};
  for (const e of document.querySelectorAll('[data-fw-layer]')) {
    if (e.getClientRects().length === 0 || getComputedStyle(e).visibility === 'hidden') continue;
    const r = e.getBoundingClientRect();
    boxes[e.getAttribute('data-fw-layer')] = [Math.round(r.left * 1e6), Math.round(r.top * 1e6), Math.round(r.width * 1e6), Math.round(r.height * 1e6)];
  }
  return JSON.stringify({ dpr: devicePixelRatio, vw: innerWidth, vh: innerHeight, scrollY: Math.round(scrollY), boxes });
})()`;

export const FREEZE_EXPR = `(${freezeAnimations.toString()})()`;

export const MARK_ON = `(() => { const d = document.createElement('div'); d.id = 'fw-pp-mark'; d.style.cssText = 'position:fixed;left:0;top:0;width:100vw;height:100vh;background:#ff00ff;z-index:2147483647;margin:0;padding:0'; document.body.appendChild(d); return 1; })()`;
export const MARK_OFF = `(() => { const d = document.getElementById('fw-pp-mark'); if (d) d.remove(); return 1; })()`;

export const pathSearch = (layer) => `?fwl=${encodeURIComponent(layer).replace(/%2C/gi, ',')}:c`;

export const HOLD_EXPR = `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  for (let i = 0; i < 200 && !(window.__fw && window.__fw.hydrated); i++) await raf();
  await document.fonts.ready;
  const eager = [...document.images].filter((i) => i.loading !== 'lazy');
  await Promise.race([Promise.all(eager.map((i) => (i.complete ? Promise.resolve() : new Promise((r) => { i.addEventListener('load', r, { once: true }); i.addEventListener('error', r, { once: true }); })).then(() => i.decode()).catch(() => {}))), new Promise((r) => setTimeout(r, 4000))]);
  await raf(); await raf();
  window.__wk.hold();
  const em = document.querySelector('[data-fw="hero-accent"]');
  return JSON.stringify({ at: Math.round(performance.now()), word: em ? em.getAttribute('aria-label') : null });
})()`;

export const VIDEO_EXPR = `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const vs = [...document.querySelectorAll('video')];
  for (const v of vs) { v.pause(); if (v.currentTime !== 0) { try { v.currentTime = 0; } catch (e) {} } }
  for (let i = 0; i < 300 && vs.some((v) => v.seeking); i++) await raf();
  await raf(); await raf();
  return JSON.stringify(vs.map((v) => [v.readyState, v.paused, v.currentTime]));
})()`;

export const NEAR_IMAGES_EXPR = `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const vh = innerHeight;
  const near = [...document.images].filter((i) => { const r = i.getBoundingClientRect(); return r.bottom > -vh && r.top < 2 * vh; });
  const all = Promise.all(near.map((i) => (i.complete ? Promise.resolve() : new Promise((r) => { i.addEventListener('load', r, { once: true }); i.addEventListener('error', r, { once: true }); })).then(() => i.decode()).catch(() => {})));
  const cap = (async () => { for (let i = 0; i < 600; i++) await raf(); })();
  await Promise.race([all, cap]);
  await raf(); await raf();
  return near.length;
})()`;

export const IMAGES_READY_EXPR = `[...document.images].every((i) => i.complete || i.loading === 'lazy')`;
