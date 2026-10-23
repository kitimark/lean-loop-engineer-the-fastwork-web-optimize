export const EXIT_LAYERS = ['hero_copy', 'hero.cue_cue', 'hero.orbit_card', 'hero.deck_article'];

export const EXIT_GEOM_EXPR = `(() => {
  const t = document.querySelector('[data-fw="hero-exit"]');
  if (!t) return JSON.stringify(null);
  const r = t.getBoundingClientRect();
  return JSON.stringify({ T: Math.round(r.top + scrollY), h: Math.round(r.height), v: innerHeight, vw: innerWidth, dpr: devicePixelRatio, variant: t.getAttribute('data-fw-variant') });
})()`;

// Opaque foreign content in front of a layer (Lean `Fw.Gate.PathPix.Cover`): a COVER_GRID x COVER_GRID grid over the
// layer's part that lies in the viewport; a point counts as covered when an element in front of the layer's own
// elements is opaque (background alpha 1, effective opacity 1). A layer missing from the hit stack counts as not covered.
export const COVER_GRID = 7;

export const EXIT_BOX_EXPR = `(() => {
  const boxes = {}, alpha = {}, cover = {}, parts = {};
  const G = ${COVER_GRID};
  const opa = (e) => { let a = 1; for (let n = e; n && n.nodeType === 1; n = n.parentElement) a *= Number(getComputedStyle(n).opacity); return Math.round(a * 1e4) / 1e4; };
  const opaque = (e) => {
    const m = getComputedStyle(e).backgroundColor.match(/^rgba?\\(([^)]*)\\)$/);
    if (!m) return false;
    const p = m[1].split(/[ ,\\/]+/).filter(Boolean);
    return (p.length > 3 ? Number(p[3]) : 1) === 1 && opa(e) === 1;
  };
  const r2 = (v) => Math.round(v * 100) / 100;
  for (const l of ${JSON.stringify(EXIT_LAYERS)}) {
    const els = [...document.querySelectorAll('[data-fw-layer="' + l + '"]')];
    els.forEach((e, k) => {
      if (e.getClientRects().length === 0 || getComputedStyle(e).visibility === 'hidden') return;
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      const named = [];
      for (const d of [e, ...e.querySelectorAll('*')]) {
        const r = d.getBoundingClientRect();
        if (r.width === 0 && r.height === 0) continue;
        x0 = Math.min(x0, r.left); y0 = Math.min(y0, r.top); x1 = Math.max(x1, r.right); y1 = Math.max(y1, r.bottom);
        if (d !== e && named.length < 40 && d.matches('button, a, p, h1, h2, h3, img, svg, input, [data-fw], [data-face], [data-strip], [class*=countdown], [class*=cta]')) {
          named.push([d.tagName.toLowerCase() + (d.getAttribute('data-fw') ? '[' + d.getAttribute('data-fw') + ']' : '') + (typeof d.className === 'string' && d.className ? '.' + d.className.split(' ')[0] : ''), r2(r.left), r2(r.top), r2(r.width), r2(r.height)]);
        }
      }
      if (x0 === Infinity) return;
      const key = els.length > 1 ? l + '#' + k : l;
      alpha[key] = opa(e);
      boxes[key] = [Math.round(x0 * 1e6), Math.round(y0 * 1e6), Math.round((x1 - x0) * 1e6), Math.round((y1 - y0) * 1e6)];
      parts[key] = named;
      const vx0 = Math.max(0, x0), vy0 = Math.max(0, y0), vx1 = Math.min(innerWidth, x1), vy1 = Math.min(innerHeight, y1);
      let n = 0, hit = 0;
      if (vx1 > vx0 && vy1 > vy0) {
        for (let gy = 0; gy < G; gy++) for (let gx = 0; gx < G; gx++) {
          const x = vx0 + (vx1 - vx0) * (gx + 0.5) / G, y = vy0 + (vy1 - vy0) * (gy + 0.5) / G;
          n++;
          const stack = document.elementsFromPoint(x, y);
          const own = stack.findIndex((t) => e.contains(t));
          if (own > 0 && stack.slice(0, own).some((t) => opaque(t))) hit++;
        }
      }
      cover[key] = { n, k: hit };
    });
  }
  return JSON.stringify({ dpr: devicePixelRatio, vw: innerWidth, vh: innerHeight, scrollY: Math.round(scrollY), dateNow: Date.now(), boxes, alpha, cover, parts });
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

const ACCENT_SIG_SRC = `const sel = '[data-fw="hero-accent"]';
  const sig = (e) => {
    const h = (t) => { let a = 5381; for (let i = 0; i < t.length; i++) a = ((a * 33) ^ t.charCodeAt(i)) >>> 0; return a.toString(16); };
    const svgs = [...e.querySelectorAll('svg')].map((v) => v.getAttribute('viewBox') + ':' + h(v.querySelector('path').getAttribute('d')));
    return h([e.className, e.getAttribute('style'), e.getAttribute('aria-label'), e.querySelector('[data-paint]').getAttribute('style'), ...svgs].join('|'));
  };`;

// Per shot: how many accents, the signature, and whether the site's hook (\`?fwpin=accent\`) is set on the first.
export const ACCENT_SIG_EXPR = `(() => {
  ${ACCENT_SIG_SRC}
  const all = [...document.querySelectorAll(sel)];
  return JSON.stringify({ n: all.length, sig: all.length ? sig(all[0]) : null, pinned: all.length ? all[0].getAttribute('data-fw-pin') === 'accent' : false });
})()`;

// Read only: the accent of the page as the server sent it (the page's own URL without the hook, which the server does not key on) against the live one.
// The site stops its timer chain when \`?fwpin=accent\` is in the URL, so the two must agree and nothing is replaced.
export const ACCENT_SERVED_EXPR = `(() => {
  ${ACCENT_SIG_SRC}
  const live = document.querySelector(sel);
  if (!live) return JSON.stringify({ hooked: false, same: false, why: 'no accent element' });
  const x = new XMLHttpRequest();
  x.open('GET', location.pathname + location.search.replace(/[?&]fwpin=accent(?=&|$)/, '').replace(/^&/, '?'), false);
  x.send();
  if (x.status !== 200) return JSON.stringify({ hooked: false, same: false, why: 'page fetch status ' + x.status });
  const ssr = new DOMParser().parseFromString(x.responseText, 'text/html').querySelector(sel);
  if (!ssr) return JSON.stringify({ hooked: false, same: false, why: 'no accent element in the served page' });
  const hooked = live.getAttribute('data-fw-pin') === 'accent';
  return JSON.stringify({ hooked, n: document.querySelectorAll(sel).length, ssr: sig(ssr), live: sig(live), same: sig(live) === sig(ssr) });
})()`;
