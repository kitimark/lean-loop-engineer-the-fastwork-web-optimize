import ButtonBase from '@mui/material/ButtonBase';
import Typography from '@mui/material/Typography';
import { useEffect, useRef, type ReactNode } from 'react';
import { getClock } from '../../engine/clock';
import { getScrollEngine } from '../../engine/scroll';
import { createExitDriver, mountExit } from './driver';
import { matchList } from './media';
import css from './hero.module.css';

export interface HeroExitProps {
  variant: string;
  /** `mui` (default) uses MUI Typography/ButtonBase; `plain` bare elements. Same CSS Module and driver. */
  impl?: 'mui' | 'plain';
}

const CARDS = 4;

/** hero.exit: sticky hero in a 200vh track; `--exit-opacity` is written on the hero per scroll frame. Placeholder content. */
export function HeroExit({ variant, impl = 'mui' }: HeroExitProps) {
  const trackRef = useRef<HTMLElement>(null);
  const heroRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const track = trackRef.current;
    const hero = heroRef.current;
    if (!track || !hero) return;
    const reduce = matchList('mq.rm-reduce');
    const driver = createExitDriver({ track, hero, reduced: () => reduce?.matches ?? false });
    // faithful engine: own rAF per frame, run once on mount; batched engine: read in the callback, write in its writer
    return mountExit({ driver, engine: getScrollEngine(), clock: getClock(), readVh: () => window.innerHeight });
  }, []);

  const mui = impl === 'mui';
  return (
    <section ref={trackRef} className={css.track} data-fw="hero-exit" data-fw-variant={variant}>
      <div ref={heroRef} className={css.hero}>
        <div className={css.cards} aria-hidden="true">
          {Array.from({ length: CARDS }, (_, i) => (
            <div key={i} className={css.card} />
          ))}
        </div>
        <header className={css.copy}>
          <div className={css.copyMain}>
            {mui ? (
              <Typography variant="h1" className={css.title}>
                Placeholder headline
              </Typography>
            ) : (
              <h1 className={css.title}>Placeholder headline</h1>
            )}
            {mui ? (
              <Typography variant="body1" component="p" className={css.lead}>
                Placeholder supporting text.
              </Typography>
            ) : (
              <p className={css.lead}>Placeholder supporting text.</p>
            )}
          </div>
          <button type="button" className={css.cta}>
            Action
          </button>
        </header>
        {mui ? (
          <ButtonBase className={css.cue} focusRipple={false}>
            <Cue>Scroll</Cue>
          </ButtonBase>
        ) : (
          <button type="button" className={css.cue}>
            <Cue>Scroll</Cue>
          </button>
        )}
      </div>
    </section>
  );
}

function Cue({ children }: { children: ReactNode }) {
  return <span className={css.cueLabel}>{children}</span>;
}
