import { GenSvg, art } from '../../GenSvg';
import css from './cue.module.css';

export interface HeroCueProps {
  variant: string;
}

/** Smooth-scrolls to the next section (the original: the people card's top; N2:4130-4133). */
function scrollNext() {
  const next = document.querySelector<HTMLElement>('[data-fw="people"]');
  if (next) window.scrollTo({ top: window.scrollY + next.getBoundingClientRect().top, behavior: 'smooth' });
}

/**
 * hero.cue: the "scroll down" button at the foot of the hero. CSS only (entrance, float loop, blur and rise on exit via the
 * stage's variables); the one handler is the click. Lean spec: `HeroDeck` (cue section).
 */
export function HeroCue({ variant }: HeroCueProps) {
  return (
    <button type="button" className={css.cue} data-fw="hero-cue" data-fw-variant={variant} onClick={scrollNext}>
      <span className={css.float}>
        <span className={css.label}>Scroll down</span>{' '}
        <GenSvg art={art('hero.cue')} />
      </span>
    </button>
  );
}
