/**
 * commission: the pure decisions of the section (shrink bands and follower, compact switch, title wrap, underline trigger,
 * scene gate). The Lean spec is `lean/Fw/Parts/Commission.lean`; the golden vectors
 * (`packages/contracts/golden/parts/commission.jsonl`) check this file against it (`logic.test.ts`).
 */

export const ENTER_LO = 0.06;
export const ENTER_HI = 0.42;
export const EXIT_LO = 0.35;
export const EXIT_HI = 0.85;
export const GAIN = 0.22;
export const EPS = 8e-4;
export const DEPTH = 0.083333;
export const RADIUS = 32;
export const RUNWAY = 0.06;
export const ENTER_TOP_CUT = 0.995;
export const CLASS_CUT = 0.04;
export const UL_RATIO = 0.45;
export const UL_DELAY = 900;

const clamp01 = (x: number): number => Math.min(1, Math.max(0, x));

/** t^2 (3 - 2t) of the clamped value (JS 3063). */
export const smooth = (x: number): number => {
  const t = clamp01(x);
  return t * t * (3 - 2 * t);
};

/** The enter value of a card whose top is `top` px in a viewport `h` px tall (JS 3066-3069). */
export const enterRaw = (top: number, h: number): number =>
  top >= ENTER_HI * h ? 1 : top <= ENTER_LO * h ? 0 : clamp01((top - ENTER_LO * h) / ((ENTER_HI - ENTER_LO) * h));

/** The exit value of a section whose bottom is `bottom` px (JS 3070-3075). */
export const exitRaw = (bottom: number, h: number): number =>
  bottom >= EXIT_HI * h ? 0 : bottom <= EXIT_LO * h ? 1 : clamp01((EXIT_HI * h - bottom) / ((EXIT_HI - EXIT_LO) * h));

/** What the follower chases: the smooth step, or a step at one half under reduced motion (JS 3099-3100). */
export const target = (reduced: boolean, x: number): number => (reduced ? (x >= 0.5 ? 1 : 0) : smooth(x));

export interface Pair {
  n: number;
  r: number;
}
export const PAIR0: Pair = { n: 1, r: 0 };

export interface Frame {
  n: number;
  r: number;
  entering: boolean;
  shrinking: boolean;
  runway: number | null;
  more: boolean;
}

/** One frame of the per-frame body (JS 3092-3123). `top` is the card's top, `bottom` the section's bottom. */
export function frame(s: Pair, top: number, bottom: number, h: number, reduced: boolean, compact: boolean): Frame {
  const f = enterRaw(top, h);
  const p = exitRaw(bottom, h);
  const m = target(reduced, f);
  const q = target(reduced, p);
  const g = reduced ? 1 : GAIN;
  const n1 = s.n < m ? m : s.n + (m - s.n) * g;
  const r1 = s.r + (q - s.r) * g;
  const n2 = Math.abs(m - n1) < EPS ? m : n1;
  const r2 = Math.abs(q - r1) < EPS ? q : r1;
  return {
    n: n2,
    r: r2,
    entering: top < ENTER_TOP_CUT * h && CLASS_CUT < f,
    shrinking: CLASS_CUT < p,
    runway: compact || reduced ? null : RUNWAY * h,
    more: EPS <= Math.abs(m - n2) || EPS <= Math.abs(q - r2),
  };
}

/** The original's `A()` (JS 3085-3090). The driver reads `mq.c1000` from matchMedia; this is the same rule as numbers. */
export const compact = (width: number, deviceWidth: number, touch: boolean): boolean =>
  width <= 1000 || deviceWidth <= 500 || (touch && width <= 1200);

export const titleWrapped = (isCompact: boolean, rects: number): boolean => isCompact && rects > 1;

export type Ul = 'hidden' | 'enter' | 'idle';
export const ulFire = (isIntersecting: boolean, ratio: number): boolean => isIntersecting && UL_RATIO <= ratio;
export const ulStart = (reduced: boolean): Ul => (reduced ? 'idle' : 'enter');
export const ulTimer = (u: Ul): Ul => (u === 'enter' ? 'idle' : u);

/** A card is active from one viewport above to two below (JS 2723-2726). */
export const sceneActive = (top: number, bottom: number, h: number): boolean => -h <= bottom && top <= 2 * h;

/**
 * The `band-gate` write decision (Lean `CommissionOpt.writeNow`): write the two custom properties unless the gate (`mq.c1000`)
 * is on and the follower still moves. A write outside the band includes the first frame after the band is left
 * (`exit_catchup`); a write when the follower settles in the band keeps the section's pair equal to the original's at rest.
 */
export const planWrite = (gated: boolean, moving: boolean): boolean => !(gated && moving);

/** The media-change decision (Lean `CommissionOpt.catchupNow`): write the follower's pair exactly when the gate is off. */
export const planCatchup = (gated: boolean): boolean => !gated;

/** The pair a catch-up writes (Lean `stepC`): `--commission-enter-shrink` and `--commission-shrink` of a follower pair. */
export const catchupPair = (p: Pair): { enter: number; shrink: number } => ({ enter: p.n, shrink: Math.max(p.n, p.r) });

/**
 * The card's look at the inline pair (Lean `CommissionOpt.look`): scale and radius in px, given whether `mq.c1000` matches.
 * Restates commission.module.css:9, 10, 48 with the band's overrides at 438, 439, 446.
 */
export function cardLook(c1000: boolean, enter: number, shrink: number): { scale: number; radius: number } {
  if (c1000) return { scale: 1, radius: 0 };
  const w = Math.max(enter, shrink);
  return { scale: 1 - DEPTH * w, radius: RADIUS * w };
}
