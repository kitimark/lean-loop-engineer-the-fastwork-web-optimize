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

/** `closest()` selectors on our hooks (the original's `.commission-card`, `.start-selling-future-card` = people-card, `.hero`; `.pain`; the platform card sits inside the platform section; `.commission.shrinking`, the class is a CSS-Module name so it matches by substring). Excluded wins over included; shrinking is checked last. */
export const EXCLUDE_SELECTOR = '[data-fw="commission-card"], [data-fw="people-card"], [data-fw="hero"]';
export const INCLUDE_SELECTOR = '[data-fw="pain"], [data-fw="platform"]';
export const SHRINKING_SELECTOR = '[data-fw="commission"][class*="shrinking"]';

/** j(): is the hit element over a dark section. The flags are the `el.closest(...)` results for the three selectors. */
export function classifyHit(f: { hasElement: boolean; inExclude: boolean; inInclude: boolean; inShrinking: boolean }): boolean {
  if (!f.hasElement || f.inExclude) return false;
  return f.inInclude || f.inShrinking;
}

/** One box at the probe point, top-most first (`elementsFromPoint` order, nav at its normal `pointer-events`). */
export interface Hit {
  insideNav: boolean;
  /** the box sets `pointer-events` itself, so it stays hit-testable while the nav root is forced to `none`. */
  reEnabled: boolean;
}

/** JS `findIndex` with -1 for none. */
export function findIdx<T>(p: (x: T) => boolean, xs: readonly T[]): number {
  return xs.findIndex(p);
}

/**
 * Index `elementFromPoint` returns in the original (F, 12959-12961): with the nav root at `pointer-events: none`, the
 * first box that is outside the nav or re-enabled inside it (nav actions, expanded morph panel, active morph pill,
 * earn button; CSS 11442, 10557, 10519, 11498).
 */
export function faithfulHit(stack: readonly Hit[]): number {
  return findIdx((h) => !h.insideNav || h.reEnabled, stack);
}

/**
 * Naive skip: index of the first element outside the nav subtree. NOT faithful: it passes over the re-enabled boxes
 * (Lean `firstOutside_ne_faithful`). Kept only to pin that difference; no variant uses it.
 */
export function firstOutside(insideNav: readonly boolean[]): number {
  return findIdx((b) => !b, insideNav);
}

/**
 * elements-skip (v1 `nav-hit-test`): first box outside the nav or allow-listed inside it. Equals `faithfulHit` when the
 * allow-list agrees with `reEnabled` on the nav's boxes (Lean `allowHit_eq_faithful`).
 */
export function allowHit(allow: (h: Hit) => boolean, stack: readonly Hit[]): number {
  return findIdx((h) => !h.insideNav || allow(h), stack);
}

/** Above this morph the nav is dark whatever the hit test says (N2:13228: `is-on-dark = g || morph > 0.2`). */
export const MORPH_DARK_ABOVE = 0.2;

/** `is-on-dark`: the hit answer or morph strictly past 0.2. */
export function isOnDark(hit: boolean, morph: number): boolean {
  return hit || morph > MORPH_DARK_ABOVE;
}

/** hit-skip (v1 `hit-skip`): skip the hit test while the answer is invisible, i.e. while `morph > 0.2` (Lean `hitSkip_morph`). */
export function skipHitTest(morph: number): boolean {
  return morph > MORPH_DARK_ABOVE;
}

/** Selectors of the nav boxes that set `pointer-events` themselves (original CSS 11442, 10557, 10519, 11498), on our hooks. */
export const ALLOW_SELECTOR = [
  '[data-fw="nav"] [class*="actions"]',
  '[data-fw="morph-panel"][data-expanded]',
  '[data-fw="nav"]:not(.is-hero-pill, .is-morphing) [data-fw="nav-earn"]',
].join(', ');

/** The original's `.start-selling-morph-pill` entry has no counterpart: our pill is the nav itself, which the probe already steps over. */

/** Write on change only. */
export function changed(prev: boolean, next: boolean): boolean {
  return prev !== next;
}

/** Position on the scroll engine: after the profile-sticky check, before the hero progress read (13001-13003). */
export const NAV_HIT_ORDER = 100;
