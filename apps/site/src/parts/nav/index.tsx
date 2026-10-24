import { useCallback, useEffect, useRef, type MutableRefObject, type ReactNode } from 'react';
import { getClock } from '../../engine/clock';
import { registerScroll } from '../../engine/scroll';
import type { PanelWriter } from '../morph.panel';
import { LangMenu, type LocaleCode } from '../nav.langMenu';
import { PROFILE_SECTION_SELECTOR, PROFILE_STICKY_SELECTOR } from '../nav.hitTest/probe';
import { installNavTransitionDebug } from '../../debug/nav-transition';
import { createNavDriver, type NavEnv } from './driver';
import { CLASS_OF, EARN_LOGICAL_CLASS, EARN_LOGICAL_VARIANT, EARN_STILL_CLASS, EARN_STILL_VARIANT, earnTransitionOn, type Sticky } from './logic';
import { boxVariant } from './box';
import { matchList } from './media';
import boxCss from './box.module.css';
import css from './nav.module.css';
import { art, GenSvg } from '../../GenSvg';

export const NAV_ORDER = 99;

export interface NavProps {
  variant: string;
  impl?: 'mui' | 'plain';
  heroSelector?: string;
  splashSelector?: string;
  stickySelector?: string;
  sectionSelector?: string;
  locale?: LocaleCode;
  onSelectLocale?: (code: LocaleCode) => void;
  onJoin?: () => void;
  children?: ReactNode;
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

export function Nav({
  variant,
  heroSelector = '[data-fw="hero-exit"]',
  splashSelector = '.hero.is-ring-splash-done',
  stickySelector = PROFILE_STICKY_SELECTOR,
  sectionSelector = PROFILE_SECTION_SELECTOR,
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
    const still = variant === EARN_STILL_VARIANT;
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
        nav.classList.toggle(EARN_STILL_CLASS, !earnTransitionOn({ flag: still, morphing: v.morphing }));
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
    const mo = new MutationObserver(() => {
      d.morphChanged();
      panelWriterRef?.current?.apply(env.morph());
    });
    mo.observe(nav, { attributes: true, attributeFilter: ['data-fw-morph'] });
    const offDebug = installNavTransitionDebug(location.search, nav);
    return () => {
      offDebug?.();
      off();
      mo.disconnect();
      reduce.removeEventListener('change', onQuery);
      narrow.removeEventListener('change', onQuery);
      d.dispose();
      driver.current = null;
    };
  }, [variant, heroSelector, splashSelector, stickySelector, sectionSelector, panelWriterRef]);

  const onOpenChange = useCallback((open: boolean) => driver.current?.setLocaleOpen(open), []);

  const box = boxVariant(variant);
  const boxClass = box === null ? '' : `${boxCss.boxClip}${box === 'clip-box' ? '' : ` ${boxCss.boxBar}`}${box === 'logo-3d' ? ` ${boxCss.box3d}` : ''} `;
  const boxAttr = box === null ? undefined : 'union';
  const roleAttr = (role: string) => (box === null ? undefined : role);

  return (
    <header ref={header} className={`${css.nav} ${boxClass}is-hero-pill${variant === EARN_LOGICAL_VARIANT ? ` ${EARN_LOGICAL_CLASS}` : ''}`} aria-label="Primary navigation" data-fw="nav" data-fw-layer="nav_bar" data-fw-box={boxAttr}>
      <div className={css.bar} data-fw-box-role={roleAttr('bar')}>
        <a className={css.logo} href="/" aria-label="Fastwork home" data-fw-box-role={roleAttr('logo')}>
          <GenSvg art={art('nav.wordmark')} />
        </a>
        <div className={css.actions} data-fw="nav-actions">
          <LangMenu variant="faithful" locale={locale} onSelect={onSelectLocale} onOpenChange={onOpenChange} />
          <button className={`${css.btn} ${css.earn}`} type="button" tabIndex={-1} aria-hidden="true" data-fw="nav-earn" data-fw-layer="nav_earn" onClick={onJoin}>
            Join waitlist
          </button>
        </div>
      </div>
      {children}
    </header>
  );
}
