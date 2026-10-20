import { clamp01, DURATION_MS, FADE_END } from './logic';

/**
 * Pure plan of the `waapi` variant of morph.tween: the keyframes, offsets and easing of the one animation per element
 * that replaces the per-frame JS lerp. Spec and proofs: lean/Fw/Parts/MorphTweenOpt.lean (MT1 `bezier_eq_ease`, MT3
 * `waapi_eq_tween`, MT4 `flags_same_frame`: a flag is a discrete keyframe quadruple `[0: a, c: a, c: b, 1: b]` at the
 * eased progress `c = clamp01((theta - f) / (t - f))`, and both engines give `b` iff the progress is `>= c`). Golden
 * vectors: packages/contracts/golden/parts/morph-tween-waapi.jsonl and morph-tween-waapi.attr.jsonl (waapi.golden.test.ts).
 */

/** The curve of the effect: in exact arithmetic `1 - (1 - x)^3` (Lean `bezier_eq_ease`, control points 1/3, 1, 2/3, 1). */
export const EASING = `cubic-bezier(${1 / 3}, 1, ${2 / 3}, 1)`;
/** The effect timing: easing on the effect (not per keyframe), the value is held after the end. */
export const TIMING = { duration: DURATION_MS, easing: EASING, fill: 'both' as const };

/** Registered custom properties. `--morph` is the tween, `--morph-fade` its fade on the platform; the other two are flags. */
export const PROP_MORPH = '--morph';
export const PROP_FADE = '--morph-fade';
export const PROP_DARK = '--fw-morph-dark';
export const PROP_EXPANDED = '--fw-morph-expanded';
/** `waapi-scoped`: the platform's own non-inherited copy of the tween value. */
export const PROP_PLATFORM = '--platform-morph';

export type WaapiArm = 'waapi' | 'waapi-scoped';

export interface Registration {
  name: string;
  syntax: string;
  inherits: boolean;
  initialValue: string;
}
/**
 * The `CSS.registerProperty` descriptors (Lean `registrations`, MT-R `registrations_see`): `--morph` inherits, because
 * the nav's `.logo`, `.actions`, `.btn.earn` and the hosted morph panel read it below the animated nav; the flags have
 * no reader below the nav and do not inherit. `--morph-fade` inherits as the original's unregistered property does, and
 * is registered so that its computed value is a number (`1` at rest), as the original's. Golden rows: morph-tween-waapi.jsonl.
 */
export const REGISTRATIONS: readonly Registration[] = [
  { name: PROP_MORPH, syntax: '<number>', inherits: true, initialValue: '0' },
  { name: PROP_FADE, syntax: '<number>', inherits: true, initialValue: '1' },
  { name: PROP_DARK, syntax: '<number>', inherits: false, initialValue: '0' },
  { name: PROP_EXPANDED, syntax: '<number>', inherits: false, initialValue: '0' },
];
/** Lean `registrationsScoped`: a property inherits iff a strict descendant reads it (`registrationsScoped_rule`). */
export const REGISTRATIONS_SCOPED: readonly Registration[] = [
  { name: PROP_MORPH, syntax: '<number>', inherits: true, initialValue: '0' },
  { name: PROP_FADE, syntax: '<number>', inherits: false, initialValue: '1' },
  { name: PROP_DARK, syntax: '<number>', inherits: false, initialValue: '0' },
  { name: PROP_EXPANDED, syntax: '<number>', inherits: false, initialValue: '0' },
  { name: PROP_PLATFORM, syntax: '<number>', inherits: false, initialValue: '0' },
];

/** The property the platform animation carries per arm. */
export const PLATFORM_PROP: Readonly<Record<WaapiArm, string>> = { waapi: PROP_MORPH, 'waapi-scoped': PROP_PLATFORM };
export const registrationsOf = (arm: WaapiArm): readonly Registration[] => (arm === 'waapi' ? REGISTRATIONS : REGISTRATIONS_SCOPED);

/** Thresholds of the flags (Lean `thresholds`: 1/5, 23/25, 209/400). The original's tests are strict `>`. */
export const THETA_DARK = 1 / 5;
export const THETA_EXPANDED = 23 / 25;
/** pointer cut: `1 - m / FADE_END < 0.05` iff `m > FADE_END * 0.95` = 209/400 */
export const THETA_POINTER = 209 / 400;
/** `--morph-fade` as a CSS expression of `--morph` (Lean `fade_css`). */
export const FADE_CSS = `calc(1 - min(1, var(${PROP_MORPH}) / ${FADE_END}))`;
/** The fade expression per arm (Lean `fade_css`, `fade_eq`). */
export const fadeCss = (arm: WaapiArm): string => `calc(1 - min(1, var(${PLATFORM_PROP[arm]}) / ${FADE_END}))`;

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

