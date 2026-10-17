import { useEffect } from 'react';
import { registerScroll } from '../../engine/scroll';
import { changed, NAV_HIT_ORDER } from './logic';
import { probeFaithful, probeSkip } from './probe';

/** Class the nav carries over a dark section (same name as the original's). */
export const ON_DARK_CLASS = 'is-on-dark';

/**
 * Per-scroll-frame hit test: is the nav over a dark section. No DOM output; it toggles `is-on-dark` on the nav element
 * (found by `navSelector`) on change only, never through React state. `impl: plain` shares the code (nothing here is
 * MUI), so the twin must measure equal.
 */
export function NavHitTest({ variant, navSelector = '[data-fw="nav"]' }: { variant: string; impl?: 'mui' | 'plain'; navSelector?: string }) {
  useEffect(() => {
    const nav = document.querySelector<HTMLElement>(navSelector);
    if (!nav) return;
    const probe = variant === 'hit-skip' ? probeSkip : probeFaithful;
    let current = nav.classList.contains(ON_DARK_CLASS);
    return registerScroll('nav.hitTest', NAV_HIT_ORDER, () => {
      const next = probe(nav); // read phase (faithful also writes pointer-events inside, as the original)
      if (!changed(current, next)) return;
      return () => {
        current = next;
        nav.classList.toggle(ON_DARK_CLASS, next);
      };
    });
  }, [variant, navSelector]);
  return null;
}
