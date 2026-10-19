// DIAGNOSTIC (task commission-margin-recur round 2, temporary, removed with the fix): how the used margin of the commission inner
// box reads right after a fresh load in a content-visibility:auto skipped subtree, under a sequence of reads. Output: stderr lines
// `DIAGCV {json}`, one per load, written as soon as the load ends.
export const DIAG_INIT = `(() => {
  window.__cvlog = [];
  const t0 = () => { try { return Math.round(performance.now()); } catch { return -1; } };
  document.addEventListener('contentvisibilityautostatechange', (e) => {
    window.__cvlog.push(['ev', t0(), e.skipped, (e.target.className || e.target.tagName || '').toString().slice(0, 30)]);
  }, true);
})();`;

/** One snapshot: skip state, the margin read, a rect read, the margin read again, the geometry-derived margin.
 * arg: { inner, rows, section, tag } */
export function diagSnap(arg) {
  const q = (s) => document.querySelector(s);
  const inner = q(arg.inner), rows = q(arg.rows), sec = q(arg.section);
  if (!inner || !sec) return { tag: arg.tag, missing: true };
  const cs = (e, p) => getComputedStyle(e).getPropertyValue(p);
  const o = { tag: arg.tag };
  o.sk = [sec.checkVisibility(), sec.checkVisibility({ contentVisibilityAuto: true })];
  o.ml1 = cs(inner, 'margin-inline-start');
  const r = inner.getBoundingClientRect();
  const pr = inner.parentElement.getBoundingClientRect();
  o.x = Math.round(r.x * 100) / 100; o.w = Math.round(r.width * 100) / 100;
  o.derived = Math.round((r.left - pr.left - parseFloat(cs(inner.parentElement, 'padding-left'))) * 100) / 100;
  o.ml2 = cs(inner, 'margin-inline-start');
  o.rl = rows ? cs(rows, 'margin-inline-start') : null;
  o.scrollY = window.scrollY; o.iw = window.innerWidth;
  o.ev = (window.__cvlog || []).length;
  return o;
}

export function diagEvents() { return window.__cvlog || []; }
