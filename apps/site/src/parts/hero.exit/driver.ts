import { exitFrame } from './logic';

export interface ExitTarget {
  style: { pointerEvents: string; setProperty(name: string, value: string): void };
}
export interface TrackRect {
  getBoundingClientRect(): { top: number; height: number };
}

/**
 * The faithful per-frame handler (N2:4155-4172): read the track's rect, write `--exit-opacity` and `pointer-events`
 * on the hero (a custom property on a subtree: the bad write the faithful variant keeps). Reduced motion is read at
 * each frame (`matches`), as the original does. `read` is the scroll callback's read phase (rect read, maths) and
 * returns the writer, so the engine can interleave (faithful) or batch the writes.
 */
export function createExitDriver(opts: { track: TrackRect; hero: ExitTarget; reduced: () => boolean }) {
  return {
    read(viewportHeight: number): () => void {
      const reduced = opts.reduced();
      // the original returns before the rect read under reduced motion
      const rect = reduced ? { top: 0, height: 0 } : opts.track.getBoundingClientRect();
      const r = exitFrame(reduced, rect.top, rect.height, viewportHeight);
      return () => {
        opts.hero.style.setProperty('--exit-opacity', String(r.opacity));
        opts.hero.style.pointerEvents = r.pointerNone ? 'none' : '';
      };
    },
  };
}

/** Scroll engine surface the exit needs (a subset of `ScrollEngine`, so tests can pass a fake). */
export interface ExitEngine {
  register(id: string, order: number, cb: (f: { vh: number }) => void | (() => void)): () => void;
  readonly variant: 'faithful' | 'batched';
}
export interface ExitClock {
  subscribe(tick: (t: number) => void, opts?: { own?: boolean }): () => void;
}

/** Order on the scroll engine (the hero is registered before the nav in the original: `dE(c)` 4239, nav 13090). */
export const EXIT_ORDER = 10;

/**
 * Wire the exit handler to the engine.
 *
 * faithful engine variant: the engine callback only requests the part's own rAF (`i ||= requestAnimationFrame(s)`,
 * N2:4173-4175); the body (rect read, two style writes) runs in that rAF, which was queued before the next engine
 * frame, so a steady frame is `[exit body] ++ [engine callbacks]` (Lean `pilotFrame`). The body also runs once on mount
 * (N2:4240 `s()`).
 *
 * batched engine variant: the callback does the rect read and returns the writer, so the engine runs all reads, then
 * all writes.
 */
export function mountExit(opts: {
  driver: ReturnType<typeof createExitDriver>;
  engine: ExitEngine;
  clock: ExitClock;
  readVh: () => number;
}): () => void {
  let cancelOwn: (() => void) | null = null;
  const body = () => {
    cancelOwn?.(); // one-shot: `i = 0`, then run
    cancelOwn = null;
    opts.driver.read(opts.readVh())();
  };
  const off = opts.engine.register('hero.exit', EXIT_ORDER, (f) => {
    if (opts.engine.variant === 'batched') return opts.driver.read(f.vh);
    cancelOwn ??= opts.clock.subscribe(body, { own: true });
    return undefined;
  });
  if (opts.engine.variant === 'faithful') body();
  return () => {
    off();
    cancelOwn?.();
    cancelOwn = null;
  };
}
