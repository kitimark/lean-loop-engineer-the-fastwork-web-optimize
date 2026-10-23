export const EXIT_LAYERS = ['hero_copy', 'hero.cue_cue', 'hero.orbit_card', 'hero.deck_article'];

export const EXIT_GEOM_EXPR = `(() => {
  const t = document.querySelector('[data-fw="hero-exit"]');
  if (!t) return JSON.stringify(null);
  const r = t.getBoundingClientRect();
  return JSON.stringify({ T: Math.round(r.top + scrollY), h: Math.round(r.height), v: innerHeight, vw: innerWidth, dpr: devicePixelRatio, variant: t.getAttribute('data-fw-variant') });
})()`;

export const EXIT_BOX_EXPR = `(() => {
  const boxes = {}, alpha = {};
  const opa = (e) => { let a = 1; for (let n = e; n && n.nodeType === 1; n = n.parentElement) a *= Number(getComputedStyle(n).opacity); return Math.round(a * 1e4) / 1e4; };
  for (const l of ${JSON.stringify(EXIT_LAYERS)}) {
    const els = [...document.querySelectorAll('[data-fw-layer="' + l + '"]')];
    els.forEach((e, k) => {
      if (e.getClientRects().length === 0 || getComputedStyle(e).visibility === 'hidden') return;
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (const d of [e, ...e.querySelectorAll('*')]) {
        const r = d.getBoundingClientRect();
        if (r.width === 0 && r.height === 0) continue;
        x0 = Math.min(x0, r.left); y0 = Math.min(y0, r.top); x1 = Math.max(x1, r.right); y1 = Math.max(y1, r.bottom);
      }
      if (x0 === Infinity) return;
      alpha[els.length > 1 ? l + '#' + k : l] = opa(e);
      boxes[els.length > 1 ? l + '#' + k : l] = [Math.round(x0 * 1e6), Math.round(y0 * 1e6), Math.round((x1 - x0) * 1e6), Math.round((y1 - y0) * 1e6)];
    });
  }
  return JSON.stringify({ dpr: devicePixelRatio, vw: innerWidth, vh: innerHeight, scrollY: Math.round(scrollY), boxes, alpha });
})()`;

export const EXIT_LIVE_EXPR = `(() => {
  const t = document.querySelector('[data-fw="hero-exit"]');
  const s = t && t.querySelector('[data-splash]');
  const as = document.getAnimations();
  const nonDoc = as.filter((a) => a.timeline && !(a.timeline instanceof DocumentTimeline));
  return JSON.stringify({
    live: !!t && t.hasAttribute('data-exit-live'), variant: t ? t.getAttribute('data-fw-variant') : null, splash: s ? s.getAttribute('data-splash') : null,
    supported: typeof CSS !== 'undefined' && CSS.supports('animation-timeline', 'view()'), anims: as.length, nonDoc: nonDoc.length,
    mode: window.__fw ? window.__fw.mode : null, hash: window.__fw ? window.__fw.configHash : null,
  });
})()`;

export const EXIT_NUDGE_EXPR = `(() => {
  const t = document.querySelector('[data-fw="hero-exit"]');
  const s = t && t.querySelector('[data-splash]');
  if (!s) return 0;
  s.dispatchEvent(new Event('animationend'));
  return 1;
})()`;

export const EXIT_WAIT_EXPR = `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const t = document.querySelector('[data-fw="hero-exit"]');
  let n = 0;
  for (; n < 120 && !(t && t.hasAttribute('data-exit-live')); n++) await raf();
  return n;
})()`;

export const PIN_ACCENT_EXPR = `(() => {
  const sel = '[data-fw="hero-accent"]';
  const live = document.querySelector(sel);
  if (!live) return JSON.stringify({ pinned: false, why: 'no accent element' });
  const sig = (e) => {
    const h = (t) => { let a = 5381; for (let i = 0; i < t.length; i++) a = ((a * 33) ^ t.charCodeAt(i)) >>> 0; return a.toString(16); };
    const svgs = [...e.querySelectorAll('svg')].map((v) => v.getAttribute('viewBox') + ':' + h(v.querySelector('path').getAttribute('d')));
    return h([e.className, e.getAttribute('style'), e.getAttribute('aria-label'), e.querySelector('[data-paint]').getAttribute('style'), ...svgs].join('|'));
  };
  const x = new XMLHttpRequest();
  x.open('GET', location.pathname + location.search, false);
  x.send();
  if (x.status !== 200) return JSON.stringify({ pinned: false, why: 'page fetch status ' + x.status });
  const ssr = new DOMParser().parseFromString(x.responseText, 'text/html').querySelector(sel);
  if (!ssr) return JSON.stringify({ pinned: false, why: 'no accent element in the served page' });
  const before = sig(live);
  live.replaceWith(document.importNode(ssr, true));
  const now = document.querySelector(sel);
  return JSON.stringify({ pinned: true, before, ssr: sig(ssr), after: sig(now), same: sig(now) === sig(ssr) });
})()`;
