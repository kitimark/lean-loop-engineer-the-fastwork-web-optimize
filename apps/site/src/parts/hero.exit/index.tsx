import { useEffect, useRef, type ReactNode } from 'react';
import { getClock } from '../../engine/clock';
import { getScrollEngine } from '../../engine/scroll';
import { createExitDriver, mountExit } from './driver';
import { matchList } from './media';
import css from './hero.module.css';
import { registerScoped, SCOPE_ATTR, SCOPED } from './scope';

export interface HeroExitProps {
  variant: string;
  /** What the sticky stage holds (hero.orbit, hero.deck, the copy, hero.cue); the composition is the `hero` part. */
  children?: ReactNode;
}

/**
 * hero.exit: the sticky hero in a 200vh track; `--exit-opacity` is written on the stage per scroll frame (the exit
 * driver). The stage carries `data-splash` (`prep` on the server, then `run` and `done`, owned by hero.orbit) so the
 * copy and the cue can follow the ring splash.
 */
export function HeroExit({ variant, children }: HeroExitProps) {
  const trackRef = useRef<HTMLElement>(null);
  const heroRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const track = trackRef.current;
    const hero = heroRef.current;
    if (!track || !hero) return;
    if (variant === SCOPED) registerScoped(globalThis.CSS);
    const reduce = matchList('mq.rm-reduce');
    const driver = createExitDriver({ track, hero, reduced: () => reduce?.matches ?? false });
    // faithful engine: own rAF per frame, run once on mount; batched engine: read in the callback, write in its writer
    return mountExit({ driver, engine: getScrollEngine(), clock: getClock(), readVh: () => window.innerHeight });
  }, [variant]);

  const scope = variant === SCOPED ? { [SCOPE_ATTR]: '' } : {};
  return (
    <section ref={trackRef} className={css.track} data-fw="hero-exit" data-fw-variant={variant} aria-labelledby="start-selling-heading">
      <div ref={heroRef} className={css.hero} data-splash="prep" {...scope}>
        {children}
      </div>
    </section>
  );
}
