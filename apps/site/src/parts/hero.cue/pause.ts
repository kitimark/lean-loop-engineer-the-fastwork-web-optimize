import { init, seek, tick, step, ticks, orig, reportAction, watchLoopPause } from '../hero.accent/pause';

export const VARIANT = 'offscreen-pause';
export const FLAG = 'hero.cue:offscreen-pause';
export const CYCLE_MS_CUE = 2200;

export { init, seek, tick, step, ticks, orig, reportAction, watchLoopPause };

const frac = (x: number) => x - Math.floor(x);

export function cueY(e: (p: number) => number, t: number): number {
  const p = frac(t / CYCLE_MS_CUE);
  return p < 0.5 ? -8 * e(2 * p) : -8 * (1 - e(2 * p - 1));
}
