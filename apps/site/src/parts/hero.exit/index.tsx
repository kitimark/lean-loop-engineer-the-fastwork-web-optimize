import { useEffect, useRef, type ReactNode } from 'react';
import { getClock } from '../../engine/clock';
import { getScrollEngine } from '../../engine/scroll';
import { createExitDriver, mountExit } from './driver';
import { matchList } from './media';
import css from './hero.module.css';
import { liveReaders, registerScoped, SCOPED } from './scope';
import { createHandoff, pointerNoneFromEntry, sentinelTop, THREADED } from './threaded';
import threaded from './threaded.module.css';

export interface HeroExitProps {
  variant: string;
  /** What the sticky stage holds (hero.orbit, hero.deck, the copy, hero.cue); the composition is the `hero` part. */
  children?: ReactNode;
}

/** hero.exit: the sticky hero in a 200vh track whose stage carries `--exit-opacity` and `data-splash`. */
export function HeroExit({ variant, children }: HeroExitProps) {
  const trackRef = useRef<HTMLElement>(null);
  const heroRef = useRef<HTMLDivElement>(null);
  const sentinelRef = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const track = trackRef.current;
    const hero = heroRef.current;
    if (!track || !hero) return;
    const scoped = variant === SCOPED;
    if (scoped) registerScoped(globalThis.CSS);
    const reduce = matchList('mq.rm-reduce');
    const readers = scoped ? liveReaders(hero) : null;
    const driver = createExitDriver({ track, hero, reduced: () => reduce?.matches ?? false, readers: readers?.get });
    // faithful engine: own rAF per frame, run once on mount; batched engine: read in the callback, write in its writer
    const start = () => mountExit({ driver, engine: getScrollEngine(), clock: getClock(), readVh: () => window.innerHeight });
    const sentinel = sentinelRef.current;
    if (variant === THREADED && sentinel) {
      const cue = hero.querySelector<HTMLElement>('[data-fw="hero-cue"]');
      const handoff = createHandoff({
        stage: hero,
        track,
        entranceFinished: () => cue === null || cue.getAnimations().every((a) => a.playState === 'finished'),
        supported: typeof CSS !== 'undefined' && CSS.supports('animation-timeline', 'view()'),
        reduced: () => reduce?.matches ?? false,
        startDriver: start,
        placeSentinel: () => {
          sentinel.style.top = `${sentinelTop(track.getBoundingClientRect().height, window.innerHeight)}px`;
        },
        watchSentinel: (none) => {
          const io = new IntersectionObserver((entries) => {
            const last = entries[entries.length - 1];
            if (last) none(pointerNoneFromEntry(last));
          });
          io.observe(sentinel);
          return () => io.disconnect();
        },
      });
      const mo = new MutationObserver((records) => handoff.onMutations(records));
      mo.observe(hero, { attributes: true, attributeFilter: ['data-splash'], attributeOldValue: true });
      hero.addEventListener('animationend', handoff.sync);
      hero.addEventListener('animationcancel', handoff.sync);
      const onResize = () => handoff.resize();
      window.addEventListener('resize', onResize);
      reduce?.addEventListener('change', handoff.sync);
      return () => {
        mo.disconnect();
        hero.removeEventListener('animationend', handoff.sync);
        hero.removeEventListener('animationcancel', handoff.sync);
        window.removeEventListener('resize', onResize);
        reduce?.removeEventListener('change', handoff.sync);
        handoff.stop();
      };
    }
    const unmount = start();
    return () => {
      unmount();
      readers?.stop();
    };
  }, [variant]);

  return (
    <section ref={trackRef} className={css.track} data-fw="hero-exit" data-fw-variant={variant} aria-labelledby="start-selling-heading">
      <div ref={heroRef} className={css.hero} data-splash="prep" data-exit-scope={variant === SCOPED ? '' : undefined}>
        {children}
      </div>
      {variant === THREADED ? <span ref={sentinelRef} className={threaded.sentinel} aria-hidden="true" /> : null}
    </section>
  );
}
