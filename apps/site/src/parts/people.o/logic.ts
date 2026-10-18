/**
 * Pure logic of people.o (no DOM): the opening timeline of the "o" and the preview card position. Restated from the
 * original (nodes/2.DyWL8TcE.js): timeline 6214-6245, position 6190-6213. Spec and proofs: lean/Fw/Parts/PeopleO.lean.
 * Golden vectors: packages/contracts/golden/parts/people.o.jsonl (logic.test.ts).
 */

/** Ms from entering the viewport to the stack (N2:6236). */
export const STACK_DELAY = 1300;
/** Ms from the stack to the expansion (N2:6229, 6238). */
export const EXPAND_DELAY = 120;
/** IntersectionObserver threshold on the heading (N2:6252). */
export const THRESHOLD = 0.35;
/** Preview card height used by the flip test, px (N2:6196). */
export const CARD_HEIGHT = 440;

export interface Phase {
  stack: boolean;
  expanded: boolean;
}

/** The two flags `t` ms after the heading entered the viewport. */
export function phase({ reduced, standalone, t }: { reduced: boolean; standalone: boolean; t: number }): Phase {
  if (reduced) return { stack: true, expanded: true };
  if (standalone) return { stack: true, expanded: t >= EXPAND_DELAY };
  return { stack: t >= STACK_DELAY, expanded: t >= STACK_DELAY + EXPAND_DELAY };
}

/** Timer plan for an entry: the delays at which the flags turn on (standalone: stack at once). */
export function plan({ reduced, standalone }: { reduced: boolean; standalone: boolean }): { stackAt: number | null; expandAt: number | null } {
  if (reduced) return { stackAt: null, expandAt: null };
  return standalone ? { stackAt: null, expandAt: EXPAND_DELAY } : { stackAt: STACK_DELAY, expandAt: STACK_DELAY + EXPAND_DELAY };
}

export function cardWidth({ vw }: { vw: number }): number {
  return Math.min(320, vw - 24);
}

export function cardLeft({ vw, x, s }: { vw: number; x: number; s: number }): number {
  const w = cardWidth({ vw });
  return Math.max(12, Math.min(x + s / 2 - w / 2, vw - w - 12));
}

export function cardTop({ vh, y, z }: { vh: number; y: number; z: number }): number {
  return z + 12 + CARD_HEIGHT > vh - 12 ? Math.max(12, y - 12 - CARD_HEIGHT) : z + 12;
}

/** Entry delay of face `i` when stacked but not expanded, ms (CSS 2551). */
export function faceDelay({ i }: { i: number }): number {
  return 170 * i;
}
