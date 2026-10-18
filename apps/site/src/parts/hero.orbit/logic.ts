/**
 * Pure maths of the hero ring splash (no DOM). Follows the Lean spec `lean/Fw/Parts/HeroOrbit.lean`; golden vectors:
 * packages/contracts/golden/parts/hero.orbit.jsonl (checked by logic.test.ts). Original: nodes/2.DyWL8TcE.js:4016-4229.
 * Angles are in degrees here and in Lean; `place` converts to radians exactly as the Lean `Float` spec does.
 */

/** Design canvas (N2:4016). */
export const CANVAS_W = 1512;
export const CANVAS_H = 779;
/** Share of the 480 ms move that is the rewind (N2:4019). */
export const REWIND_SHARE = 0.48;
/** Peak motion blur px (N2:4020). */
export const PEAK_BLUR = 5.5;
/** Ring spin in degrees per ms: one turn per 32 s (N2:4047). */
export const OMEGA = 360 / 32000;
export const REWIND_DEG = -14;
export const SURGE_DEG = 140;
export const MOVE_START = 900;
export const MOVE_END = 1380;
export const REST_RADIUS = 248;
export const PULLED_RADIUS = 188;
export const DELAY_BASE = 8;
export const DELAY_STEP = 28;
/** `is-expanding` is set at this many ms into the splash (N2:4155). */
export const EXPAND_AT = 1164;
/** The splash timer (N2:4229). */
export const SPLASH_END = 1820;
export const PULL_BELOW = 1280;
export const PULL_SHARE = 0.35;
export const CHIP = 76;

export type PhaseName = 'idle' | 'rewind' | 'surge' | 'after';
export interface Ph {
  phase: PhaseName;
  t: number;
}

/** Splash clock phase at elapsed ms (Lean `phase`). */
export function phase(i: { e: number }): Ph {
  const e = i.e;
  if (e < MOVE_START) return { phase: 'idle', t: 0 };
  if (e >= MOVE_END) return { phase: 'after', t: 1 };
  const u = (e - MOVE_START) / 480;
  return u < REWIND_SHARE ? { phase: 'rewind', t: u / REWIND_SHARE } : { phase: 'surge', t: (u - REWIND_SHARE) / 0.52 };
}

const ease5 = (t: number) => 1 - (1 - t) ** 5;
const ease3 = (t: number) => 1 - (1 - t) ** 3;

/** Ring angle in degrees (Lean `angleDeg`). */
export function angleDeg(i: { e: number }): number {
  const e = i.e;
  const n = e * OMEGA;
  const p = phase(i);
  switch (p.phase) {
    case 'idle':
      return n;
    case 'rewind':
      return n + REWIND_DEG * ease5(p.t);
    case 'surge':
      return n + REWIND_DEG * (1 - p.t * p.t) + SURGE_DEG * ease3(p.t);
    default:
      return MOVE_END * OMEGA + SURGE_DEG + (e - MOVE_END) * OMEGA * 22;
  }
}

/** Ring radius px (Lean `radius`). */
export function radius(i: { e: number }): number {
  const p = phase(i);
  if (p.phase === 'rewind') return REST_RADIUS - 60 * ease5(p.t);
  if (p.phase === 'surge') return PULLED_RADIUS + 60 * ease3(p.t);
  return REST_RADIUS;
}

/** Motion blur px (Lean `blur`). */
export function blur(i: { e: number }): number {
  const p = phase(i);
  if (p.phase === 'rewind') return PEAK_BLUR * ease5(p.t);
  if (p.phase === 'surge') return PEAK_BLUR * (1 - p.t) * (1 - p.t);
  return 0;
}

/** `--orbit-enter-delay` in ms (Lean `enterDelay`). */
export function enterDelay(i: { k: number }): number {
  return DELAY_BASE + DELAY_STEP * i.k;
}

