import { DURATION_MS, FADE_END, fade } from '../morph.tween/logic';

export const FADE_THREADED = 'fade-threaded';

export const FADED_PAUSE = 'faded-pause';

export const FADED_PAUSE_FLAG = 'platform:faded-pause';

export const BLUR_MAX = 12;

export const EASING = [1 / 3, 1, 2 / 3, 1] as const;

export const EASING_CSS = `cubic-bezier(${EASING.join(', ')})`;

export interface Kf {
  off: number;
  fade: number;
  blur: number;
}

export function blurOf(v: number): number {
  return (1 - v) * BLUR_MAX;
}

export function kink(from: number, to: number): number {
  return to === from ? 0 : (FADE_END - from) / (to - from);
}

export function keyframes(from: number, to: number): Kf[] {
  const at = (off: number, v: number): Kf => ({ off, fade: v, blur: blurOf(v) });
  const k = kink(from, to);
  const ends = [at(0, fade({ m: from })), at(1, fade({ m: to }))];
  return 0 < k && k < 1 ? [ends[0]!, at(k, 0), ends[1]!] : ends;
}

/** Lean `PlatformFadedPause.zero`: the section's fade is 0 (m at or past FADE_END). */
export function fadedZero(m: number): boolean {
  return fade({ m }) === 0;
}

export function constants() {
  return { blurMax: BLUR_MAX, duration: DURATION_MS, fadeEnd: FADE_END, easing: [...EASING] };
}
