import { useLayoutEffect, useRef, type ReactNode } from 'react';
import { getClock } from '../../engine/clock';
import { getScrollEngine } from '../../engine/scroll';
import { COPY } from '../people/data';
import { ORDER, watchActive } from '../people/shared';
import css from './card.module.css';
import { createCardDriver, type CardEnv } from './driver';
import { matchList } from './media';
import { darkScrollSupported, layerOwnsFlip } from '../pain/darkScroll';

export interface PeopleCardProps {
  variant: string;
  /** the "o" of "people" (part people.o) */
  o: ReactNode;
  /** the profile showcase (part people.deck) */
  deck: ReactNode;
  /** the community pill with the avatar carousel (part people.carousel) */
  pill: ReactNode;
}

const TRACK = '[data-fw="hero-exit"], .hero-track';
const PAIN = '[data-fw="pain"], .pain';

/**
 * people.card (`faithful`): the People section's white card, its header and community pill. The driver writes
 * `--future-shrink` on the section per scroll frame and toggles the reveal and shrinking classes and the Pain colour on the
 * DOM (no React state in the frame). Title, copy and button are the original's English strings.
 */
export function PeopleCard({ variant, o, deck, pill }: PeopleCardProps) {
  const sectionRef = useRef<HTMLElement>(null);
  const cardRef = useRef<HTMLDivElement>(null);
  const headerRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const section = sectionRef.current;
    const card = cardRef.current;
    const header = headerRef.current;
    if (!section || !card || !header) return;
    const reduce = matchList('mq.rm-reduce');
    const narrow = matchList('mq.w-le-860');
    const c860 = variant === 'mq' ? matchList('mq.c860') : null;
    const pain = () => document.querySelector<HTMLElement>(PAIN);
    const flips = () => {
      const p = pain();
      return p !== null && !layerOwnsFlip(p.getAttribute('data-fw-variant'), darkScrollSupported()) ? p : null;
    };
    const env: CardEnv = {
      reduced: () => reduce?.matches ?? false,
      narrow: () => narrow?.matches ?? false,
      vh: () => window.innerHeight,
      track: () => {
        const t = document.querySelector(TRACK);
        if (!t) return null;
        const r = t.getBoundingClientRect();
        return { top: r.top, height: r.height };
      },
      cardBottom: () => card.getBoundingClientRect().bottom,
      headerTop: () => flips()?.isConnected ? header.getBoundingClientRect().top : null,
      painPresent: () => flips() !== null,
      write: {
        revealed: (on) => section.classList.toggle(css.isVisible!, on),
        shrink: (v) => section.style.setProperty('--future-shrink', String(v)),
        shrinking: (on) => section.classList.toggle(css.isShrinking!, on),
        painDark: (on) => {
          const p = flips();
          if (!p) return;
          p.classList.toggle('is-pain-dark', on);
          p.setAttribute('data-fw-pain-dark', String(on));
        },
      },
    };
    const driver = createCardDriver(env, getClock(), { gate: () => c860?.matches === true });
    let active = false;
    const off = getScrollEngine().register('people.card', ORDER.card, () => {
      if (active) driver.onScroll();
    });
    const stopActive = watchActive(section, (a) => {
      active = a;
      section.setAttribute('data-fw-scene', a ? 'active' : 'paused'); // the original's data-start-selling-scene (dE manageAnimations)
      if (a) driver.onScroll();
    });
    const onMedia = () => driver.onMediaChange();
    reduce?.addEventListener('change', onMedia);
    narrow?.addEventListener('change', onMedia);
    c860?.addEventListener('change', onMedia);
    driver.runNow();
    return () => {
      reduce?.removeEventListener('change', onMedia);
      narrow?.removeEventListener('change', onMedia);
      c860?.removeEventListener('change', onMedia);
      stopActive();
      section.removeAttribute('data-fw-scene');
      off();
      driver.dispose();
    };
  }, [variant]);

  const word = COPY.titleWord;
  const at = word.indexOf('o');
  const before = at === -1 ? word : word.slice(0, at);
  const after = at === -1 ? '' : word.slice(at + 1);
  return (
    <section ref={sectionRef} id="people" className={css.future} aria-labelledby="future-heading" data-fw="people" data-fw-variant={variant}>
      <div ref={cardRef} className={css.card} data-fw="people-card">
        <div ref={headerRef} className={css.header}>
          <div className={css.headerCopy}>
            <h2 id="future-heading" className={variant === 'title-wrap' ? `${css.title} ${css.titleWrap}` : css.title}>
              <span className={css.titleLead}>{COPY.titleLead}</span>{' '}
              <span className={css.titleWords}>
                {before}
                {o}
                {after}
              </span>
            </h2>
            <p className={css.copy}>
              <span className={css.copyLead}>{COPY.bodyLead}</span> <br aria-hidden="true" /> {COPY.bodyRest}
            </p>
          </div>
        </div>
        <div className={css.showcase}>{deck}</div>
        {pill}
      </div>
    </section>
  );
}
