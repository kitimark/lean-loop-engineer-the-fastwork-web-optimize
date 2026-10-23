/** The declared layers of the hero exit consumers (Lean `exitClaim`). */
export const EXIT_LAYERS = ['hero_copy', 'hero.cue_cue', 'hero.orbit_card', 'hero.deck_article'];

/** Track top (document px), track height, viewport height and width, and the track's variant. */
export const EXIT_GEOM_EXPR = `(() => {
  const t = document.querySelector('[data-fw="hero-exit"]');
  if (!t) return JSON.stringify(null);
  const r = t.getBoundingClientRect();
  return JSON.stringify({ T: Math.round(r.top + scrollY), h: Math.round(r.height), v: innerHeight, vw: innerWidth, dpr: devicePixelRatio, variant: t.getAttribute('data-fw-variant') });
})()`;

/** Boxes of the visible exit consumers; a layer on several elements is keyed `layer#k` by DOM index. */
export const EXIT_BOX_EXPR = `(() => {
  const boxes = {};
  for (const l of ${JSON.stringify(EXIT_LAYERS)}) {
    const els = [...document.querySelectorAll('[data-fw-layer="' + l + '"]')];
    els.forEach((e, k) => {
      if (e.getClientRects().length === 0 || getComputedStyle(e).visibility === 'hidden') return;
      const r = e.getBoundingClientRect();
      boxes[els.length > 1 ? l + '#' + k : l] = [Math.round(r.left * 1e6), Math.round(r.top * 1e6), Math.round(r.width * 1e6), Math.round(r.height * 1e6)];
    });
  }
  return JSON.stringify({ dpr: devicePixelRatio, vw: innerWidth, vh: innerHeight, scrollY: Math.round(scrollY), boxes });
})()`;

/** Whether the threaded hand-over happened: the live attribute, the variant, scroll-driven animations present. */
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

/** The hand-over listener's own event (hero `animationend`), dispatched once when the finished entrance raised none. */
export const EXIT_NUDGE_EXPR = `(() => {
  const t = document.querySelector('[data-fw="hero-exit"]');
  const s = t && t.querySelector('[data-splash]');
  if (!s) return 0;
  s.dispatchEvent(new Event('animationend'));
  return 1;
})()`;

/** Frames waited (at most 120) until the track carries `data-exit-live`. */
export const EXIT_WAIT_EXPR = `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const t = document.querySelector('[data-fw="hero-exit"]');
  let n = 0;
  for (; n < 120 && !(t && t.hasAttribute('data-exit-live')); n++) await raf();
  return n;
})()`;
