// Pixel reduction of the lane. The grade is the existing Lean-backed `grade` (Fw.Gate.PathPix, TS twin pathpix.mjs); the counts come
// from the path-pix reducers (`deltas`, `split`). `ringSplit` and `glassOf` are descriptive and are TS stand-ins (no Lean golden).
import { createHash } from 'node:crypto';
import { deltas, split, microRat } from '../../../packages/measure-webkit/src/pathpix-analyze.mjs';
import { mask, grade, premises, rawOf } from '../../../packages/measure-webkit/src/pathpix.mjs';
import { sameImage } from '../../../packages/measure-webkit/src/pathpix-png.mjs';

export const hashOf = (img) => createHash('sha256').update(img.rgba).digest('hex').slice(0, 16);

/** The mask of a state: the nav rect (micro CSS px, as `mask` takes it, padded by one device px) or the whole frame. */
export function maskOf(kind, dpr, w, h, box) {
  if (kind === 'frame') return [0, w, 0, h];
  if (!box) throw new Error('a nav mask needs the nav box');
  return mask(dpr, w, h, box);
}

/** Changed pixels of `del` inside `m`, split into the ring of `k` device px along the mask edge and the rest. Pixels on the frame border are not edge. */
export function ringSplit(del, w, m, k = 3) {
  const edge = [], inner = [];
  for (let i = 0; i < del.length; i++) {
    const x = i % w, y = (i - x) / w;
    if (x < m[0] || x >= m[1] || y < m[2] || y >= m[3]) continue;
    const near = (m[0] > 0 && x - m[0] < k) || (m[1] < w && m[1] - 1 - x < k) || (m[2] > 0 && y - m[2] < k) || (y >= 0 && m[3] < del.length / w && m[3] - 1 - y < k);
    (near ? edge : inner).push(del[i]);
  }
  return { edge: rawOf(edge), interior: rawOf(inner) };
}

/** Mean and median of each colour channel over the mask shrunk by `inset` device px on every side. */
export function glassOf(img, m, inset = 12) {
  const x0 = m[0] + inset, x1 = m[1] - inset, y0 = m[2] + inset, y1 = m[3] - inset;
  if (x0 >= x1 || y0 >= y1) return null;
  const hist = [new Uint32Array(256), new Uint32Array(256), new Uint32Array(256)];
  const sum = [0, 0, 0];
  let n = 0;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const o = (y * img.w + x) * 4;
      for (let c = 0; c < 3; c++) { const v = img.rgba[o + c]; hist[c][v]++; sum[c] += v; }
      n++;
    }
  }
  const med = hist.map((hc) => { let acc = 0; for (let v = 0; v < 256; v++) { acc += hc[v]; if (2 * acc >= n) return v; } return 255; });
  return { n, mean: sum.map((s) => Math.round((100 * s) / n) / 100), median: med };
}

export const glassDelta = (a, b) => (a && b ? { mean: a.mean.map((v, i) => Math.round(100 * (b.mean[i] - v)) / 100), median: a.median.map((v, i) => b.median[i] - v) } : null);

/**
 * The arm against every faithful load of the session, and the faithful loads against each other, inside mask `m`.
 * `nearest` is the smallest changed count of the arm against any faithful load; `spread` is the largest changed count between two faithful loads.
 * An arm whose `nearest` is not above the `spread` lies inside the load-to-load variation of the faithful arm.
 */
export function againstLoads(loads, b0, w, m) {
  const inM = (x, y) => { const r = split(deltas(x, y), w, m).inside; return r; };
  const arm = loads.map((x) => inM(x, b0));
  const pairs = [];
  for (let i = 0; i < loads.length; i++) for (let j = i + 1; j < loads.length; j++) pairs.push({ i, j, ...inM(loads[i], loads[j]) });
  const nearest = Math.min(...arm.map((r) => r.changed));
  const spread = Math.max(...pairs.map((r) => r.changed));
  return { arm, pairs, nearest, spread, within: nearest <= spread };
}

/**
 * One cell: arm B against faithful A over mask `m`, with the A/A control C (the faithful arm loaded again).
 * `a0 a1` are two settled shots of A, `b0 b1` of B, `c0 c1` of C. Returns the graded cell and the descriptive counts.
 */
export function pixelCell({ run, engine, dpr, a0, a1, b0, b1, c0, c1, d0 = null, m, box = null, own = null }) {
  const { w } = a0;
  const same = (p, q) => p.w === q.w && p.h === q.h;
  if (![a1, b0, b1, c0, c1].every((x) => same(a0, x))) throw new Error('the captures differ in size');
  const del = deltas(a0, b0);
  const { inside, out, hist } = split(del, w, m);
  const ctrl = split(deltas(a0, c0), w, m);
  const cell = {
    run, engine, lossless: true,
    claim: { props: [], scales: false, text: false, snap: false, compA: false, compB: false, bound: null },
    sameA: sameImage(a0, a1), sameB: sameImage(b0, b1), out, inside,
    control: { same: sameImage(c0, c1), raw: ctrl.inside }, p1: false,
    origin: box ? [microRat(box[0]), microRat(box[1])] : null, dpr, t1: null, stripsAccepted: false,
  };
  const ring = ringSplit(del, w, m);
  const loads = againstLoads([a0, c0, ...(d0 ? [d0] : [])], b0, w, m);
  // `own`: the faithful nav rect inside the union mask. Changes there are the arm's effect on the nav's own pixels (edge and glass),
  // changes in the rest of the union are the extra area an enlarged box covers.
  let ownPart = null;
  if (own) {
    const o = split(del, w, own), oc = split(deltas(a0, c0), w, own);
    ownPart = { mask: own, inside: o.inside, hist: o.hist, ring: ringSplit(del, w, own), control: oc.inside, controlHist: oc.hist, glass: { faithful: glassOf(a0, own), arm: glassOf(b0, own), control: glassOf(c0, own) } };
    ownPart.glass.armDelta = glassDelta(ownPart.glass.faithful, ownPart.glass.arm);
    ownPart.glass.controlDelta = glassDelta(ownPart.glass.faithful, ownPart.glass.control);
  }
  const g0 = glassOf(a0, m), g1 = glassOf(b0, m), gc = glassOf(c0, m);
  return {
    loads, own: ownPart, grade: grade(cell), premises: premises(engine, cell.claim), cell, hist, ring, mask: m,
    controlOut: ctrl.out, controlHist: ctrl.hist,
    glass: { faithful: g0, arm: g1, control: gc, armDelta: glassDelta(g0, g1), controlDelta: glassDelta(g0, gc) },
    hash: { a: hashOf(a0), b: hashOf(b0), c: hashOf(c0) },
  };
}
