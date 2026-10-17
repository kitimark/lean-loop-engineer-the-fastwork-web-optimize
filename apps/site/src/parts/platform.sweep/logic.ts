/**
 * Pure logic of `platform.sweep` (no DOM): the 4 s gradient sweep over the four row-title words. Restated from the
 * original (assets/2.gBuqKVzi.css:5802-5805 keyframes, 11081-11103 rule). The browser runs the CSS animation; this
 * module is the exact reference (what the animation shows at time t) for tests and for any variant that replaces it.
 * Spec and proofs: lean/Fw/Parts/PlatformSweep.lean. Golden vectors: packages/contracts/golden/parts/platform.sweep.jsonl.
 */

/** One pass in ms (`4s linear infinite`). */
export const PERIOD_MS = 4000;

/** Gradient stop positions as fractions of the 300 % image (the CSS percentages). */
export const STOPS = [0, 0.3333, 0.4, 0.45, 0.5, 0.55, 0.6, 0.6667, 1] as const;

export type Rgb = readonly [number, number, number];
const WHITE: Rgb = [255, 255, 255];
const C1: Rgb = [130, 188, 255];
const C2: Rgb = [36, 131, 255];
const C3: Rgb = [255, 102, 244];
const C4: Rgb = [255, 48, 41];
const C5: Rgb = [254, 123, 2];

const frac = (x: number): number => x - Math.floor(x);

/** Cycle fraction in [0, 1). */
export function phase({ t }: { t: number }): number {
  return frac(t / PERIOD_MS);
}

/** `background-position` as a fraction (1 = 100 %): starts at 1, falls to 0, then wraps. */
export function pos({ t }: { t: number }): number {
  return 1 - phase({ t });
}

const mix = (a: Rgb, b: Rgb, w: number): Rgb => [a[0] + (b[0] - a[0]) * w, a[1] + (b[1] - a[1]) * w, a[2] + (b[2] - a[2]) * w];
const seg = (u: number, u0: number, u1: number, a: Rgb, b: Rgb): Rgb => mix(a, b, (u - u0) / (u1 - u0));

/** Gradient colour at image coordinate u in [0, 1]. */
export function color({ u }: { u: number }): Rgb {
  if (u <= 0.3333) return WHITE;
  if (u <= 0.4) return seg(u, 0.3333, 0.4, WHITE, C1);
  if (u <= 0.45) return seg(u, 0.4, 0.45, C1, C2);
  if (u <= 0.5) return seg(u, 0.45, 0.5, C2, C3);
  if (u <= 0.55) return seg(u, 0.5, 0.55, C3, C4);
  if (u <= 0.6) return seg(u, 0.55, 0.6, C4, C5);
  if (u <= 0.6667) return seg(u, 0.6, 0.6667, C5, WHITE);
  return WHITE;
}

/** The effect applies only when the visitor has not asked for reduced motion. */
export function active({ reduce }: { reduce: boolean }): boolean {
  return !reduce;
}
