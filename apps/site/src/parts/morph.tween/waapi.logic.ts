import { clamp01, DURATION_MS, FADE_END } from './logic';

/**
 * Pure plan of the `waapi` variant of morph.tween: the keyframes, offsets and easing of the one animation per element
 * that replaces the per-frame JS lerp. Spec and proofs: lean/Fw/Parts/MorphTweenOpt.lean (MT1 `bezier_eq_ease`, MT3
 * `waapi_eq_tween`, MT4 `flags_same_frame`: a flag is a discrete keyframe quadruple `[0: a, c: a, c: b, 1: b]` at the
 * eased progress `c = clamp01((theta - f) / (t - f))`, and both engines give `b` iff the progress is `>= c`). Golden
 * vectors: packages/contracts/golden/parts/morph-tween-waapi.jsonl (waapi.golden.test.ts).
 */

/** The curve of the effect: in exact arithmetic `1 - (1 - x)^3` (Lean `bezier_eq_ease`, control points 1/3, 1, 2/3, 1). */
export const EASING = `cubic-bezier(${1 / 3}, 1, ${2 / 3}, 1)`;
/** The effect timing: easing on the effect (not per keyframe), the value is held after the end. */
export const TIMING = { duration: DURATION_MS, easing: EASING, fill: 'both' as const };

/** Registered custom properties (all `<number>`, not inherited). `--morph` is the tween; the other two are flags. */
export const PROP_MORPH = '--morph';
export const PROP_DARK = '--fw-morph-dark';
export const PROP_EXPANDED = '--fw-morph-expanded';
export const REGISTERED = [PROP_MORPH, PROP_DARK, PROP_EXPANDED] as const;

/** Thresholds of the flags (Lean `thresholds`: 1/5, 23/25, 209/400). The original's tests are strict `>`. */
export const THETA_DARK = 1 / 5;
export const THETA_EXPANDED = 23 / 25;
/** pointer cut: `1 - m / FADE_END < 0.05` iff `m > FADE_END * 0.95` = 209/400 */
export const THETA_POINTER = 209 / 400;
/** `--morph-fade` as a CSS expression of `--morph` (Lean `fade_css`). */
export const FADE_CSS = `calc(1 - min(1, var(${PROP_MORPH}) / ${FADE_END}))`;

/** `kfOffset` clamped: where the value crosses `theta` on an animation from `from` to `to`; 0 for a flat one (`x / 0 = 0`). */
export function flagOffset({ theta, from, to }: { theta: number; from: number; to: number }): number {
  return to === from ? 0 : clamp01((theta - from) / (to - from));
}

export interface Kf {
  offset: number;
  props: Record<string, string>;
}

/** The discrete keyframe quadruple of one flag. */
function flagKfs(prop: string, theta: number, from: number, to: number, off: string, on: string): Kf[] {
  const c = flagOffset({ theta, from, to });
  const a = from > theta ? on : off;
  const b = to > theta ? on : off;
  return [
    { offset: 0, props: { [prop]: a } },
    { offset: c, props: { [prop]: a } },
    { offset: c, props: { [prop]: b } },
    { offset: 1, props: { [prop]: b } },
  ];
}

const bySort = (kfs: Kf[]): Kf[] =>
  kfs
    .map((k, i) => ({ k, i }))
    .sort((x, y) => x.k.offset - y.k.offset || x.i - y.i)
    .map((x) => x.k);

/** Keyframes of the nav animation: `--morph` linear, the dark and expanded flags discrete. */
export function navKeyframes({ from, to }: { from: number; to: number }): Kf[] {
  return bySort([
    { offset: 0, props: { [PROP_MORPH]: String(from) } },
    ...flagKfs(PROP_DARK, THETA_DARK, from, to, '0', '1'),
    ...flagKfs(PROP_EXPANDED, THETA_EXPANDED, from, to, '0', '1'),
    { offset: 1, props: { [PROP_MORPH]: String(to) } },
  ]);
}

/** Keyframes of the platform animation: `--morph` (the fade is `FADE_CSS` of it) and the pointer cut, discrete. */
export function platformKeyframes({ from, to }: { from: number; to: number }): Kf[] {
  return bySort([
    { offset: 0, props: { [PROP_MORPH]: String(from) } },
    ...flagKfs('pointerEvents', THETA_POINTER, from, to, 'auto', 'none'),
    { offset: 1, props: { [PROP_MORPH]: String(to) } },
  ]);
}

/** WAAPI keyframe objects (`{ offset, <prop>: value }`) from a plan. */
export const toWaapi = (kfs: Kf[]): Record<string, string | number>[] => kfs.map((k) => ({ offset: k.offset, ...k.props }));

/** The inline values for a settled morph value (reduced-motion jump; the same flags as the animation's end). */
export function settledProps(m: number): { nav: Record<string, string>; platform: Record<string, string>; pointerEvents: string } {
  return {
    nav: { [PROP_MORPH]: String(m), [PROP_DARK]: m > THETA_DARK ? '1' : '0', [PROP_EXPANDED]: m > THETA_EXPANDED ? '1' : '0' },
    platform: { [PROP_MORPH]: String(m) },
    pointerEvents: m > THETA_POINTER ? 'none' : '',
  };
}
