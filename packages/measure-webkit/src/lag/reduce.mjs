// Twin of lean/Fw/Measure/WebKitLag.lean; test/lag-reduce.test.mjs checks it against golden/measure/webkit-lag.jsonl.
// Rects are [x0, y0, x1, y1] in integer units (the probe passes quarter CSS px).

export const Q = 4;

export const area = ([x0, y0, x1, y1]) => Math.max(0, x1 - x0) * Math.max(0, y1 - y0);
export const inter = (a, b) => [Math.max(a[0], b[0]), Math.max(a[1], b[1]), Math.min(a[2], b[2]), Math.min(a[3], b[3])];

const covers = (clip, box) => area(clip) > 0 && area(clip) <= 2 * area(inter(clip, box.rect));

/** The smallest covering box, the first of equal area; null when none covers. */
export function owner(boxes, clip) {
  let best = null;
  for (const b of boxes) {
    if (!covers(clip, b)) continue;
    if (best === null || area(b.rect) < area(best.rect)) best = b;
  }
  return best === null ? null : best.name;
}

export const ownerName = (boxes, clip) => owner(boxes, clip) ?? '(none)';

/** Values summed by key, keys in order of first appearance. */
export function byKey(entries) {
  const out = [];
  for (const [k, v] of entries) {
    const hit = out.find((e) => e[0] === k);
    if (hit) hit[1] += v; else out.push([k, v]);
  }
  return out;
}

export const coarse = (s) => s.split('-')[0];
export const rollup = (ledger) => byKey(ledger.map(([k, v]) => [coarse(k), v]));

export function regionOf(vh, maxY, y) {
  if (y <= vh) return 'A';
  if (maxY - vh <= y) return 'B';
  if (2 * vh < y && y < maxY - 2 * vh) return 'calm';
  return 'other';
}

export const stepArea = (s) => s.clips.map((c) => [ownerName(s.boxes, c), area(c)]);
export const stepCount = (s) => s.clips.map((c) => [ownerName(s.boxes, c), 1]);

export function regionLedger(vh, maxY, steps, region, f) {
  return byKey(steps.filter((s) => regionOf(vh, maxY, s.y) === region).flatMap(f));
}

export function filterTotals(vp, items) {
  const vis = items.map((f) => ({ ...f, a: area(inter(f.rect, vp)) })).filter((f) => f.a > 0);
  return { count: vis.length, area: vis.reduce((s, f) => s + f.a, 0), areaRadius: vis.reduce((s, f) => s + f.a * f.radius, 0) };
}

const colSum = (rows, j) => rows.reduce((s, r) => s + (r[j] ?? 0), 0);
export const windowOf = (vh, maxY, ys, rows, region) => rows.filter((_, i) => regionOf(vh, maxY, ys[i]) === region);
export const excess = (nR, nC, sR, sC) => sR * nC - sC * nR;

/** Counters ranked by excess over the calm baseline, highest first, ties in column order (a stable sort). */
export function rankRegion(vh, maxY, ys, rows, names, region) {
  const wr = windowOf(vh, maxY, ys, rows, region), wc = windowOf(vh, maxY, ys, rows, 'calm');
  const items = names.map((n, j) => [n, excess(wr.length, wc.length, colSum(wr, j), colSum(wc, j))]);
  return items.map((e, i) => [e, i]).sort((a, b) => b[0][1] - a[0][1] || a[1] - b[1]).map(([e]) => e);
}
