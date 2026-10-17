/**
 * Pure logic of nav.hitTest (no DOM). Original: _app/immutable/nodes/2.DyWL8TcE.js
 *   selector lists 12936-12937, j (classify) 12950-12954, F (probe) 12955-12963, `z(g, F(), !0)` 13001 (equality-gated set).
 * Golden vectors: packages/contracts/golden/parts/nav.hitTest.jsonl (lean-parts), see logic.test.ts.
 */
export interface Rect {
  left: number;
  top: number;
  width: number;
  height: number;
}

/** Probe point: horizontal centre of the nav, vertical centre of its first 64 px. */
export function hitPoint(rect: Rect): { x: number; y: number } {
  return { x: rect.left + rect.width / 2, y: rect.top + Math.min(rect.height, 64) / 2 };
}

/** `closest()` selectors, restated from the original. Excluded wins over included; shrinking is checked last. */
export const EXCLUDE_SELECTOR = '.commission-card, .start-selling-future-card, .hero';
export const INCLUDE_SELECTOR = '.pain, .start-selling-platform-card, .start-selling-platform';
export const SHRINKING_SELECTOR = '.commission.shrinking';

/** j(): is the hit element over a dark section. The flags are the `el.closest(...)` results for the three selectors. */
export function classifyHit(f: { hasElement: boolean; inExclude: boolean; inInclude: boolean; inShrinking: boolean }): boolean {
  if (!f.hasElement || f.inExclude) return false;
  return f.inInclude || f.inShrinking;
}

/**
 * hit-skip: index of the first element of the `elementsFromPoint` stack that lies outside the nav subtree
 * (what `elementFromPoint` returns while the nav has `pointer-events: none`), or -1.
 */
export function firstOutside(insideNav: readonly boolean[]): number {
  return insideNav.findIndex((b) => !b);
}

/** Write on change only. */
export function changed(prev: boolean, next: boolean): boolean {
  return prev !== next;
}

/** Position on the scroll engine: after the profile-sticky check, before the hero progress read (13001-13003). */
export const NAV_HIT_ORDER = 100;
