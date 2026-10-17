/**
 * Pure logic of morph.tween (no DOM): the 680 ms scroll-jacked tween of `--morph`. Restated from the original
 * (nodes/2.DyWL8TcE.js): constants and clamp 12683-12690, direction 12691-12693, tween 12694-12698, fade 12699-12701,
 * pointer cut 13026, active 13030, tween frame 13033-13035, push 13036-13053, armed/taken 13065-13069.
 * Spec and proofs: lean/Fw/Parts/MorphTween.lean. Golden vectors: packages/contracts/golden/parts/morph.tween.jsonl
 * (logic.test.ts).
 */

/** Tween duration, ms (N2:12694). */
export const DURATION_MS = 680;
/** The platform fades out over the first 0.55 of the morph (N2:12683). */
export const FADE_END = 0.55;
/** Platform pointer events are off below this fade (N2:13026). */
export const POINTER_CUT = 0.05;
/** Active above this (N2:13030). */
export const ACTIVE_CUT = 0.001;
/** Platform box share of the visual viewport height (N2:13068). */
export const FILL_RATIO = 0.45;
/** Platform bottom may be this many px below the viewport bottom (N2:13068). */
export const BOTTOM_SLACK = 8;
/** Pushes with |delta| below this are ignored (N2:12691). */
export const DEADZONE = 1;

export const clamp01 = (x: number): number => Math.min(1, Math.max(0, x));

/** Ease-out cubic `1 - (1 - clamp x)^3` (N2:12688). Written as the product, as the Lean spec does. */
export function ease({ x }: { x: number }): number {
  const u = 1 - clamp01(x);
  return 1 - u * u * u;
}

export interface Sample {
  value: number;
  done: boolean;
}

/** One tween sample (N2:12694-12698). */
export function tween({ from, to, elapsed }: { from: number; to: number; elapsed: number }): Sample {
  const i = clamp01(elapsed / DURATION_MS);
  return i >= 1 ? { value: to, done: true } : { value: from + (to - from) * ease({ x: i }), done: false };
}

/** Direction of a push: null (dead zone), 1 (open, delta > 0) or 0 (close) (N2:12691-12693). */
export function dir({ delta }: { delta: number }): number | null {
  return Math.abs(delta) < DEADZONE ? null : +(delta > 0);
}

/** Platform box test (N2:13065-13068): at least 45 % of the viewport tall, bottom within 8 px below it. */
export function armed({ rectHeight, rectBottom, viewportHeight }: { rectHeight: number; rectBottom: number; viewportHeight: number }): boolean {
  return rectHeight >= viewportHeight * FILL_RATIO && rectBottom <= viewportHeight + BOTTOM_SLACK;
}

/** Whether a push is taken (N2:13069): running, or a downward push while armed. */
export function taken({ active, delta, armed: arm }: { active: boolean; delta: number; armed: boolean }): boolean {
  return active || (delta > 0 && arm);
}

/** Running test (N2:13030): target or value above 0.001. */
export function active({ target, value }: { target: number; value: number }): boolean {
  return target > ACTIVE_CUT || value > ACTIVE_CUT;
}

/** `--morph-fade` (N2:12699-12701). */
export function fade({ m }: { m: number }): number {
  return 1 - Math.min(1, m / FADE_END);
}

/** Platform `pointer-events: none` iff the fade is below 0.05 (N2:13026). */
export function pointerNone({ m }: { m: number }): boolean {
  return fade({ m }) < POINTER_CUT;
}

export interface St {
  value: number;
  target: number;
  from: number;
  to: number;
  start: number;
  pending: boolean;
}

export const REST: St = { value: 0, target: 0, from: 0, to: 0, start: 0, pending: false };

/** A taken push toward `goal` (0 or 1) at `now` (N2:13036-13053). */
export function push({ state, goal, reduced, now }: { state: St; goal: number; reduced: boolean; now: number }): St {
  if (state.target === goal && state.to === goal) return state;
  if (reduced) return { ...state, value: goal, target: goal, to: goal, pending: false };
  return { ...state, target: goal, from: state.value, to: goal, start: now, pending: true };
}

/** One animation frame at `now` (N2:13033-13035). */
export function frame({ state, now }: { state: St; now: number }): St {
  const z = tween({ from: state.from, to: state.to, elapsed: now - state.start });
  return { ...state, value: z.value, pending: !z.done };
}
