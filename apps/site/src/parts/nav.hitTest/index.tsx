import { useEffect } from 'react';
import { registerScroll } from '../../engine/scroll';
import { changed, isOnDark, NAV_HIT_ORDER, NAV_SELECTOR } from './logic';
import { BOX_ATTR } from '../nav/box';
import { navFrame, type NavVariant } from './probe';

/** Class the nav carries over a dark section (same name as the original's). */
export const ON_DARK_CLASS = 'is-on-dark';

function parseVariant(v: string): NavVariant {
  return v === 'hit-skip' || v === 'elements-skip' ? v : 'faithful';
}

/** Morph progress of the nav, 0..1, from `data-fw-morph` (the nav part owns it; absent means 0). */
function readMorph(nav: HTMLElement): number {
  const m = Number.parseFloat(nav.dataset.fwMorph ?? '');
  return Number.isFinite(m) ? m : 0;
}

/**
 * Per-scroll-frame hit test: is the nav over a dark section. No DOM output; it toggles `is-on-dark` on the nav element
 * (found by `navSelector`) on change only, never through React state. The class is `isOnDark(hit, morph)` as the
 * original's `g || morph > 0.2`. Variants: faithful (original sequence), hit-skip (skip the test while morph > 0.2,
 * keep the stale answer), elements-skip (elementsFromPoint with the allow-list, no style write). `impl: plain` shares the
 * code (nothing here is MUI), so the twin must measure equal.
 *
 * The callback runs its reads and writes inside itself, in the original's order (read, write, read, write, read), so
 * the faithful engine variant keeps the original's forced style passes; only the class toggle is returned as a writer.
 *
 * The class is also re-derived when the morph value changes. In the original `is-on-dark` is a Svelte class directive
 * over `g() || x() > .2`, so it follows the morph signal as well as the hit test (N2:13228); a push (wheel or touch at
 * the end of the page) moves the morph with no scroll frame, and a class written only in the scroll callback stayed
 * stale (divergence B of faithful-hero-baseline: at 390 the original is dark from morph 0.2 on, the port never was). The
 * re-derivation reuses the last hit answer and runs no hit test: the original's `g` is not re-probed on a morph change either.
 * The MutationObserver write runs in a microtask, outside the registerScroll read/write order above.
 */
export function NavHitTest({ variant, navSelector = NAV_SELECTOR }: { variant: string; impl?: 'mui' | 'plain'; navSelector?: string }) {
  useEffect(() => {
    const nav = document.querySelector<HTMLElement>(navSelector);
    if (!nav) return;
    const v = parseVariant(variant);
    const box = nav.getAttribute(BOX_ATTR) === 'union';
    let hit = false; // last known hit answer (stale while skipped)
    let current = nav.classList.contains(ON_DARK_CLASS);
    // The morph signal of the original's class directive: the nav part's tween writes `data-fw-morph` once per frame.
    const mo = new MutationObserver(() => {
      const next = isOnDark(hit, readMorph(nav));
      if (!changed(current, next)) return;
      current = next;
      nav.classList.toggle(ON_DARK_CLASS, next);
    });
    mo.observe(nav, { attributes: true, attributeFilter: ['data-fw-morph'] });
    const offScroll = registerScroll('nav.hitTest', NAV_HIT_ORDER, () => {
      const morph = readMorph(nav);
      const r = navFrame(v, nav, morph, undefined, box);
      if (r.hit !== null) hit = r.hit;
      const next = isOnDark(hit, morph);
      if (!changed(current, next)) return;
      return () => {
        current = next;
        nav.classList.toggle(ON_DARK_CLASS, next);
      };
    });
    return () => {
      offScroll();
      mo.disconnect();
    };
  }, [variant, navSelector]);
  return null;
}
