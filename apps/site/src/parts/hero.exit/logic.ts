/**
 * Pure scroll-out maths for hero.exit (no DOM). Restated from the original's per-frame handler
 * (nodes/2.DyWL8TcE.js:4155-4172) and the calc() expressions that consume `--exit-opacity` / `--exit-scatter`
 * (assets/2.gBuqKVzi.css:1523-1590, 1725-1740, 1905-1935, 2040-2048). Golden vectors (when present):
 * packages/contracts/golden/parts/hero.exit.jsonl.
 */

/** Pointer events are switched off below this opacity (N2:4171). */
export const POINTER_OFF_BELOW = 0.05;
/** Track height as a share of the viewport height (css 1523-1527: 200vh). */
export const TRACK_VH = 200;
/** Hero min-height outside `(width<=600px)` (css 1536). */
export const HERO_MIN_PX = 680;

/** Scroll range in px: how far the hero can travel inside its track, `max(1, trackHeight - viewportHeight)` (N2:4168). */
export function exitRange(trackHeight: number, viewportHeight: number): number {
  return Math.max(1, trackHeight - viewportHeight);
}

/** `--exit-opacity` (N2:4168-4170): `1 - min(n, max(0, -top)) / n` for the track's rect top. In [0, 1]. */
export function exitOpacity(trackTop: number, trackHeight: number, viewportHeight: number): number {
  const n = exitRange(trackHeight, viewportHeight);
  return 1 - Math.min(n, Math.max(0, -trackTop)) / n;
}

/** `--exit-scatter` (css 1530): `1 - exit-opacity`. */
export function exitScatter(opacity: number): number {
  return 1 - opacity;
}

/** The hero's `pointer-events` is `none` when true, else the empty string (N2:4171). */
export function pointerOff(opacity: number): boolean {
  return opacity < POINTER_OFF_BELOW;
}

/** One frame (N2:4162-4171): reduced motion writes opacity 1 and clears pointer events without reading the rect. */
export function exitFrame(
  reduced: boolean,
  trackTop: number,
  trackHeight: number,
  viewportHeight: number,
): { opacity: number; pointerNone: boolean } {
  if (reduced) return { opacity: 1, pointerNone: false };
  const opacity = exitOpacity(trackTop, trackHeight, viewportHeight);
  return { opacity, pointerNone: pointerOff(opacity) };
}

/** Track height in px: `200vh`, or `auto` (null) under reduced motion (css 1523, 2128). */
export function trackHeightPx(viewportHeight: number, reduced: boolean): number | null {
  return reduced ? null : (viewportHeight * TRACK_VH) / 100;
}

/** Hero height in px (css 1531-1545, 2043): `100svh`, with min-height 680px except under `(width<=600px)` where it is 100svh. */
export function heroHeightPx(svh: number, le600: boolean): number {
  return le600 ? svh : Math.max(svh, HERO_MIN_PX);
}

/** hero-copy opacity (css 1734, 1932 and mobile 2043): `copy-in * exit-opacity` (mobile: `copy-in` is 1). */
export function copyOpacity(copyIn: number, exitOpacityValue: number): number {
  return copyIn * exitOpacityValue;
}
/** hero-copy blur in px: `(1 - copy-in) * 16 + scatter * 18`; `none` on `(width<=600px)` (returned as 0). */
export function copyBlurPx(copyIn: number, scatter: number, le600: boolean): number {
  return le600 ? 0 : (1 - copyIn) * 16 + scatter * 18;
}
/** hero-copy translateY in px: `(1 - copy-in) * 12 + scatter * -10`; on `(width<=600px)` `scatter * -8` (css 1736, 2045). */
export function copyTranslateYPx(copyIn: number, scatter: number, le600: boolean): number {
  return le600 ? scatter * -8 : (1 - copyIn) * 12 + scatter * -10;
}
/** scroll-cue blur in px: `scatter * 18` once the copy has entered (css 1911, 1933). */
export function cueBlurPx(scatter: number): number {
  return scatter * 18;
}
/** scroll-cue translateY in px: `scatter * -10` with `(width<=600px)` (css 1913), none with `(width>600px)` (css 1934-1936: `translate(-50%)`). */
export function cueTranslateYPx(scatter: number, le600: boolean): number {
  return le600 ? scatter * -10 : 0;
}
/**
 * scroll-cue blur in px, full reading (css 1911, 1925-1928, 1930-1933): `scatter * 18` on `(width<=600px)` or once the
 * desktop ring splash is done; otherwise (desktop, splash running) `(1 - copy-in) * 16 + scatter * 18`.
 * `cueBlurPx` above is the settled reading; they agree when `le600 => copyIn = 1` and `!le600 => splashDone`.
 */
