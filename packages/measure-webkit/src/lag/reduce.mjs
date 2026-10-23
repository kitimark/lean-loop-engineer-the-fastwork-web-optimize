// Twin of lean/Fw/Measure/WebKitLag.lean; test/lag-reduce.test.mjs checks it against golden/measure/webkit-lag.jsonl.
// Rects are [x0, y0, x1, y1] in integer units (the probe passes quarter CSS px).
import { readFileSync } from 'node:fs';

export const Q = 4;

/** The constants Lean owns (Fw.Measure.WebKitLag.rareMin, countColumns), read from the generated golden, not typed here. */
const CONST = readFileSync(new URL('../../../contracts/golden/measure/webkit-lag.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((l) => l.kind === 'rareConst');
/** Fewer baseline events than this in one pass make the baseline of that arm and counter rare (Lean `rareMin`). */
export const RARE_MIN = CONST.rareMin;
/** The columns the rare-baseline rule applies to: an allowlist of event counts, never a duration or an area (Lean `countColumns`). */
export const COUNT_COLUMNS = Object.freeze(CONST.countColumns);

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

/** Zone of position `y` at zone height `vh`: Fw.Measure.WebKit.zoneIx, floor(y / vh) and 0 below `y = 0`. */
export const zoneOf = (vh, y) => (vh <= 0 ? 0 : Math.max(0, (y - (((y % vh) + vh) % vh)) / vh));

/** A is zone 0 of the position, B is zone 0 of the distance to the end, calm is zone 2 or above from both ends. */
export function regionOf(vh, maxY, y) {
  if (zoneOf(vh, y) === 0) return 'A';
  if (zoneOf(vh, maxY - y) === 0) return 'B';
  if (zoneOf(vh, y) >= 2 && zoneOf(vh, maxY - y) >= 2) return 'calm';
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

export const colSum = (rows, j) => rows.reduce((s, r) => s + (r[j] ?? 0), 0);
export const windowOf = (vh, maxY, ys, rows, region) => rows.filter((_, i) => regionOf(vh, maxY, ys[i]) === region);

/** Raw excess carries the unit of its column; kept only to show why the probe does not rank by it. */
export const excess = (nR, nC, sR, sC) => sR * nC - sC * nR;

const gcd = (a, b) => { a = Math.abs(a); b = Math.abs(b); while (b) [a, b] = [b, a % b]; return a; };
/** A reduced fraction [num, den] with den > 0 (Rat.divInt). */
export function frac(n, d) {
  const g = gcd(n, d) || 1;
  return d < 0 ? [-n / g, -d / g] : [n / g, d / g];
}
const lt = ([a, b], [c, d]) => BigInt(a) * BigInt(d) < BigInt(c) * BigInt(b);
const le = (x, y) => !lt(y, x);

/** Window-to-baseline ratio (sR / nR) / (sC / nC) as a fraction; unit-free (Lean: ratio_scale). */
export const ratio = (nR, nC, sR, sC) => frac(sR * nC, sC * nR);

/** The ratio of column `j`, or null when it has none (a window without frames, or a baseline sum that is not positive). */
export function colRatio(fR, fC, wr, wc, j) {
  const nR = fR * wr.length, nC = fC * wc.length;
  return nR > 0 && nC > 0 && colSum(wc, j) > 0 ? ratio(nR, nC, colSum(wr, j), colSum(wc, j)) : null;
}

/**
 * Counters ranked by ratio of a window of step rows to a baseline window, highest first, ties in column order.
 * fR and fC are the frames per row of the two windows. Counters without a baseline (sum 0, or an empty window) are `unranked`.
 */
export function rankWindows(fR, fC, wr, wc, names) {
  const rs = names.map((n, j) => [n, colRatio(fR, fC, wr, wc, j)]);
  const items = rs.filter(([, q]) => q !== null);
  const ranked = items.map((e, i) => [e, i]).sort((a, b) => (lt(a[0][1], b[0][1]) ? 1 : lt(b[0][1], a[0][1]) ? -1 : a[1] - b[1])).map(([e]) => e);
  return { ranked, unranked: rs.filter(([, q]) => q === null).map(([n]) => n) };
}

export const rankRegion = (vh, maxY, ys, rows, names, region) =>
  rankWindows(1, 1, windowOf(vh, maxY, ys, rows, region), windowOf(vh, maxY, ys, rows, 'calm'), names);

/** An arm difference is stated only when the per-pass ranges are separated (Lean: verdict). */
export function verdict(orig, faith) {
  if (orig.length === 0 || faith.length === 0) return 'overlap';
  const sepBelow = (lo, hi) => lo.every((x) => hi.every((y) => lt(x, y)));
  if (sepBelow(faith, orig)) return 'lower';
  if (sepBelow(orig, faith)) return 'higher';
  return 'overlap';
}

export const jobVerdicts = (jobs) => jobs.map((j) => verdict(j.a, j.b));

export const tally = (vs) => ({ lower: vs.filter((v) => v === 'lower').length, higher: vs.filter((v) => v === 'higher').length, overlap: vs.filter((v) => v === 'overlap').length });

export const rareBase = (passSums) => passSums.some((x) => x < RARE_MIN);

/** The rare-baseline flag of one cell: `name` is a count column and `rareBase` of its per-pass baseline sums (Lean: flagged). */
export const flagged = (name, passSums) => COUNT_COLUMNS.includes(name) && rareBase(passSums);

/** The verdict on a ratio: none when either arm's baseline is rare, else the range verdict (Lean: ratioVerdict). */
export const ratioVerdict = (rareO, rareF, orig, faith) => (rareO || rareF ? 'rareBaseline' : verdict(orig, faith));

/** The `k` items with the largest value, [y, value] pairs, highest first, equal values in input order. */
export const topK = (k, items) =>
  items.map((e, i) => [e, i]).sort((a, b) => b[0][1] - a[0][1] || a[1] - b[1]).slice(0, k).map(([e]) => e);

/** The part with the most paint area at a step, `(none)` for a step without paint. */
export function topPart(step) {
  const l = byKey(stepArea(step)).map((e, i) => [e, i]).sort((a, b) => b[0][1] - a[0][1] || a[1] - b[1]);
  return l.length ? l[0][0][0] : '(none)';
}

export { le as fracLe, lt as fracLt };
