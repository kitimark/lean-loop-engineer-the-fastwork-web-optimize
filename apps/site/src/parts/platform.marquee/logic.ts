/**
 * Pure logic of `platform.marquee` (no DOM): the 90 s review marquee. Restated from the original
 * (assets/2.gBuqKVzi.css:6484-6496, 7497). The browser runs the CSS animation; this is the exact reference.
 * Spec and proofs: lean/Fw/Parts/PlatformMarquee.lean. Golden vectors: packages/contracts/golden/parts/platform.marquee.jsonl.
 */

/** One pass in ms (`90s linear infinite`). */
export const PERIOD_MS = 90000;

const frac = (x: number): number => x - Math.floor(x);

/** `translateX` in px of the left-running track of width `w`: `-(w/2) * phase`. */
export function offsetLeft({ w, t }: { w: number; t: number }): number {
  return -(w / 2) * frac(t / PERIOD_MS);
}

/** `translateX` in px of the right-running track: `-(w/2) * (1 - phase)`. */
export function offsetRight({ w, t }: { w: number; t: number }): number {
  return -(w / 2) * (1 - frac(t / PERIOD_MS));
}

/** The animation runs only when motion is allowed. */
export function running({ reduce }: { reduce: boolean }): boolean {
  return !reduce;
}
