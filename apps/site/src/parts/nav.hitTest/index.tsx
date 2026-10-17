import { useEffect } from 'react';
import { registerScroll } from '../../engine/scroll';
import { changed, isOnDark, NAV_HIT_ORDER } from './logic';
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
 */
export function NavHitTest({ variant, navSelector = '[data-fw="nav"]' }: { variant: string; impl?: 'mui' | 'plain'; navSelector?: string }) {
  useEffect(() => {
    const nav = document.querySelector<HTMLElement>(navSelector);
    if (!nav) return;
    const v = parseVariant(variant);
    let hit = false; // last known hit answer (stale while skipped)
    let current = nav.classList.contains(ON_DARK_CLASS);
    return registerScroll('nav.hitTest', NAV_HIT_ORDER, () => {
      const morph = readMorph(nav);
      const r = navFrame(v, nav, morph);
      if (r.hit !== null) hit = r.hit;
      const next = isOnDark(hit, morph);
      if (!changed(current, next)) return;
      return () => {
        current = next;
        nav.classList.toggle(ON_DARK_CLASS, next);
      };
    });
  }, [variant, navSelector]);
  return null;
}
