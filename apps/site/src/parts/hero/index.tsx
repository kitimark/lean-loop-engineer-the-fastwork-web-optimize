import { useEffect, useRef } from 'react';
import { GenSvg, art } from '../../GenSvg';
import { HeroAccent } from '../hero.accent';
import { HeroCountdown } from '../hero.countdown';
import { HeroCue } from '../hero.cue';
import { HeroDeck } from '../hero.deck';
import { HeroExit } from '../hero.exit';
import { HeroOrbit } from '../hero.orbit';
import { watchActive } from '../people/shared';
import css from './hero.module.css';
import { SCENE_PAUSE, bindHeroScene } from './scene';

export interface HeroProps {
  /** every registered part id -> chosen variant */
  variants: Record<string, string>;
}

const v = (variants: Record<string, string>, id: string) => variants[id] ?? 'faithful';

function BellIcon() {
  return <GenSvg art={art('icon.bell')} className={css.icon} />;
}

function CalendarIcon() {
  return <GenSvg art={art('icon.calendar')} className={css.icon} />;
}

/**
 * hero: the first section of the home page. Composes the sticky stage (hero.exit) with the ring (hero.orbit), the phone deck
 * (hero.deck), the copy (headline with the hand-drawn word, countdown, call to action) and the scroll cue (hero.cue).
 * The copy itself is static markup and CSS; the splash state arrives as the stage's `data-splash`.
 */
export function Hero({ variants }: HeroProps) {
  const variant = v(variants, 'hero');
  const copy = useRef<HTMLElement>(null);
  useEffect(() => {
    const track = copy.current?.closest('[data-fw="hero-exit"]');
    if (variant !== SCENE_PAUSE || !track) return undefined;
    return bindHeroScene(track, watchActive);
  }, [variant]);

  return (
    <HeroExit variant={v(variants, 'hero.exit')}>
      <HeroOrbit variant={v(variants, 'hero.orbit')} />
      <HeroDeck variant={v(variants, 'hero.deck')} />
      <header ref={copy} className={css.copy} data-fw="hero" data-fw-variant={variant}>
        <div className={css.copyMain}>
          <h1 id="start-selling-heading" className={css.title}>
            <span className={css.line}>Show the world</span>{' '}
            <span className={css.words}>
              <span>what</span> <HeroAccent variant={v(variants, 'hero.accent')} /> <span>can do</span>
            </span>
          </h1>
          <p>In the age of AI, your portfolio proves why clients need you.</p>
        </div>
        <HeroCountdown variant={v(variants, 'hero.countdown')} />
        <div className={css.ctaStack}>
          <div className={css.cta}>
            <button type="button">
              <BellIcon />
              Join waitlist
            </button>
          </div>{' '}
          <a className={css.rsvp} href="https://f.fastwork.co/demoday" target="_blank" rel="noopener">
            <CalendarIcon />
            RSVP Demo day
          </a>{' '}
          <p className={`${css.note} ${css.invite}`}>* Available October 1st, by invitation only.</p>
        </div>
      </header>
      <HeroCue variant={v(variants, 'hero.cue')} />
    </HeroExit>
  );
}
