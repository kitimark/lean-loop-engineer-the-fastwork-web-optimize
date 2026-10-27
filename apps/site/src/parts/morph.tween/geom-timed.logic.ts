/**
 * Pure logic of morph.tween:geom-timed (no DOM): a push is one Web Animation per track on a shared start time, with the
 * tween's own curve as the easing and the track's keyframes rebased onto the part the push still has to travel.
 * Spec and proofs: lean/Fw/Parts/MorphGeomTimed.lean (rebase_eval, rebase_end, timed_eq_ideal, reverse_continuous,
 * commit_eq, crossMs_some). Golden vectors: packages/contracts/golden/morph-geom-timed.jsonl (geom-timed.golden.test.ts).
 * TS stand-in: `sampledTime` (time tracks of any push except the exact one from rest, no Lean spec yet).
 */
import { DURATION_MS, ease, tween } from './logic';
import { FRAME_MS, evalAt, type Anim } from '../morph.geom/tracks';

/** `cubic-bezier(1/3, 1, 2/3, 1)` is `1 - (1 - x)^3` (Lean bezier_eq_ease), the tween's own curve. */
export const EASING_CSS = `cubic-bezier(${1 / 3},1,${2 / 3},1)`;
/** Thresholds the page reads from `data-fw-morph` (nav 0.001/0.2/0.4/0.55/0.72/0.92) plus the platform pointer cut (fade < 0.05). */
export const CUTS: readonly number[] = [0.001, 0.2, 0.4, 0.5225, 0.55, 0.72, 0.92];

export interface Knots {
  offsets: number[];
  values: number[];
}

function lin(p: number, a: number, q: number, b: number, m: number): number {
  return a + ((b - a) * (m - p)) / (q - p);
}

/** The track `(xs, ys)` (ascending xs) at `m`, held flat outside. */
export function at(xs: number[], ys: number[], m: number): number {
  let k = 0;
  while (k < xs.length - 2 && m > xs[k + 1]) k++;
  return lin(xs[k], ys[k], xs[k + 1], ys[k + 1], m);
}

/** Lean `rebaseUp`: the knots of `m0 < g`, a knot at each end, pulled back onto `[0, 1]` (offset 0 at `m0`, 1 at `g`). */
function rebaseUp(xs: number[], ys: number[], m0: number, g: number): Knots {
  const c = g - m0;
  if (c === 0) return { offsets: [0, 1], values: [at(xs, ys, m0), at(xs, ys, m0)] };
  const inner = xs.map((x, i) => i).filter((i) => xs[i] > m0 && xs[i] < g);
  return {
    offsets: [0, ...inner.map((i) => (xs[i] - m0) / c), 1],
    values: [at(xs, ys, m0), ...inner.map((i) => ys[i]), at(xs, ys, g)],
  };
}

/** Lean `rebase`: up is the trimmed track pulled back, down is the same on the mirrored track, so offsets always ascend. */
export function rebase(xs: number[], ys: number[], m0: number, g: number): Knots {
  if (m0 < g) return rebaseUp(xs, ys, m0, g);
  return rebaseUp(xs.map((x) => -x).reverse(), [...ys].reverse(), -m0, -g);
}

/** Float slack for a threshold that the exact rational tween meets with equality (down to 0.001 at 612 ms). */
const EPS = 1e-12;

/** Lean `crossMs`: the first whole millisecond of the push at which the tween has reached `c` (up: at or above; down: at or below). */
export function crossMs(m0: number, g: number, c: number): number | null {
  for (let n = 0; n <= DURATION_MS; n++) {
    const v = m0 + (g - m0) * ease({ x: n / DURATION_MS });
    if (m0 <= g ? c <= v + EPS : v <= c + EPS) return n;
  }
  return null;
}

/** The ideal tween value `ms` after the push (Lean `idealM`). */
export const idealAt = (from: number, to: number, ms: number): number => tween({ from, to, elapsed: ms }).value;

/** Thresholds a push from `m0` to `g` crosses, with the whole millisecond of each (earliest first). */
export function crossings(m0: number, g: number): { c: number; ms: number }[] {
  const out: { c: number; ms: number }[] = [];
  for (const c of CUTS) {
    if (!((m0 < c && c <= g) || (g <= c && c < m0))) continue;
    const ms = crossMs(m0, g, c);
    if (ms !== null) out.push({ c, ms });
  }
  return out.sort((a, b) => a.ms - b.ms);
}

/** Time of the faithful frames for the tween value `m` (the inverse of the open tween; the geom driver's `timeOf`). */
const timeOf = (m: number): number => DURATION_MS * (1 - Math.cbrt(1 - Math.min(1, Math.max(0, m))));

/**
 * Keyframes of a time track for a push: the exact trim at 680 ms for the push from rest up (the time axis is the push
 * time), else sampled at the 60 Hz grid (TS stand-in). Offsets in `[0, 1]` of the 680 ms, played linear.
 */
export function timeKnots(a: Anim, comp: number, m0: number, g: number): Knots {
  const end = a.offsets.length - 1;
  const ys = a.values[comp];
  if (m0 === 0 && g === 1) {
    const xs = a.offsets.slice(0, end + 1).map((o) => o * (end * FRAME_MS));
    return rebaseUp(xs, ys, 0, DURATION_MS);
  }
  const n = Math.ceil(DURATION_MS / FRAME_MS);
  const ts = [...Array.from({ length: n }, (_, k) => k * FRAME_MS), DURATION_MS];
  return { offsets: ts.map((t) => t / DURATION_MS), values: ts.map((t) => evalAt(a, comp, timeOf(idealAt(m0, g, t)))) };
}
