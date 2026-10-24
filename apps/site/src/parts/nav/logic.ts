/**
 * Pure logic of the nav (no DOM): the class set of the pill, the hero-track progress, the profile-sticky test and the
 * chrome-ready rule. Restated from the original (nodes/2.DyWL8TcE.js): constants 12683-12684, state 12897-12906,
 * sticky test 12921-12935, ready rule 12996-13005, past-hero rule 13008-13018, classes and attributes 13224-13245.
 * Spec and proofs: lean/Fw/Parts/Nav.lean. Golden vectors: packages/contracts/golden/parts/nav.jsonl (logic.test.ts).
 * The geometry (width, height, top, radius ... as functions of `--morph`) is CSS (nav.module.css), specified in Lean.
 */

/** The nav counts as morphing above this morph value (N2:12899). */
export const MORPHING_CUT = 0.001;
/** Expanded above this (N2:12684). */
export const EXPANDED_CUT = 0.92;
/** Forced dark look above this; the earn button has collapsed by it (N2:13228). */
export const DARK_CUT = 0.2;
/** Share of the hero track after which the hero pill ends (N2:13016). */
export const PAST_CUT = 0.72;
/** Earn button leaves the tab order above this (N2:13244). */
export const EARN_TAB_CUT = 0.4;
/** Earn button is aria-hidden above this (N2:12903). */
export const EARN_ARIA_CUT = 0.55;
/** Chrome fades in after this many ms unless a query allows it earlier (N2:13003). */
export const READY_DELAY_MS = 1140;

/** Progress through the hero track (N2:13013-13015). */
export function progress({ top, height, vh }: { top: number; height: number; vh: number }): number {
  const r = Math.max(1, height - vh);
  return Math.min(r, Math.max(0, -top)) / r;
}

/** Past the hero (N2:13008-13018): no track, or reduced motion, or 72 % of the track scrolled. */
export function pastHero({ present, reduced, top, height, vh }: { present: boolean; reduced: boolean; top: number; height: number; vh: number }): boolean {
  return !present || reduced || progress({ top, height, vh }) >= PAST_CUT;
}

export interface Sticky {
  present: boolean;
  isSticky: boolean;
  hasSection: boolean;
  /** Parsed CSS `top`; null when not a finite number. */
  top: number | null;
  itemTop: number;
  itemBottom: number;
  sectionBottom: number;
}

/** The profile sticky item is stuck (N2:12921-12935). */
export function stuck(s: Sticky): boolean {
  return s.present && s.isSticky && s.hasSection && s.top !== null && Number.isFinite(s.top) && s.itemTop <= s.top + 1 && s.sectionBottom > s.itemBottom + 1;
}

export interface View {
  heroPill: boolean;
  ready: boolean;
  morphing: boolean;
  expanded: boolean;
  onDark: boolean;
  localeOpen: boolean;
  scrollHidden: boolean;
}

/** The class set of the header (N2:12897-12906, 13224-13231). */
export function view({ past, ready, localeOpen, hit, stuck: st, m }: { past: boolean; ready: boolean; localeOpen: boolean; hit: boolean; stuck: boolean; m: number }): View {
  const morphing = m > MORPHING_CUT;
  return { heroPill: !past && !morphing, ready, morphing, expanded: m > EXPANDED_CUT, onDark: hit || m > DARK_CUT, localeOpen, scrollHidden: st && !morphing };
}

/** Earn button attributes (N2:13243-13245). */
export function earn({ heroPill, m }: { heroPill: boolean; m: number }): { tabOff: boolean; ariaHidden: boolean } {
  return { tabOff: m > EARN_TAB_CUT || heroPill, ariaHidden: heroPill || m > EARN_ARIA_CUT };
}

/** Chrome ready at mount (N2:13005). */
export function readyInit({ reduced, phone }: { reduced: boolean; phone: boolean }): boolean {
  return reduced || phone;
}

/** Chrome ready after a query change or splash check (N2:12998-13004); never goes back. */
export function readyChange({ ready, reduced, phone, splash }: { ready: boolean; reduced: boolean; phone: boolean; splash: boolean }): boolean {
  return ready || reduced || phone || splash;
}

/** Ready once the timer has run (N2:13003). */
export function readyAt({ t }: { t: number }): boolean {
  return t >= READY_DELAY_MS;
}

/** The nav variant that keeps the earn button's transitions off while morphing (lean/Fw/Parts/NavEarnOpt.lean). */
export const EARN_STILL_VARIANT = 'earn-no-transition';
/** The class that turns the earn button's transitions off. */
export const EARN_STILL_CLASS = 'is-earn-still';

/** The earn button's CSS transitions run (NavEarnOpt.transitionsOn): always in the faithful, outside the morph in the flag. */
export function earnTransitionOn({ flag, morphing }: { flag: boolean; morphing: boolean }): boolean {
  return !(flag && morphing);
}

export const EARN_LOGICAL_VARIANT = 'earn-logical';
export const EARN_LOGICAL_CLASS = 'is-earn-logical';

export const CLASS_OF: Readonly<Record<Exclude<keyof View, 'onDark'>, string[]>> = {
  heroPill: ['is-hero-pill'],
  ready: ['is-hero-chrome-ready'],
  morphing: ['is-morphing'],
  expanded: ['is-expanded'],
  localeOpen: ['is-locale-open'],
  scrollHidden: ['is-scroll-hidden', 'is-profile-sticky-hidden'],
};
