// Twin of lean/Fw/Measure/WkCost.lean; test/lag-cost.test.mjs checks it against golden/measure/wkcost.jsonl.
// Times are integer microseconds. A frame is [t, zone]; a cost is [zone, paintUs, compUs]; a layer is [id, w, h].
import { readFileSync } from 'node:fs';
import { regionOf } from './reduce.mjs';

/** The constants Lean owns (tweenUs, earlyUs, lateUs, histEdges), read from the generated golden, not typed here. */
const CONST = readFileSync(new URL('../../../contracts/golden/measure/wkcost.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((l) => l.kind === 'const');
export const TWEEN_US = CONST.tweenUs;
export const EARLY_US = CONST.earlyUs;
export const LATE_US = CONST.lateUs;
export const HIST_EDGES = Object.freeze(CONST.histEdges);

/** Display slot of an offset from the first frame: the offset over 50000/3 microseconds, rounded half up (Lean `slotOf`). */
export const slotOf = (d) => Math.floor((6 * d + 50000) / 100000);

/** The interval to the previous frame and the slots skipped since it, [zone of the later frame, d, g] (Lean `deltas`). */
export function deltas(frames) {
  const out = [];
  for (let i = 1; i < frames.length; i++) {
    out.push([frames[i][1], frames[i][0] - frames[i - 1][0], slotOf(frames[i][0] - frames[0][0]) - slotOf(frames[i - 1][0] - frames[0][0])]);
  }
  return out;
}

const count = (ds, z, ok) => ds.filter((x) => x[0] === z && ok(x)).length;
/** Intervals in the zone longer than `th` microseconds (Lean `nOver`). */
export const nOver = (th, z, ds) => count(ds, z, (x) => th < x[1]);
/** Intervals in the zone that jump more than one display slot (Lean `nSkip`). */
export const nSkip = (z, ds) => count(ds, z, (x) => x[2] > 1);
/** Slots skipped in the zone (Lean `nSlots`). */
export const nSlots = (z, ds) => ds.filter((x) => x[0] === z).reduce((s, x) => s + Math.max(0, x[2] - 1), 0);
/** Frames in the zone (Lean `nFrames`). */
export const nFrames = (z, frames) => frames.filter((f) => f[1] === z).length;

/** Histogram bin of an interval: 0 up to the first edge, one bin per edge, the last beyond (Lean `histBin`). */
export function histBin(d) {
  for (let i = 0; i < HIST_EDGES.length; i++) if (d <= HIST_EDGES[i]) return i;
  return HIST_EDGES.length;
}
/** The seven bin counts of a zone (Lean `hist`). */
export function hist(z, ds) {
  const out = new Array(HIST_EDGES.length + 1).fill(0);
  for (const x of ds) if (x[0] === z) out[histBin(x[1])]++;
  return out;
}

/** Cadence of one zone: the fields of the golden `frames` kind. */
export function cadence(z, frames) {
  const ds = deltas(frames);
  return { zone: z, frames: nFrames(z, frames), over25: nOver(25000, z, ds), over34: nOver(34000, z, ds), over50: nOver(50000, z, ds),
    skipped: nSkip(z, ds), slots: nSlots(z, ds), hist: hist(z, ds) };
}

/** A frame is composite-bound when its Composite time exceeds its Paint time (Lean `compositeBound`). */
export const compositeBound = (c) => c[1] < c[2];
/** Frames, Paint time, Composite time and composite-bound frames of a zone (Lean `sumsOf`). */
export function sumsOf(z, costs) {
  const zs = costs.filter((c) => c[0] === z);
  return { frames: zs.length, paintUs: zs.reduce((s, c) => s + c[1], 0), compUs: zs.reduce((s, c) => s + c[2], 0), bound: zs.filter(compositeBound).length };
}

const known = (prev, l) => prev.some((p) => p[0] === l[0]);
/** Layers of the later read that the earlier read did not have (Lean `newLayers`). */
export const newLayers = (prev, cur) => cur.filter((l) => !known(prev, l)).length;
/** Layers of the later read whose composited size differs from the earlier read (Lean `resizedLayers`). */
export const resizedLayers = (prev, cur) => cur.filter((l) => prev.some((p) => p[0] === l[0] && (p[1] !== l[1] || p[2] !== l[2]))).length;
/** Reads in the zone after the first, new layers, and resized layers; a snap is [zone, layers] (Lean `layerSums`). */
export function layerSums(z, snaps) {
  let reads = 0, fresh = 0, resized = 0;
  for (let i = 1; i < snaps.length; i++) {
    if (snaps[i][0] !== z) continue;
    reads++; fresh += newLayers(snaps[i - 1][1], snaps[i][1]); resized += resizedLayers(snaps[i - 1][1], snaps[i][1]);
  }
  return { reads, fresh, resized };
}

/** The end of a morph pushed at `p` (Lean `morphEnd`). */
export const morphEnd = (p) => p + TWEEN_US;
const nIn = (lo, hi, ts) => ts.filter((t) => lo < t && t <= hi).length;
/** Paint starts in the early window after a morph that ends at `e` (Lean `early`). */
export const early = (e, ts) => nIn(e, e + EARLY_US, ts);
/** Paint starts in the late window after the early one (Lean `late`). */
export const late = (e, ts) => nIn(e + EARLY_US, e + EARLY_US + LATE_US, ts);

/** Zone of a morph frame at `t` with the pushes at `po` and `pc` (Lean `morphZone`). */
export function morphZone(po, pc, t) {
  if (t < po) return 'idle';
  if (t <= morphEnd(po)) return 'open';
  if (t < pc) return 'rest';
  if (t <= morphEnd(pc)) return 'close';
  return 'rest';
}
/** Zone of a scroll step (Lean `scrollZone`). */
export const scrollZone = (vh, maxY, y) => `scroll-${regionOf(vh, maxY, y)}`;
