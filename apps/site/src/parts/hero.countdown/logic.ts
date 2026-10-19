/**
 * Pure countdown math for hero.countdown (no DOM, no clock, no Date). Restated from the original's
 * sliding-number and countdown functions (nodes/2.DyWL8TcE.js:3791-3867 spring, digit and face maths;
 * 3905-3910 remaining time). Golden vectors (when present) pin these names and shapes:
 * packages/contracts/golden/parts/hero.countdown.jsonl.
 */

/** Target instant of the original countdown, epoch ms (2026-11-02T12:00:00+07:00 = 05:00:00Z; N2:3905). */
export const TARGET_MS = 1793595600000;

export const SPRING = { stiffness: 280, damping: 18, mass: 0.3 } as const; // N2:3789
export const SPRING_SLICE_MS = 16; // N2:3790

export interface SpringState {
  value: number;
  velocity: number;
}

/** N2:3908-3911. Non-finite input gives 0; otherwise `max(0, ceil((target - now) / 1000))`. */
export function remainingSeconds(nowMs: number, targetMs: number = TARGET_MS): number {
  return Number.isFinite(targetMs) && Number.isFinite(nowMs) ? Math.max(0, Math.ceil((targetMs - nowMs) / 1000)) : 0;
}

/** N2:3911: `[days, hours, minutes, seconds]` from whole seconds. */
export function unitsFromSeconds(total: number): [number, number, number, number] {
  return [Math.floor(total / 86400), Math.floor((total % 86400) / 3600), Math.floor((total % 3600) / 60), total % 60];
}

/** N2:3835-3838 (`JE`): place values of the digits shown for `value`; `padStart` pads to at least 2 digits. */
export function digitPlaces(value: number, padStart = false): number[] {
  const len = String(Math.abs(Math.floor(value))).length;
  const n = padStart ? Math.max(2, len) : len;
  return Array.from({ length: n }, (_, i) => 10 ** (n - i - 1));
}

/** N2:3832-3834 (`qE`): the digit of `value` at `place`. */
export function digitAt(value: number, place: number): number {
  if (place === 0) return 0; // the original would give NaN but never passes 0; match the Lean spec (0), never NaN
  return Math.floor(Math.abs(Math.floor(value)) / place) % 10;
}

/** N2:3827-3831 (`KE`): signed shortest distance in digits from the spring position `current` to face `face`, in (-5, 5] (a half-turn counts as +5). */
export function faceDelta(face: number, current: number): number {
  const mod10 = (x: number) => ((x % 10) + 10) % 10; // floored remainder, as the Lean spec
  const r = mod10(10 + face - mod10(current));
  return r > 5 ? r - 10 : r;
}

/** N2:3799-3826 (`GE`): advance the spring `dtMs` toward `target` in 16 ms slices (the last slice may be shorter). */
export function springStep(
  state: SpringState,
  target: number,
  dtMs: number,
  cfg: { stiffness: number; damping: number; mass: number } = SPRING,
): { state: SpringState; done: boolean } {
  let { value, velocity } = state;
  let left = Math.max(0, dtMs);
  while (left > 0) {
    const dt = Math.min(left, SPRING_SLICE_MS) / 1000;
    left -= SPRING_SLICE_MS;
    const acc = (-cfg.stiffness * (value - target) - cfg.damping * velocity) / cfg.mass;
    velocity += acc * dt;
    value += velocity * dt;
  }
  return Math.abs(velocity) < 0.01 && Math.abs(value - target) < 0.001
    ? { state: { value: target, velocity: 0 }, done: true }
    : { state: { value, velocity }, done: false };
}

/** The faithful face transform, px (N2:3862): `faceDelta(face, a) * cell`. */
export function faceOffsetPx(face: number, spring: number, cellPx: number): number {
  return faceDelta(face, spring) * cellPx;
}

/** `aria-label` of the timer (N2:3945-3948): `"<value> <unit label>"` joined by ", ". */
export function ariaLabel(units: readonly number[], labels: readonly string[]): string {
  return units.map((u, i) => `${u} ${labels[i]}`).join(', ');
}

export interface CountdownMetrics {
  fontPx: number;
  /** integer cell height c = offsetHeight of the digit spacer (line-height 1.3). */
  cellPx: number;
  unitPx: number;
  unitRadiusPx: number;
  unitGapPx: number;
  rowGapPx: number;
  labelPx: number;
}

/** Cell height of a digit: `round(1.3 * font)` (README of 11-breakpoints: c = 31 / 36 / 52). */
export function cellHeight(fontPx: number): number {
  return Math.round(fontPx * 1.3);
}

/**
 * CSS metrics by condition (assets/2.gBuqKVzi.css:1422-1495). `le400` is `(width<=400px)`; `c1000nodw` is
 * `(width<=1000px), (hover: none) and (pointer: coarse) and (width<=1200px)`. The later `<=400` block wins when both match.
 */
export function countdownMetrics(le400: boolean, c1000nodw: boolean): CountdownMetrics {
  if (le400) return { fontPx: 24, cellPx: cellHeight(24), unitPx: 74, unitRadiusPx: 14, unitGapPx: 4, rowGapPx: 6, labelPx: 10 };
  if (c1000nodw) return { fontPx: 28, cellPx: cellHeight(28), unitPx: 88, unitRadiusPx: 16, unitGapPx: 6, rowGapPx: 8, labelPx: 11 };
  return { fontPx: 40, cellPx: cellHeight(40), unitPx: 120, unitRadiusPx: 24, unitGapPx: 8, rowGapPx: 8, labelPx: 14 };
}

/** strip variant (ours, no original counterpart): strip entries are [9,0..9,0]; translate in cells, `-(1 + spring mod 10)`. */
export function stripOffsetCells(spring: number): number {
  return -(1 + (((spring % 10) + 10) % 10));
}
/** The digit shown by strip entry `j` (entries 0..11 are 9,0,1,...,9,0). */
export function stripEntryDigit(j: number): number {
  return (j + 9) % 10;
}

/**
 * Lean `refreshShown` (`shown (refreshNow ⟨readMs⟩ nowMs)`): the digits after a "refresh now" event. The stale reading
 * is forgotten, so the result depends on `nowMs` only.
 */
export function refreshShown(_readMs: number, nowMs: number): [number, number, number, number] {
  return unitsFromSeconds(remainingSeconds(nowMs));
}

/** Golden-vector argument names per function, in call order (lines are {fn, in: {name: value}, out}). */
export const GOLDEN_ARGS: Record<string, string[]> = {
  remainingSeconds: ['nowMs', 'targetMs'],
  unitsFromSeconds: ['total'],
  digitPlaces: ['value', 'padStart'],
  digitAt: ['value', 'place'],
  faceDelta: ['face', 'current'],
  springStep: ['state', 'target', 'dtMs'],
  faceOffsetPx: ['face', 'spring', 'cellPx'],
  ariaLabel: ['units', 'labels'],
  cellHeight: ['fontPx'],
  countdownMetrics: ['le400', 'c1000nodw'],
  stripOffsetCells: ['spring'],
  stripEntryDigit: ['j'],
  refreshShown: ['readMs', 'nowMs'],
};
