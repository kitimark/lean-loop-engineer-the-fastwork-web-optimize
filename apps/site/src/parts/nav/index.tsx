import { useCallback, useEffect, useRef, type MutableRefObject, type ReactNode } from 'react';
import { getClock } from '../../engine/clock';
import { registerScroll } from '../../engine/scroll';
import type { PanelWriter } from '../morph.panel';
import { LangMenu, type LocaleCode } from '../nav.langMenu';
import { createNavDriver, type NavEnv } from './driver';
import { CLASS_OF, type Sticky } from './logic';
import { NavLogo } from './logo';
import { matchList } from './media';
import css from './nav.module.css';

/** Where the nav's own scroll callback sits on the engine: before nav.hitTest (100), as the original reads the sticky item first. */
export const NAV_ORDER = 99;

export interface NavProps {
  variant: string;
  impl?: 'mui' | 'plain';
  /** the hero scroll track whose progress ends the hero pill (the original's `.hero-track`) */
  heroSelector?: string;
  /** the hero element that carries `is-ring-splash-done` (the original's `.hero`) */
  splashSelector?: string;
  /** the profile sticky item and its section (the original's `.start-selling-profile-sticky`) */
  stickySelector?: string;
  sectionSelector?: string;
  /** the language the page is in */
  locale?: LocaleCode;
  onSelectLocale?: (code: LocaleCode) => void;
  /** the "Join waitlist" button (opens the signup overlay) */
  onJoin?: () => void;
  /** the morph panel (mounted lazily by the page); the nav hosts it and gives it `--morph` by inheritance */
  children?: ReactNode;
  /** the panel's attribute writer, called with the new value as the observer sees each `data-fw-morph` write (no React state) */
  panelWriterRef?: MutableRefObject<PanelWriter | null>;
}

function measureSticky(stickySelector: string, sectionSelector: string): Sticky {
  const none: Sticky = { present: false, isSticky: false, hasSection: false, top: null, itemTop: 0, itemBottom: 0, sectionBottom: 0 };
  const item = document.querySelector<HTMLElement>(stickySelector);
  if (!item) return none;
  const cs = window.getComputedStyle(item);
  if (cs.position !== 'sticky') return { ...none, present: true };
  const section = item.closest<HTMLElement>(sectionSelector);
  if (!section) return { ...none, present: true, isSticky: true };
  const top = Number.parseFloat(cs.top);
  const i = item.getBoundingClientRect();
  const s = section.getBoundingClientRect();
  return { present: true, isSticky: true, hasSection: true, top: Number.isFinite(top) ? top : null, itemTop: i.top, itemBottom: i.bottom, sectionBottom: s.bottom };
}

/**
 * nav (`faithful`): the floating pill of the original's top nav: logo, language switch, the "Join waitlist" button that
 * collapses as the morph opens. Static markup and CSS (nav.module.css, restated); the state classes (`is-hero-pill`,
 * `is-hero-chrome-ready`, `is-morphing`, `is-expanded`, `is-locale-open`, `is-scroll-hidden`) are toggled by the driver
 * on change only, from the scroll engine's callback and from the value morph.tween publishes (`data-fw-morph`). `is-on-dark`
 * belongs to nav.hitTest. No React state: nothing here re-renders. The geometry as functions of `--morph` is CSS and is
 * specified in lean/Fw/Parts/Nav.lean; the decisions are logic.ts (golden vectors).
 *
 * Deltas (named): the wordmark is the snapshot's artwork (logo.paths.ts); the morph panel is the `children`, hosted
 * here as in the original (title, columns, CTAs and footer are morph.panel's); no `.hero-track`/profile
 * elements exist in the page yet beyond the hero.exit track, which stands in for the former.
 */
export function Nav({
  heroSelector = '[data-fw="hero-exit"]',
  splashSelector = '.hero.is-ring-splash-done',
  stickySelector = '.start-selling-profile-sticky',
  sectionSelector = '#profile-showcase, .start-selling-profile',
  locale = 'en',
  onSelectLocale,
  onJoin,
  children,
  panelWriterRef,
}: NavProps) {
  const header = useRef<HTMLElement>(null);
  const driver = useRef<ReturnType<typeof createNavDriver> | null>(null);

  useEffect(() => {
    const nav = header.current;
    if (!nav) return;
    const reduce = matchList('mq.rm-reduce');
    const narrow = matchList('mq.w-le-600');
    const earn = nav.querySelector<HTMLElement>('[data-fw="nav-earn"]');
    const env: NavEnv = {
      reduced: () => reduce.matches,
      narrow: () => narrow.matches,
      hero: () => {
        const el = document.querySelector<HTMLElement>(heroSelector);
        if (!el) return null;
        const r = el.getBoundingClientRect();
        return { top: r.top, height: r.height };
      },
      innerHeight: () => window.innerHeight,
      sticky: () => measureSticky(stickySelector, sectionSelector),
      splashDone: () => document.querySelector(splashSelector) !== null,
      morph: () => {
        const m = Number.parseFloat(nav.dataset.fwMorph ?? '');
        return Number.isFinite(m) ? m : 0;
      },
      apply: (v, e) => {
        for (const key of Object.keys(CLASS_OF) as (keyof typeof CLASS_OF)[]) for (const c of CLASS_OF[key]) nav.classList.toggle(c, v[key]);
        if (earn) {
          earn.tabIndex = e.tabOff ? -1 : 0;
          if (e.ariaHidden) earn.setAttribute('aria-hidden', 'true');
          else earn.removeAttribute('aria-hidden');
        }
      },
      after: (ms, cb) => {
        const off = getClock().interval(ms, () => {
          off();
          cb();
        });
        return off;
      },
    };
    const d = createNavDriver(env);
    driver.current = d;
    d.mount();
    const off = registerScroll('nav', NAV_ORDER, () => d.measure());
    const onQuery = () => d.queryChanged();
    reduce.addEventListener('change', onQuery);
    narrow.addEventListener('change', onQuery);
    // The tween writes `data-fw-morph` once per frame; the observer reacts in the same frame (microtask), only on change.
    const mo = new MutationObserver(() => {
      d.morphChanged();
      panelWriterRef?.current?.apply(env.morph());
    });
    mo.observe(nav, { attributes: true, attributeFilter: ['data-fw-morph'] });
    return () => {
      off();
      mo.disconnect();
      reduce.removeEventListener('change', onQuery);
      narrow.removeEventListener('change', onQuery);
      d.dispose();
      driver.current = null;
    };
  }, [heroSelector, splashSelector, stickySelector, sectionSelector, panelWriterRef]);

  const onOpenChange = useCallback((open: boolean) => driver.current?.setLocaleOpen(open), []);

  return (
    <header ref={header} className={`${css.nav} is-hero-pill`} aria-label="Primary navigation" data-fw="nav">
      <div className={css.bar}>
        <a className={css.logo} href="/" aria-label="Fastwork home">
          <NavLogo />
        </a>
        <div className={css.actions}>
          <LangMenu variant="faithful" locale={locale} onSelect={onSelectLocale} onOpenChange={onOpenChange} />
          <button className={`${css.btn} ${css.earn}`} type="button" tabIndex={-1} aria-hidden="true" data-fw="nav-earn" onClick={onJoin}>
            Join waitlist
          </button>
        </div>
      </div>
      {children}
    </header>
  );
}
