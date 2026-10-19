import {
  allowHit,
  ALLOW_SELECTOR,
  classifyHit,
  EXCLUDE_SELECTOR,
  hitPoint,
  INCLUDE_SELECTOR,
  SHRINKING_SELECTOR,
  skipHitTest,
  type Hit,
} from './logic';
import { navHeroProgress } from '../hero.exit/logic';

/**
 * DOM adapters over the pure logic. The faithful sequence is the original's nav callback (2.DyWL8TcE.js:12955-13007):
 *   ee()  : querySelector, getComputedStyle position/top (style reads), two rects        [RS RS RL RL]
 *   F()   : nav rect, `pointer-events: none` write, elementFromPoint, restore write      [RL WS RL WS]
 *   track : hero-track rect                                                              [RL]
 * The style reads and the track rect are kept for cost parity in every variant (their results feed other nav
 * behaviour: `is-scroll-hidden`, `is-hero-pill`); they are returned, not applied here.
 */
export type NavVariant = 'faithful' | 'hit-skip' | 'elements-skip';

export interface ProbeEnv {
  doc: Pick<Document, 'elementFromPoint' | 'elementsFromPoint' | 'querySelector'>;
  win: Pick<Window, 'getComputedStyle' | 'innerHeight'>;
}

export function defaultEnv(): ProbeEnv {
  return { doc: document, win: window };
}

/** Selector of the hero track on our site (the original's `.hero-track`). */
export const HERO_TRACK_SELECTOR = '[data-fw="hero-exit"]';

/** The profile showcase's pinned bar (`.start-selling-profile-sticky`): the first child of the showcase section. */
export const PROFILE_STICKY_SELECTOR = '[data-fw="people-sticky"]';
export const PROFILE_SECTION_SELECTOR = '#profile-showcase, [data-fw="people-deck"]';

function classify(el: Element | null): boolean {
  return classifyHit({
    hasElement: el !== null,
    inExclude: !!el?.closest(EXCLUDE_SELECTOR),
    inInclude: !!el?.closest(INCLUDE_SELECTOR),
    inShrinking: !!el?.closest(SHRINKING_SELECTOR),
  });
}

/** ee() (12968-12980): is the profile showcase's sticky bar pinned. Style reads, then two rects. */
export function readProfileSticky(env: ProbeEnv): boolean {
  const e = env.doc.querySelector(PROFILE_STICKY_SELECTOR);
  if (!e) return false;
  const t = env.win.getComputedStyle(e);
  if (t.position !== 'sticky') return false;
  const n = e.closest(PROFILE_SECTION_SELECTOR);
  if (!n) return false;
  const top = Number.parseFloat(t.top);
  const i = e.getBoundingClientRect();
  const a = n.getBoundingClientRect();
  return Number.isFinite(top) && i.top <= top + 1 && a.bottom > i.bottom + 1;
}

/** faithful F(): rect read, write `pointer-events: none` on the nav, elementFromPoint (forces style + layout), restore. */
export function probeFaithful(nav: HTMLElement, env: ProbeEnv = defaultEnv()): boolean {
  const { x, y } = hitPoint(nav.getBoundingClientRect());
  const prev = nav.style.pointerEvents;
  nav.style.pointerEvents = 'none';
  const el = env.doc.elementFromPoint(x, y);
  nav.style.pointerEvents = prev;
  return classify(el);
}

/** Stack boxes as `Hit`s: inside the nav, and whether an ancestor-or-self box sets `pointer-events` itself. */
export function toHits(stack: readonly Element[], nav: Element): Hit[] {
  return stack.map((e) => ({ insideNav: nav.contains(e), reEnabled: !!e.closest(ALLOW_SELECTOR) }));
}

/** elements-skip: rect read, elementsFromPoint, first box outside the nav or allow-listed. No style write. */
export function probeElements(nav: HTMLElement, env: ProbeEnv = defaultEnv()): boolean {
  const { x, y } = hitPoint(nav.getBoundingClientRect());
  const stack = env.doc.elementsFromPoint(x, y);
  const i = allowHit((h) => h.reEnabled, toHits(stack, nav));
  return classify(i < 0 ? null : (stack[i] ?? null));
}

/** Hero track progress as the nav reads it (13000-13007); null when the track is absent. */
export function readHeroProgress(env: ProbeEnv): { progress: number; pillPassed: boolean } | null {
  const t = env.doc.querySelector(HERO_TRACK_SELECTOR);
  if (!t) return null;
  const r = t.getBoundingClientRect();
  return navHeroProgress(r.top, r.height, env.win.innerHeight);
}

export interface NavFrameResult {
  /** hit answer, or null when the test was skipped (the stale answer stays). */
  hit: boolean | null;
  profileSticky: boolean;
  hero: { progress: number; pillPassed: boolean } | null;
}

/** One nav callback in the original's access order; the variant picks the hit-test step. */
export function navFrame(variant: NavVariant, nav: HTMLElement, morph: number, env: ProbeEnv = defaultEnv()): NavFrameResult {
  const profileSticky = readProfileSticky(env);
  let hit: boolean | null;
  if (variant === 'hit-skip' && skipHitTest(morph)) hit = null;
  else if (variant === 'elements-skip') hit = probeElements(nav, env);
  else hit = probeFaithful(nav, env);
  return { hit, profileSticky, hero: readHeroProgress(env) };
}
