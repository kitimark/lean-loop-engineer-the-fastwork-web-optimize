import { useEffect, useRef } from 'react';
import { GenSvg, art } from '../../GenSvg';
import { VARIANT as PAUSE_VARIANT, watchLoopPause } from './pause';
import css from './cue.module.css';

export interface HeroCueProps {
  variant: string;
}

function scrollNext() {
  const next = document.querySelector<HTMLElement>('[data-fw="people"]');
  if (next) window.scrollTo({ top: window.scrollY + next.getBoundingClientRect().top, behavior: 'smooth' });
}

export function HeroCue({ variant }: HeroCueProps) {
  const floatRef = useRef<HTMLSpanElement>(null);
  // Variant `offscreen-pause` (Lean HeroCuePause): the float loop stops while the cue is off screen.
  useEffect(() => {
    const el = floatRef.current;
    if (variant !== PAUSE_VARIANT || !el) return;
    return watchLoopPause([el]);
  }, [variant]);
  return (
    <button type="button" className={css.cue} data-fw="hero-cue" data-fw-layer="hero.cue_cue" data-fw-variant={variant} onClick={scrollNext}>
      <span ref={floatRef} className={css.float}>
        <span className={css.label}>Scroll down</span>{' '}
        <GenSvg art={art('hero.cue')} />
      </span>
    </button>
  );
}
