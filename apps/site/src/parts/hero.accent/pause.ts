import { watchHidden } from '../engine.scene/observe';
import { reportAction, init, seek, tick, step, ticks, orig } from '../platform.sweep/pause';
import { CYCLE_MS, origVal } from './steps';

/**
 * Variant `offscreen-pause` of hero.accent (Lean `Fw.Parts.HeroAccentPause` accent_visible_same, accent_reported_no_tick,
 * accent_offscreen_ticks_le_one, on `Fw.Parts.OffscreenPause.look_same`). The pure model is the sweep's
 * (`platform.sweep/pause`, Lean `PlatformSweepPause`); the DOM side below is shared with `hero.cue/pause`.
 */
export const VARIANT = 'offscreen-pause';
export const FLAG = 'hero.accent:offscreen-pause';

export { init, seek, tick, step, ticks, orig, reportAction };

const frac = (x: number) => x - Math.floor(x);

/** Lean `HeroAccentPause.shown j t`: opacity of boil box j at local time t ms (the original's step-end value). */
export const shown = (j: number, t: number): number => origVal(j, CYCLE_MS * frac(t / CYCLE_MS));

/** An infinite-iteration animation: the loops the pause acts on (finite draw and entry animations are left alone). */
export const isLoop = (a: Animation): boolean => a.effect?.getTiming().iterations === Infinity;

/** The loops of an element and its subtree, read at the moment of the call (the style flush makes late ones visible). */
export const loopsOf = (el: Element): Animation[] => el.getAnimations({ subtree: true }).filter(isLoop);

interface ElState {
  paused: boolean;
  readonly starts: Map<Animation, CSSNumberish | null>;
}

/**
 * Pause the loops of each element while the observer reports it off screen, and resume them with their saved start time
 * (so the phase is the unpaused one, `shown_same`). The loops are read when the element is reported, not at mount, so a
 * loop created before that (the cue's after the splash) is covered. Limits (named premises): the observer reports after
 * the frame the element left; a loop created while the element is off screen is not tracked; a loop the page cancelled
 * meanwhile (the accent's class change to a draw state) is not resumed, since it no longer exists.
 */
export function watchLoopPause(
  els: Element[],
  pick: (el: Element) => Animation[] = loopsOf,
  IO: typeof IntersectionObserver = IntersectionObserver,
): () => void {
  const state = new Map<Element, ElState>();
  for (const el of els) state.set(el, { paused: false, starts: new Map() });
  const resume = (st: ElState) => {
    for (const [a, s] of st.starts) {
      if (a.playState !== 'paused') continue;
      a.play();
      if (s != null) a.startTime = s;
    }
    st.starts.clear();
  };
  const stop = watchHidden(
    els,
    'rect',
    (el, hidden) => {
      const st = state.get(el);
      if (!st) return;
      const act = reportAction(st.paused, hidden);
      if (act === 'pause') {
        for (const a of pick(el)) {
          if (a.playState !== 'running') continue;
          st.starts.set(a, a.startTime);
          a.pause();
        }
        st.paused = true;
      } else if (act === 'resume') {
        resume(st);
        st.paused = false;
      }
    },
    IO,
  );
  return () => {
    stop();
    for (const st of state.values()) if (st.paused) resume(st);
  };
}
