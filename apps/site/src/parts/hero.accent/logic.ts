/**
 * Pure state machine of the hand-drawn headline word (no DOM). Follows the Lean spec `lean/Fw/Parts/HeroAccent.lean`;
 * golden vectors: packages/contracts/golden/parts/hero.accent.jsonl. Original: nodes/2.DyWL8TcE.js:3672-3716,
 * assets/2.gBuqKVzi.css:1221-1366.
 */

/** First idle wait ms (N2:3688). */
export const FIRST_WAIT = 2200;
/** Idle wait after the first one (N2:3688). */
export const IDLE_WAIT = 1250;
/** Draw-out and draw-in wait (N2:3697, 3703). */
export const DRAW_WAIT = 900;
/** Visible words after the base word. */
export const WORDS = 6;
/** Box widths in em/64 of the visible words, cursor order (N2:3501-3665, hidden ones removed). */
export const WORD_WIDTHS: readonly number[] = [112, 80, 96, 134, 161, 120];
/** Width of the base word in em/64 (N2:3667). */
export const BASE_WIDTH = 106;
/** One word change in ms. */
export const PERIOD = IDLE_WAIT + DRAW_WAIT + DRAW_WAIT;

export type AccentState = 'idle' | 'draw-out' | 'draw-in';

/** Cursor step (N2:3672-3678): base word -1, words 0..5, then back to -1. */
export function next(i: { c: number }): number {
  const c = i.c;
  return c < 0 ? 0 : c + 1 >= WORDS ? -1 : c + 1;
}

/** Cursor after `j` steps (Lean `cursorAfter`): `(j mod 7) - 1`. */
export function cursorAfter(i: { j: number }): number {
  return (i.j % (WORDS + 1)) - 1;
}

/** Box width in em/64 for a cursor value (Lean `widthOf`). */
export function widthOf(i: { c: number }): number {
  return i.c < 0 ? BASE_WIDTH : (WORD_WIDTHS[i.c] ?? BASE_WIDTH);
}

/** The chain at `e` ms after mount without pause (Lean `chainAt`). */
export function chainAt(i: { e: number }): { state: AccentState; cursor: number } {
  const e = i.e;
  if (e < FIRST_WAIT) return { state: 'idle', cursor: -1 };
  const r = e - FIRST_WAIT;
  const k = Math.floor(r / PERIOD);
  const m = r % PERIOD;
  if (m < DRAW_WAIT) return { state: 'draw-out', cursor: cursorAfter({ j: k }) };
  if (m < DRAW_WAIT + DRAW_WAIT) return { state: 'draw-in', cursor: cursorAfter({ j: k + 1 }) };
  return { state: 'idle', cursor: cursorAfter({ j: k + 1 }) };
}

/** Visible idle frame 0..2 (Lean `idleFrame`). */
export function idleFrame(i: { e: number }): number {
  return Math.floor((i.e % 600) / 200);
}

/** Wait before the next transition (N2:3685-3705): idle waits 2200 the first time only, 1250 otherwise. */
export function waitFor(state: AccentState, firstIdle: boolean): number {
  return state === 'idle' ? (firstIdle ? FIRST_WAIT : IDLE_WAIT) : DRAW_WAIT;
}

export const GOLDEN_ARGS = ['next', 'cursorAfter', 'widthOf', 'chainAt', 'idleFrame'] as const;
