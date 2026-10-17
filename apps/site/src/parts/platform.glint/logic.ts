/**
 * Pure logic of `platform.glint` (no DOM): the SMIL glint on the two secure-network dashes and its play state.
 * Restated from the original (nodes/2.DyWL8TcE.js:12150-12212, 12269-12275). Spec and proofs:
 * lean/Fw/Parts/PlatformGlint.lean. Golden vectors: packages/contracts/golden/parts/platform.glint.jsonl.
 */

export type Side = 'left' | 'right';

/** One SMIL cycle in ms (`dur="5s"`). */
export const DUR_MS = 5000;
/** Delay between becoming visible and the first `beginElement` (JS `1e3`). */
export const START_DELAY_MS = 1000;
/** Visibility ratio at which the stage counts as visible. */
export const MIN_RATIO = 0.35;

/** The `values` of the `<animate>` elements, six equally spaced key times (`keyTimes="0;0.2;0.4;0.6;0.8;1"`). */
export const X1: Record<Side, readonly number[]> = {
  left: [-200, 200, 200, 200, -200, -200],
  right: [-200, -200, 200, -200, -200, -200],
};
export const X2: Record<Side, readonly number[]> = {
  left: [-80, 320, 320, 320, -80, -80],
  right: [-80, -80, 320, -80, -80, -80],
};
/** The attributes before the first `beginElement`. */
export const REST: Record<Side, readonly [number, number]> = { left: [-200, -80], right: [200, 320] };

const frac = (x: number): number => x - Math.floor(x);
const lerp = (a: number, b: number, w: number): number => a + (b - a) * w;

/** Linear interpolation over the six key times at cycle fraction u in [0, 1). */
export function interp(v: readonly number[], u: number): number {
  const k = Math.min(4, Math.floor(5 * u));
  return lerp(v[k]!, v[k + 1]!, 5 * u - k);
}

/** Gradient end points (x1, x2) `elapsed` ms after the animation began. */
export function sample({ side, elapsed }: { side: Side; elapsed: number }): [number, number] {
  const u = frac(elapsed / DUR_MS);
  return [interp(X1[side], u), interp(X2[side], u)];
}

export interface St {
  /** visible (ratio >= 0.35) */
  h: boolean;
  /** reduced motion */
  g: boolean;
  /** playing (the `<animate>` elements are rendered) */
  v: boolean;
  /** due time (ms) of the pending start timer */
  timer: number | null;
  /** when the animation began */
  t0: number | null;
}

export const init = (reduced: boolean): St => ({ h: false, g: reduced, v: false, timer: null, t0: null });

export type Ev = { kind: 'ratio'; ratio: number } | { kind: 'reduced'; value: boolean } | { kind: 'fire' };

const reset = (s: St, now: number): St => ({ ...s, v: false, t0: null, timer: s.h && !s.g ? now + START_DELAY_MS : null });

/** Next state (JS 12186-12212). */
export function step({ state, now, event }: { state: St; now: number; event: Ev }): St {
  switch (event.kind) {
    case 'ratio': {
      const b = event.ratio >= MIN_RATIO;
      return b === state.h ? state : reset({ ...state, h: b }, now);
    }
    case 'reduced':
      return reset({ ...state, g: event.value }, now);
    case 'fire':
      return state.timer !== null && state.timer <= now ? { ...state, v: true, timer: null, t0: now } : state;
  }
}

/** The gradient end points to draw at `now`: the sample once began, else the rest attributes. */
export function view({ state, side, now }: { state: St; side: Side; now: number }): [number, number] {
  return state.t0 !== null ? sample({ side, elapsed: now - state.t0 }) : [REST[side][0], REST[side][1]];
}
