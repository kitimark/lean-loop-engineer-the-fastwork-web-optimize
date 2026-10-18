import { HeroAccent } from '../hero.accent';
import { HeroCountdown } from '../hero.countdown';
import { HeroCue } from '../hero.cue';
import { HeroDeck } from '../hero.deck';
import { HeroExit } from '../hero.exit';
import { HeroOrbit } from '../hero.orbit';
import css from './hero.module.css';

export interface HeroProps {
  /** every registered part id -> chosen variant */
  variants: Record<string, string>;
}

const v = (variants: Record<string, string>, id: string) => variants[id] ?? 'faithful';

function BellIcon() {
  return (
    <svg className={css.icon} viewBox="0 0 24 24" fill="none" strokeWidth="1.5" aria-hidden="true" focusable="false">
      <path
        d="M18.7491 9.70957V9.00496C18.7491 5.13623 15.7274 2 12 2C8.27256 2 5.25087 5.13623 5.25087 9.00496V9.70957C5.25087 10.5552 5.00972 11.3818 4.5578 12.0854L3.45036 13.8095C2.43882 15.3843 3.21105 17.5249 4.97036 18.0229C9.57274 19.3257 14.4273 19.3257 19.0296 18.0229C20.789 17.5249 21.5612 15.3843 20.5496 13.8095L19.4422 12.0854C18.9903 11.3818 18.7491 10.5552 18.7491 9.70957Z"
        stroke="currentColor"
      />
      <path d="M7.5 19C8.15503 20.7478 9.92246 22 12 22C14.0775 22 15.845 20.7478 16.5 19" stroke="currentColor" strokeLinecap="round" />
    </svg>
  );
}

function CalendarIcon() {
  return (
    <svg className={css.icon} viewBox="0 0 24 24" fill="none" strokeWidth="1.5" aria-hidden="true" focusable="false">
      <path
        d="M2 12C2 8.22876 2 6.34315 3.17157 5.17157C4.34315 4 6.22876 4 10 4H14C17.7712 4 19.6569 4 20.8284 5.17157C22 6.34315 22 8.22876 22 12V14C22 17.7712 22 19.6569 20.8284 20.8284C19.6569 22 17.7712 22 14 22H10C6.22876 22 4.34315 22 3.17157 20.8284C2 19.6569 2 17.7712 2 14V12Z"
        stroke="currentColor"
      />
      <path d="M7 4V2.5M17 4V2.5M2.5 9H21.5" stroke="currentColor" strokeLinecap="round" />
    </svg>
  );
}

/**
 * hero: the first section of the home page. Composes the sticky stage (hero.exit) with the ring (hero.orbit), the phone deck
 * (hero.deck), the copy (headline with the hand-drawn word, countdown, call to action) and the scroll cue (hero.cue).
 * The copy itself is static markup and CSS; the splash state arrives as the stage's `data-splash`. Placeholder text.
 */
export function Hero({ variants }: HeroProps) {
  return (
    <HeroExit variant={v(variants, 'hero.exit')}>
      <HeroOrbit variant={v(variants, 'hero.orbit')} />
      <HeroDeck variant={v(variants, 'hero.deck')} />
      <header className={css.copy} data-fw="hero" data-fw-variant={v(variants, 'hero')}>
        <div className={css.copyMain}>
          <h1 id="start-selling-heading" className={css.title}>
            <span className={css.line}>Placeholder headline</span>{' '}
            <span className={css.words}>
              <span>word</span> <HeroAccent variant={v(variants, 'hero.accent')} /> <span>word</span>
            </span>
          </h1>
          <p>Placeholder supporting text.</p>
        </div>
        <HeroCountdown variant={v(variants, 'hero.countdown')} />
        <div className={css.ctaStack}>
          <div className={css.cta}>
            <button type="button">
              <BellIcon />
              Join list
            </button>
          </div>{' '}
          <a className={css.rsvp} href="#rsvp">
            <CalendarIcon />
            RSVP
          </a>{' '}
          <p className={`${css.note} ${css.invite}`}>* Placeholder note.</p>
        </div>
      </header>
      <HeroCue variant={v(variants, 'hero.cue')} />
    </HeroExit>
  );
}
