// Diagnostic for a refused viewport gate: which elements stick out of the viewport on the right. Page-side expression plus a
// text formatter; no decision logic (the gate itself is Lean Fw.Site.StageMode.gateSize / viewportGate).
export const OVERFLOW_LIMIT = 30;

// Elements whose bounding right edge is beyond the client width, widest first. `clipped` is true when an ancestor with
// overflow other than visible ends inside the viewport (it then adds nothing to scrollWidth). `part` is the nearest data-fw.
export const overflowExpr = (limit = OVERFLOW_LIMIT) => `(() => {
  const vw = document.documentElement.clientWidth;
  const sel = (e) => { let s = e.tagName.toLowerCase(); if (e.id) s += '#' + e.id; const c = typeof e.className === 'string' ? e.className.trim().split(/\\s+/).filter(Boolean).slice(0, 3) : []; return s + c.map((x) => '.' + x).join(''); };
  const clipped = (e) => { for (let a = e.parentElement; a; a = a.parentElement) { const o = getComputedStyle(a); if (o.overflowX !== 'visible' && a.getBoundingClientRect().right <= vw + 0.5) return true; } return false; };
  const out = [];
  for (const e of document.getElementsByTagName('*')) {
    const r = e.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) continue;
    if (r.right <= vw + 0.5) continue;
    const p = e.closest('[data-fw]');
    out.push({ sel: sel(e), part: p ? p.getAttribute('data-fw') : null, right: Math.round(r.right * 100) / 100, left: Math.round(r.left * 100) / 100, width: Math.round(r.width * 100) / 100, pos: getComputedStyle(e).position, clipped: clipped(e) });
  }
  out.sort((a, b) => Number(a.clipped) - Number(b.clipped) || b.right - a.right);
  return { vw, total: out.length, shown: out.slice(0, ${limit}) };
})()`;

export function formatOverflow(o) {
  if (!o) return 'overflow: no listing';
  const lines = o.shown.map((e) => `  ${e.clipped ? 'clipped ' : 'ESCAPES '} right ${e.right} left ${e.left} width ${e.width} ${e.pos} part ${e.part ?? '-'} ${e.sel}`);
  return `overflow: ${o.total} elements end right of the client width ${o.vw}${o.total > o.shown.length ? ` (first ${o.shown.length})` : ''}\n${lines.join('\n')}`;
}
