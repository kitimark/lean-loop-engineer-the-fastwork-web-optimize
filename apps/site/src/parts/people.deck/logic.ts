/**
 * Pure logic of people.deck (no DOM): the scroll-driven profile showcase. Restated from the original
 * (nodes/2.DyWL8TcE.js): ease 10753-10762, ranges 10767-10770, fit and offset 10786-10796, pick 10797-10808,
 * tab target 10826-10829, frame 10896-10966, nearest shell 10921-10934. Spec and proofs:
 * lean/Fw/Parts/PeopleDeck.lean. Golden vectors: packages/contracts/golden/parts/people.deck.jsonl (logic.test.ts).
 */

export const MAX_FIT = 1.22;
export const RATE = 0.2;
export const SNAP_SCALE = 0.0008;
export const SNAP_OFFSET = 0.4;
export const SNAP_ORIGIN = 0.15;
export const STICKY_TOP = 48;
export const SHRINK_VH = 1.45;
export const STEP_VH = 0.34;
export const BIAS = 0.35;
export const RAIL_PX = 248;
export const SIDE_PX = 112;
export const DEBOUNCE_MS = 150;

export const clamp01 = (x: number): number => Math.min(1, Math.max(0, x));

/** Ease-in-out cubic (N2:10756). */
export function ae({ x }: { x: number }): number {
  const c = clamp01(x);
  return c < 0.5 ? 4 * c * c * c : 1 - ((2 - 2 * c) * (2 - 2 * c) * (2 - 2 * c)) / 2;
}

export interface Ranges {
  shrink: number;
  prof: number;
  total: number;
}

/** Scroll ranges for viewport height `vh` and `n` professions (N2:10767-10770). */
export function ranges({ vh, n }: { vh: number; n: number }): Ranges {
  const shrink = SHRINK_VH * vh;
  const prof = Math.max(0, n - 1) * STEP_VH * vh;
  return { shrink, prof, total: shrink + prof };
}

/** Progress through the ranges (N2:10905). */
export function progress({ top, total }: { top: number; total: number }): number {
  return Math.min(total, Math.max(0, STICKY_TOP - top));
}

/** Fit scale of the shell (N2:10786-10789 on `max(1, chromeWidth - 248)`). */
export function fit({ vw, deckW }: { vw: number; deckW: number }): number {
  const w = Math.max(1, deckW - RAIL_PX);
  return Math.min(MAX_FIT, Math.max(1, vw - SIDE_PX) / w);
}

/** Horizontal position of the shell centre at scale `s`, origin `o` percent (N2:10791). */
export function de({ left, width, s, o }: { left: number; width: number; s: number; o: number }): number {
  return left + (o / 100) * width * (1 - s) + (width * s) / 2;
}

/** Offset that centres the shell in the chrome (N2:10790-10796). */
export function fe({ deckW, left, width, s, o }: { deckW: number; left: number; width: number; s: number; o: number }): number {
  return deckW / 2 - de({ left, width, s, o });
}

export interface Target {
  scale: number;
  offset: number;
  origin: number;
  railIn: boolean;
  k: number;
}

/** Targets for progress `y` (N2:10896-10918). */
export function tgt({ y, shrink, prof, fit: b, delta }: { y: number; shrink: number; prof: number; fit: number; delta: number }): Target {
  if (y < shrink) {
    const e = ae({ x: y / shrink });
    return { scale: b + (1 - b) * e, offset: delta * (1 - e), origin: 50 + 50 * e, railIn: false, k: 0 };
  }
  return { scale: 1, offset: 0, origin: 100, railIn: true, k: prof <= 0 ? 0 : clamp01((y - shrink) / prof) };
}

/** One value's lerp step with snap (N2:10950-10956). */
export function step({ snap, v, t }: { snap: number; v: number; t: number }): number {
  const v1 = v + (t - v) * RATE;
  return Math.abs(t - v1) < snap ? t : v1;
}

/** Has a value settled on its target? (after the step) */
export function settled({ snap, v, t }: { snap: number; v: number; t: number }): boolean {
  return Math.abs(t - v) < snap;
}

/** JS `Math.round`. */
export function rnd({ x }: { x: number }): number {
  return Math.floor(x + 0.5);
}

/** Profession index for progress `k` with hysteresis (N2:10799-10808). */
export function pe({ cnt, k, cur }: { cnt: number; k: number; cur: number }): number {
  if (cnt <= 1) return 0;
  const n = k * (cnt - 1);
  const r = rnd({ x: n });
  if (r === cur) return cur;
  const b = cur < r ? -BIAS : BIAS;
  return Math.min(cnt - 1, Math.max(0, rnd({ x: n + b })));
}

/** Scroll position a tab click aims at (N2:10826-10829). */
export function gotoTop({ showcaseY, shrink, prof, cnt, idx }: { showcaseY: number; shrink: number; prof: number; cnt: number; idx: number }): number {
  const f = cnt <= 1 ? 0 : idx / (cnt - 1);
  return Math.ceil(showcaseY - STICKY_TOP + shrink + f * prof);
}

/** Index of the centre nearest to the target; the first of equals wins (N2:10924-10934). */
export function nearest({ target, centers }: { target: number; centers: number[] }): number {
  let best = 0;
  let bd = Infinity;
  centers.forEach((c, i) => {
    const d = Math.abs(c - target);
    if (d < bd) {
      bd = d;
      best = i;
    }
  });
  return best;
}
