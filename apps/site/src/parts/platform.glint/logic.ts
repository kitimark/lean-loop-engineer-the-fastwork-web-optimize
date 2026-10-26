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

// ---- platform.glint:hold-freeze ------------------------------------------------------------------------------------
// Spec and proofs: lean/Fw/Parts/PlatformGlintHold.lean. The two repeating `<animate>` per dash become one piece per
// key-time segment and attribute: a ramp (`<animate>`, from to to over one segment) where the value moves, a `<set>`
// where it holds. The pieces tile the 5 s cycle, so an active non-`<set>` animation exists only during a ramp.

export type Attr = 'x1' | 'x2';
export type Kind = 'set' | 'ramp';

export interface Piece {
  attr: Attr;
  seg: number;
  kind: Kind;
  from: number;
  to: number;
}

/** Length of one key-time segment in ms (`dur` over five segments). */
export const SEG_MS = DUR_MS / 5;

const valuesOf = (attr: Attr, side: Side): readonly number[] => (attr === 'x1' ? X1[side] : X2[side]);

/** Pieces of a side: x1 segments 0..4 then x2 segments 0..4. */
export function holdPlan(side: Side): Piece[] {
  const out: Piece[] = [];
  for (const attr of ['x1', 'x2'] as const) {
    const v = valuesOf(attr, side);
    for (let seg = 0; seg < 5; seg++) out.push({ attr, seg, kind: v[seg] === v[seg + 1] ? 'set' : 'ramp', from: v[seg]!, to: v[seg + 1]! });
  }
  return out;
}

/** The segment (0..4) holding cycle fraction u. */
export const segOf = (u: number): number => Math.min(4, Math.floor(5 * u));

/** The (x1, x2) of the one active piece per attribute `elapsed` ms after the anchor began (`elapsed` >= 0). */
export function holdSample({ side, elapsed }: { side: Side; elapsed: number }): [number, number] {
  const r = ((elapsed % DUR_MS) + DUR_MS) % DUR_MS;
  const k = Math.min(4, Math.floor(r / SEG_MS));
  const w = (r - k * SEG_MS) / SEG_MS;
  const plan = holdPlan(side);
  const at = (attr: Attr): number => {
    const p = plan.find((q) => q.attr === attr && q.seg === k)!;
    return p.kind === 'set' ? p.to : lerp(p.from, p.to, w);
  };
  return [at('x1'), at('x2')];
}

/** Active non-`<set>` animations of one dash at `elapsed`: the ramp pieces among the active ones. */
export function holdTicking({ side, elapsed }: { side: Side; elapsed: number }): number {
  const k = Math.min(4, Math.floor((((elapsed % DUR_MS) + DUR_MS) % DUR_MS) / SEG_MS));
  return holdPlan(side).filter((p) => p.seg === k && p.kind === 'ramp').length;
}

/** The faithful pair: two repeating `<animate>` are active at every instant after the begin. */
export const FAITHFUL_TICKING = 2;

export interface HoldEl {
  tag: 'set' | 'animate';
  id: string;
  attributeName: Attr;
  from?: number;
  to: number;
  dur: string;
  fill: 'freeze';
  begin: string;
  /** `beginElement()` is called on it at the start: the segment-0 piece of each attribute */
  anchor: boolean;
}

/**
 * Markup descriptors of a side: per attribute a ring of five pieces with `fill="freeze"`, each beginning at the end of
 * the one before it (segment 0 after segment 4), so every instance time is known a whole segment ahead; `beginElement()`
 * on the two segment-0 pieces starts the rings. INFERRED from runs in both engines (task glint-hold-freeze): without
 * `fill="freeze"` or with offsets from a shared clock element, WebKit dropped pieces in the second cycle or lost the
 * first begin; Chromium parsed `a-b-0.begin` without an offset wrongly (ids carry no hyphen).
 */
export function holdElements(side: Side, idBase: string): HoldEl[] {
  const idOf = (attr: Attr, seg: number): string => `${idBase}${attr.toUpperCase()}S${seg}`;
  return holdPlan(side).map((p): HoldEl => {
    const el: HoldEl = {
      tag: p.kind === 'set' ? 'set' : 'animate',
      id: idOf(p.attr, p.seg),
      attributeName: p.attr,
      to: p.to,
      dur: `${SEG_MS / 1000}s`,
      fill: 'freeze',
      begin: p.seg === 0 ? `indefinite;${idOf(p.attr, 4)}.end` : `${idOf(p.attr, p.seg - 1)}.end`,
      anchor: p.seg === 0,
    };
    if (p.kind === 'ramp') el.from = p.from;
    return el;
  });
}

/** Segments where both attributes hold (only `<set>` pieces are active, nothing ticks). */
export const holdSegments = (side: Side): number[] => [0, 1, 2, 3, 4].filter((k) => holdPlan(side).every((p) => p.seg !== k || p.kind === 'set'));