/** Pull-in of the side cards below 1280 px (Lean `push`). */
export function push(i: { w: number }): number {
  return Math.max(0, (PULL_BELOW - i.w) * PULL_SHARE);
}

/** Scatter vector on exit, `vw` / `vh` (Lean `scatterX`, `scatterY`). */
export function scatter(i: { left: number; top: number }): { x: number; y: number } {
  const leftPct = (i.left / CANVAS_W) * 100;
  const topPct = (i.top / CANVAS_H) * 100;
  const x = leftPct < 50 ? -48 : 48;
  const y = topPct < 25 ? -22 : topPct > 55 ? 32 : leftPct < 50 ? 10 : -8;
  return { x, y };
}

/** Start scale of a card (Lean `chip / width`). */
export function ringScale(i: { width: number }): number {
  return CHIP / i.width;
}

/** Left edge in the band 601..1511 (Lean `leftEdge`). */
export function leftEdge(i: { isLeft: boolean; left: number; right: number; width: number; vw: number }): number {
  return i.isLeft ? i.left - push({ w: i.vw }) : i.vw - (i.right - push({ w: i.vw })) - i.width;
}

export interface Piece {
  readonly id: string;
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;
  readonly rotate: number;
  readonly unit: number;
  readonly float: boolean;
}

/** Rank of each piece on the ring (Lean `ringIndex`): sort by the angle of the piece centre about the canvas centre. */
export function ringIndex(pieces: readonly Piece[]): number[] {
  const ang = (p: Piece) =>
    Math.atan2(
      ((p.top / CANVAS_H) * 100 / 100) * CANVAS_H + p.height / 2 - CANVAS_H / 2,
      ((p.left / CANVAS_W) * 100 / 100) * CANVAS_W + p.width / 2 - CANVAS_W / 2,
    );
  return pieces.map((p) => pieces.filter((q) => ang(q) < ang(p)).length);
}

/** JS `Math.round` (half up), as the original uses it. */
const jsRound = Math.round;

/**
 * Start offset of a card on the ring (Lean `place`, original `F`, N2:4076-4091). `n` is the stage width, `rDeg` the ring
 * angle in degrees, `rho` the radius, `expanded` the `is-expanding` flag. Returns px offsets and the start rotation in tenths
 * of a degree.
 */
export function place(i: {
  left: number;
  top: number;
  width: number;
  height: number;
  idx: number;
  n: number;
  e: number;
  expanded: boolean;
}): { x: number; y: number; rotTenths: number } {
  const u = CANVAS_W;
  const d = CANVAS_H / 2;
  const lp = (i.left / u) * 100;
  const tp = (i.top / CANVAS_H) * 100;
  const o = i.n / 2;
  const r = (angleDeg({ e: i.e }) * Math.PI) / 180;
  const rho = radius({ e: i.e });
  const s = -Math.PI / 2 + (i.idx / 10) * Math.PI * 2 + r;
  const c = o + rho * Math.cos(s);
  const l = d + rho * Math.sin(s);
  const f = (lp / 100) * u;
  const p = u - f - i.width;
  const m = i.expanded && i.n < PULL_BELOW ? Math.max(0, (PULL_BELOW - i.n) * PULL_SHARE) : 0;
  const hx = i.expanded ? (lp < 50 ? f - m + i.width / 2 : i.n - (p - m) - i.width / 2) : f + i.width / 2;
  const g = (tp / 100) * CANVAS_H + i.height / 2;
  const th = (Math.atan2(d - l, o - c) * 180) / Math.PI;
  return { x: jsRound(c - hx), y: jsRound(l - g), rotTenths: jsRound((th - 90) * 10) };
}

/** Argument names the golden conformance test passes (the Lean golden `in` keys). */
export const GOLDEN_ARGS = [
  'phase',
  'angleDeg',
  'radius',
  'blur',
  'enterDelay',
  'push',
  'scatter',
  'ringScale',
  'leftEdge',
  'ringIndex',
  'place',
] as const;
