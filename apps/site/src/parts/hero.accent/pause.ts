import { watchHidden } from '../engine.scene/observe';
import { reportAction, init, seek, tick, step, ticks, orig } from '../platform.sweep/pause';
import { CYCLE_MS, origVal } from './steps';

export const VARIANT = 'offscreen-pause';
export const FLAG = 'hero.accent:offscreen-pause';

export { init, seek, tick, step, ticks, orig, reportAction };

const frac = (x: number) => x - Math.floor(x);

export const shown = (j: number, t: number): number => origVal(j, CYCLE_MS * frac(t / CYCLE_MS));

export const isLoop = (a: Animation): boolean => a.effect?.getTiming().iterations === Infinity;

export const loopsOf = (el: Element): Animation[] => el.getAnimations({ subtree: true }).filter(isLoop);

interface ElState {
  paused: boolean;
  readonly starts: Map<Animation, CSSNumberish | null>;
}

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
          if (a.playState !== 'running' || a.startTime == null) continue;
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
