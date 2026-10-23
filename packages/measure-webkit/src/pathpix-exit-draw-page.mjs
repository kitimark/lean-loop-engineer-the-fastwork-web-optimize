const EM = `document.querySelector('[data-fw="hero-accent"]')`;

/** State of the accent word: class string, label, box in css px, and its animations (idle ones are infinite). */
export const DRAW_STATE_EXPR = `(() => {
  const em = ${EM};
  if (!em) return JSON.stringify(null);
  const r = em.getBoundingClientRect();
  const as = em.getAnimations({ subtree: true });
  return JSON.stringify({
    cls: em.className, label: em.getAttribute('aria-label'), draw: em.getAttribute('data-fw-draw'), variant: em.getAttribute('data-fw-variant'), pin: em.getAttribute('data-fw-pin'),
    rect: [r.left, r.top, r.width, r.height], vw: innerWidth, vh: innerHeight, scrollY: Math.round(scrollY),
    anims: as.length, idleOnly: as.length > 0 && as.every((a) => !Number.isFinite(a.effect.getComputedTiming().iterations)),
    wk: window.__wk ? window.__wk.stats() : null,
  });
})()`;

/** Move the held virtual clock in small steps until the accent's class string differs from `prev`. */
export const drawAdvanceExpr = (prev, capMs, stepMs) => `(async () => {
  const em = ${EM};
  const prev = ${JSON.stringify(prev)};
  let ms = 0;
  while (ms < ${capMs} && em.className === prev) { window.__wk.advance(${stepMs}); ms += ${stepMs}; }
  return JSON.stringify({ advanced: ms, changed: em.className !== prev, cls: em.className, wk: window.__wk.stats() });
})()`;

/** Pause every animation inside the accent word and seek it to `t` ms; the rest of the page stays as FREEZE_EXPR left it. */
export const drawSeekExpr = (t) => `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const em = ${EM};
  await raf(); await raf();
  const mine = document.getAnimations().filter((a) => a.timeline instanceof DocumentTimeline && a.effect && a.effect.target && em.contains(a.effect.target));
  const kinds = mine.map((a) => (a.transitionProperty ? 'transition:' + a.transitionProperty : 'animation') + ':' + Math.round(a.effect.getComputedTiming().duration)).sort();
  for (const a of mine) { a.pause(); a.currentTime = ${Number(t)}; }
  await raf(); await raf();
  const r = em.getBoundingClientRect();
  return JSON.stringify({ n: mine.length, kinds, rect: [r.left, r.top, r.width, r.height], times: mine.map((a) => a.currentTime) });
})()`;
