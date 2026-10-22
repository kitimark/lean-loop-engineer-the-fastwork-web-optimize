import { GenSvg, art } from '../../GenSvg';
import css from './cue.module.css';

export interface HeroCueProps {
  variant: string;
}

function scrollNext() {
  const next = document.querySelector<HTMLElement>('[data-fw="people"]');
  if (next) window.scrollTo({ top: window.scrollY + next.getBoundingClientRect().top, behavior: 'smooth' });
}

export function HeroCue({ variant }: HeroCueProps) {
  return (
    <button type="button" className={css.cue} data-fw="hero-cue" data-fw-layer="hero.cue_cue" data-fw-variant={variant} onClick={scrollNext}>
      <span className={css.float}>
        <span className={css.label}>Scroll down</span>{' '}
        <GenSvg art={art('hero.cue')} />
      </span>
    </button>
  );
}