/** Keyframes of the platform animation: the arm's platform property (the fade is `fadeCss` of it) and the pointer cut. */
export function platformKeyframes({ from, to }: { from: number; to: number }, arm: WaapiArm = 'waapi'): Kf[] {
  const prop = PLATFORM_PROP[arm];
  return bySort([
    { offset: 0, props: { [prop]: String(from) } },
    ...flagKfs('pointerEvents', THETA_POINTER, from, to, 'auto', 'none'),
    { offset: 1, props: { [prop]: String(to) } },
  ]);
}

/** WAAPI keyframe objects (`{ offset, <prop>: value }`) from a plan. */
export const toWaapi = (kfs: Kf[]): Record<string, string | number>[] => kfs.map((k) => ({ offset: k.offset, ...k.props }));

/** The inline values for a settled morph value (reduced-motion jump; the same flags as the animation's end). */
export function settledProps(
  m: number,
  arm: WaapiArm = 'waapi',
): { nav: Record<string, string>; platform: Record<string, string>; pointerEvents: string } {
  return {
    nav: { [PROP_MORPH]: String(m), [PROP_DARK]: m > THETA_DARK ? '1' : '0', [PROP_EXPANDED]: m > THETA_EXPANDED ? '1' : '0' },
    platform: { [PLATFORM_PROP[arm]]: String(m) },
    pointerEvents: m > THETA_POINTER ? 'none' : '',
  };
}

/** A reader of `data-fw-morph` (Lean `attrReaders`): what it writes, its strict comparison and its threshold. */
export interface AttrReader {
  sel: string;
  cmp: 'gt' | 'lt';
  theta: number;
}
export const ATTR_READERS: readonly AttrReader[] = [
  { sel: 'nav.is-morphing', cmp: 'gt', theta: 1 / 1000 },
  { sel: 'nav.is-on-dark', cmp: 'gt', theta: 1 / 5 },
  { sel: 'nav.earn.tabindex', cmp: 'gt', theta: 2 / 5 },
  { sel: 'nav.earn.aria-hidden', cmp: 'gt', theta: 11 / 20 },
  { sel: 'nav.is-expanded', cmp: 'gt', theta: 23 / 25 },
  { sel: 'panel.data-start-selling-scene', cmp: 'gt', theta: 1 / 1000 },
  { sel: 'panel.aria-hidden', cmp: 'lt', theta: 7 / 20 },
  { sel: 'panel.cta.tabindex', cmp: 'lt', theta: 11 / 20 },
  { sel: 'panel.data-expanded', cmp: 'gt', theta: 23 / 25 },
];
/** One marker per distinct threshold (Lean `markerThetas`). */
export const MARKER_THETAS: readonly number[] = [...new Set(ATTR_READERS.map((r) => r.theta))];

/** The readers' answers for the attribute value `m` (Lean `band`). */
export const band = (m: number): boolean[] => ATTR_READERS.map((r) => (r.cmp === 'gt' ? r.theta < m : m < r.theta));
/** `m` lies strictly past `theta` going from `from` to `to` (Lean `pastS`). */
export const pastS = (from: number, to: number, theta: number, m: number): boolean =>
  (from < to && theta < m) || (to < from && m < theta);
/** `m` has reached `theta` going from `from` to `to` (Lean `reach`). */
export const reach = (from: number, to: number, theta: number, m: number): boolean =>
  (from < to && theta <= m) || (to < from && m <= theta);
/** A push gets a marker for `theta` iff `theta` is not passed at `from` and reached at `to` (Lean `markerB`). */
export const hasMarker = (from: number, to: number, theta: number): boolean =>
  !pastS(from, to, theta, from) && reach(from, to, theta, to);

/** The marker's delay in ms: 1 ms before the push reaches `theta`, at least 0 (golden: at most Lean `dlLo`, so `DlSound`). */
export function markerDelay(from: number, to: number, theta: number): number {
  if (reach(from, to, theta, from)) return 0;
  const c = (theta - from) / (to - from);
  return Math.max(0, DURATION_MS * (1 - Math.cbrt(1 - c)) - 1);
}