export function cueBlurPxFull(copyIn: number, scatter: number, le600: boolean, splashDone: boolean): number {
  return le600 || splashDone ? scatter * 18 : (1 - copyIn) * 16 + scatter * 18;
}
/**
 * scroll-cue translateY in px, full reading (css 1913, 1930-1935): `0` on desktop once the splash is done, otherwise
 * `(1 - copy-in) * 12 + scatter * -10`.
 */
export function cueTranslateYPxFull(copyIn: number, scatter: number, le600: boolean, splashDone: boolean): number {
  return !le600 && splashDone ? 0 : (1 - copyIn) * 12 + scatter * -10;
}
/** The phone band `(width<=600px)` (its complement `(width>600px)` is the other band; no gap for fractional widths). */
export function le600(width: number): boolean {
  return width <= 600;
}
/**
 * The nav's own hero progress (N2:13002-13007), `min(r, max(0, -top)) / r`, `r = max(1, height - vh)`; `pillPassed` is
 * its `>= 0.72` flip (is-hero-pill off). Equals `1 - exitOpacity`, so one owner serves both.
 */
export function navHeroProgress(trackTop: number, trackHeight: number, viewportHeight: number): { progress: number; pillPassed: boolean } {
  const r = exitRange(trackHeight, viewportHeight);
  const progress = Math.min(r, Math.max(0, -trackTop)) / r;
  return { progress, pillPassed: progress >= 0.72 };
}

/** orbit/deck card opacity (css 1577): `1 - scatter * 0.35`. */
export function cardOpacity(scatter: number): number {
  return 1 - scatter * 0.35;
}
/** orbit/deck card translate component (css 1586-1587): `(1 - entered) * enter + scatter * scatterOffset`. */
export function cardTranslate(entered: number, enter: number, scatter: number, scatterOffset: number): number {
  return (1 - entered) * enter + scatter * scatterOffset;
}

/** Golden-vector argument names per function, in call order (lines are {fn, in: {name: value}, out}). */
export const GOLDEN_ARGS: Record<string, string[]> = {
  exitRange: ['trackHeight', 'viewportHeight'],
  exitOpacity: ['trackTop', 'trackHeight', 'viewportHeight'],
  exitScatter: ['opacity'],
  pointerOff: ['opacity'],
  exitFrame: ['reduced', 'trackTop', 'trackHeight', 'viewportHeight'],
  trackHeightPx: ['viewportHeight', 'reduced'],
  heroHeightPx: ['svh', 'le600'],
  copyOpacity: ['copyIn', 'exitOpacityValue'],
  copyBlurPx: ['copyIn', 'scatter', 'le600'],
  copyTranslateYPx: ['copyIn', 'scatter', 'le600'],
  cueBlurPx: ['scatter'],
  cueTranslateYPx: ['scatter', 'le600'],
  cueBlurPxFull: ['copyIn', 'scatter', 'le600', 'splashDone'],
  cueTranslateYPxFull: ['copyIn', 'scatter', 'le600', 'splashDone'],
  le600: ['width'],
  navHeroProgress: ['trackTop', 'trackHeight', 'viewportHeight'],
  cardOpacity: ['scatter'],
  cardTranslate: ['entered', 'enter', 'scatter', 'scatterOffset'],
};
