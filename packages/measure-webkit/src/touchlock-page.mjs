import { LOCK_CSS } from './touchlock.mjs';

/** Installed once per load. Frame samples are read at the start of the rAF list, before the site's own rAF restore. */
export const installJs = (lock) => `(() => {
  const nav = document.querySelector('header.start-selling-top-nav, [data-fw="nav"]');
  const root = document.documentElement;
  const st = window.__tl = { on: false, fr: [], ev: [], ca: [], lock: ${lock ? 'true' : 'false'} };
  const open = () => (nav && Number(nav.style.getPropertyValue('--morph')) > 0.001 ? 1 : 0);
  const y10 = () => Math.round(window.scrollY * 10);
  if (st.lock) { const s = document.createElement('style'); s.textContent = ${JSON.stringify(LOCK_CSS)}; document.head.appendChild(s); }
  const scrollTo = window.scrollTo.bind(window);
  window.scrollTo = function (...a) {
    const o = a[0];
    if (st.on && o && typeof o === 'object' && typeof o.top === 'number' && o.behavior === 'instant') st.ca.push([Math.round(o.top * 10), open(), performance.now()]);
    return scrollTo(...a);
  };
  addEventListener('scroll', () => { if (st.on) st.ev.push([y10(), open(), performance.now()]); }, { capture: true, passive: true });
  const tick = (t) => {
    if (st.on) st.fr.push([y10(), open(), t]);
    if (st.lock) root.classList.toggle('fw-lock', open() === 1);
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  return { nav: !!nav, lock: st.lock, hook: window.scrollTo !== scrollTo };
})()`;

export const nearEndJs = (gapPx) => `(() => new Promise((resolve) => {
  const maxY = document.documentElement.scrollHeight - window.innerHeight;
  window.scrollTo({ top: Math.max(0, maxY - ${gapPx}), behavior: 'instant' });
  setTimeout(() => resolve({ maxY, y: window.scrollY, vh: window.innerHeight }), 1800);
}))()`;

/** Records from the first touchstart until the Node side sets `window.__fwTouchStop`. */
export const windowJs = `(async () => {
  const st = window.__tl;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let begun = false;
  addEventListener('touchstart', () => { if (!begun) { begun = true; st.fr = []; st.ev = []; st.ca = []; st.on = true; } }, { capture: true, passive: true });
  while (!window.__fwTouchStop) await sleep(40);
  st.on = false;
  return { fr: st.fr, ev: st.ev, ca: st.ca, begun, origin: performance.timeOrigin, touch: window.__fwTouch || null,
    maxY10: Math.round((document.documentElement.scrollHeight - window.innerHeight) * 10), finalY10: Math.round(window.scrollY * 10) };
})()`;
