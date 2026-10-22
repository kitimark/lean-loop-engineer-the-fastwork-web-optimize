import { useEffect } from 'react';
import { registerScroll } from '../../engine/scroll';
import { changed, isOnDark, NAV_HIT_ORDER, NAV_SELECTOR } from './logic';
import { BOX_ATTR } from '../nav/box';
import { navFrame, type NavVariant } from './probe';

export const ON_DARK_CLASS = 'is-on-dark';

function parseVariant(v: string): NavVariant {
  return v === 'hit-skip' || v === 'elements-skip' ? v : 'faithful';
}

function readMorph(nav: HTMLElement): number {
  const m = Number.parseFloat(nav.dataset.fwMorph ?? '');
  return Number.isFinite(m) ? m : 0;
}

export function NavHitTest({ variant, navSelector = NAV_SELECTOR }: { variant: string; impl?: 'mui' | 'plain'; navSelector?: string }) {
  useEffect(() => {
    const nav = document.querySelector<HTMLElement>(navSelector);
    if (!nav) return;
    const v = parseVariant(variant);
    const box = nav.getAttribute(BOX_ATTR) === 'union';
    let hit = false;
    let current = nav.classList.contains(ON_DARK_CLASS);
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
