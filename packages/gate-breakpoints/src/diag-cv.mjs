// DIAGNOSTIC v3 (task commission-margin-recur round 2b, temporary): which sequence of resizes and reads cures the stale used margin.
export const DIAG_INIT = '';
/** One snapshot: the style margin of the inner box and the margin derived from the geometry. arg: { inner, tag } */
export function diagSnap(arg) {
  const inner = document.querySelector(arg.inner);
  const rows = document.querySelector(arg.rows);
  if (!inner) return { tag: arg.tag, missing: true };
  const cs = (e, p) => getComputedStyle(e).getPropertyValue(p);
  const r = inner.getBoundingClientRect();
  const pr = inner.parentElement.getBoundingClientRect();
  const derived = Math.round((r.left - pr.left - parseFloat(cs(inner.parentElement, 'padding-left'))) * 100) / 100;
  const rr = rows ? rows.getBoundingClientRect() : null;
  const rp = rows ? rows.parentElement.getBoundingClientRect() : null;
  const rderived = rows ? Math.round((rr.left - rp.left - parseFloat(cs(rows.parentElement, 'padding-left'))) * 100) / 100 : null;
  return { tag: arg.tag, ml: cs(inner, 'margin-inline-start'), derived, rl: rows ? cs(rows, 'margin-inline-start') : null, rderived, iw: window.innerWidth };
}
