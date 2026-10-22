import { DURATION_MS, FADE_END, fade } from '../morph.tween/logic';

/** Variant `fade-threaded` of platform (Lean `Fw.Parts.PlatformFade`, golden `platform-fade.jsonl`). */
export const FADE_THREADED = 'fade-threaded';

/** Lean `blurMax`: the blur radius in px at fade 0 (`platform.module.css` `.section`). */
export const BLUR_MAX = 12;

/** Lean `p1x, p1y, p2x, p2y`: the effect easing, the morph's ease `1 - (1 - x)^3` as one cubic bezier. */
export const EASING = [1 / 3, 1, 2 / 3, 1] as const;

/** The effect easing as CSS text. */
export const EASING_CSS = `cubic-bezier(${EASING.join(', ')})`;

/** Lean `Kf` with the blur radius it implies (Lean `blurOf`). */
export interface Kf {
  off: number;
  fade: number;
  blur: number;
}

/** Lean `blurOf`. */
export function blurOf(v: number): number {
  return (1 - v) * BLUR_MAX;
}

/** Lean `kink`: eased progress at which a push from `from` to `to` reaches the fade end (0 when they are equal). */
export function kink(from: number, to: number): number {
  return to === from ? 0 : (FADE_END - from) / (to - from);
}

/** Lean `keyframes`: the two ends, plus the kink when the push crosses the fade end strictly inside the effect. */
export function keyframes(from: number, to: number): Kf[] {
  const at = (off: number, v: number): Kf => ({ off, fade: v, blur: blurOf(v) });
  const k = kink(from, to);
  const ends = [at(0, fade({ m: from })), at(1, fade({ m: to }))];
  return 0 < k && k < 1 ? [ends[0]!, at(k, 0), ends[1]!] : ends;
}

/** The golden `const` line. */
export function constants() {
  return { blurMax: BLUR_MAX, duration: DURATION_MS, fadeEnd: FADE_END, easing: [...EASING] };
}
