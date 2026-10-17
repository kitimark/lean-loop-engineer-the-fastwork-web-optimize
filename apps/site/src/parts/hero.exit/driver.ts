import { exitFrame } from './logic';

export interface ExitTarget {
  style: { pointerEvents: string; setProperty(name: string, value: string): void };
}
export interface TrackRect {
  getBoundingClientRect(): { top: number; height: number };
}

/**
 * The faithful per-frame handler (N2:4155-4172): read the track's rect, write `--exit-opacity` and `pointer-events`
 * on the hero (a custom property on a subtree: the bad write the faithful variant keeps). Reduced motion is read
 * at each frame (`matches`), as the original does. Called once per frame by the scroll engine.
 */
export function createExitDriver(opts: {
  track: TrackRect;
  hero: ExitTarget;
  reduced: () => boolean;
  innerHeight: () => number;
}) {
  return {
    frame() {
      const reduced = opts.reduced();
      // the original returns before the rect read under reduced motion
      const rect = reduced ? { top: 0, height: 0 } : opts.track.getBoundingClientRect();
      const r = exitFrame(reduced, rect.top, rect.height, opts.innerHeight());
      opts.hero.style.setProperty('--exit-opacity', String(r.opacity));
      opts.hero.style.pointerEvents = r.pointerNone ? 'none' : '';
      return r;
    },
  };
}
