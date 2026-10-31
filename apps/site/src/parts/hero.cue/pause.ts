import { init, seek, tick, step, ticks, orig, reportAction, watchLoopPause } from '../hero.accent/pause';

/**
 * Variant `offscreen-pause` of hero.cue (Lean `Fw.Parts.HeroCuePause` cue_visible_same, cue_reported_no_tick,
 * cue_offscreen_ticks_le_one, on `Fw.Parts.OffscreenPause.look_same`): the `2.2s ease-in-out infinite scrollFloat` loop of
 * `.float` stops while the cue is off screen and resumes with its saved start time. The watcher is hero.accent's.
 */
export const VARIANT = 'offscreen-pause';
export const FLAG = 'hero.cue:offscreen-pause';
export const CYCLE_MS_CUE = 2200;

export { init, seek, tick, step, ticks, orig, reportAction, watchLoopPause };

const frac = (x: number) => x - Math.floor(x);

/** Lean `HeroCuePause.cueY e t`: translateY in px at local time t ms for the easing `e` (progress to eased progress). */
export function cueY(e: (p: number) => number, t: number): number {
  const p = frac(t / CYCLE_MS_CUE);
  return p < 0.5 ? -8 * e(2 * p) : -8 * (1 - e(2 * p - 1));
}
