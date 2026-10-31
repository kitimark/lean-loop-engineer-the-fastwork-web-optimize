import { watchHidden } from '../engine.scene/observe';
import { PERIOD_MS, phase } from './logic';

export const VARIANT = 'offscreen-pause';
export const FLAG = 'platform.sweep:offscreen-pause';

export interface PauseState {
  readonly loc: number;
  readonly clk: number;
  readonly paused: boolean;
  readonly off: number;
}

export const init = (off: number): PauseState => ({ loc: off, clk: 0, paused: false, off });

export function seek(s: PauseState, rep: boolean): PauseState {
  if (rep) return { ...s, paused: true };
  return s.paused ? { ...s, paused: false, loc: s.clk + s.off } : s;
}

export const tick = (s: PauseState, d: number, rep: boolean): PauseState => ({ ...s, clk: s.clk + d, loc: rep ? s.loc : s.loc + d });

export const step = (s: PauseState, d: number, rep: boolean): PauseState => tick(seek(s, rep), d, rep);

export const ticks = (rep: boolean): number => (rep ? 0 : 1);

export const orig = (off: number, ds: readonly number[]): number => off + ds.reduce((a, b) => a + b, 0);

export { PERIOD_MS, phase };

export const reportAction = (paused: boolean, rep: boolean): 'pause' | 'resume' | 'none' => (rep ? (paused ? 'none' : 'pause') : paused ? 'resume' : 'none');

interface ElState {
  paused: boolean;
  readonly starts: Map<Animation, CSSNumberish | null>;
}

export function watchSweepPause(els: Element[], IO: typeof IntersectionObserver = IntersectionObserver): () => void {
  const state = new Map<Element, ElState>();
  for (const el of els) state.set(el, { paused: false, starts: new Map() });
  const holdOne = (st: ElState, a: Animation) => {
    if (st.starts.has(a) || a.playState !== 'running' || a.startTime == null) return;
    st.starts.set(a, a.startTime);
    a.pause();
  };
  const hold = (el: Element, st: ElState) => {
    for (const a of el.getAnimations()) {
      if (a.playState === 'running' && a.startTime == null) {
        void a.ready.then(
          () => {
            if (st.paused) holdOne(st, a);
          },
          () => undefined,
        );
      } else holdOne(st, a);
    }
  };
  const resume = (st: ElState) => {
    for (const [a, s] of st.starts) {
      if (a.playState !== 'paused') continue;
      a.play();
      if (s != null) a.startTime = s;
    }
    st.starts.clear();
  };
  const started = new Map<Element, () => void>();
  for (const [el, st] of state) {
    const on = () => {
      if (st.paused) hold(el, st);
    };
    started.set(el, on);
    el.addEventListener('animationstart', on);
  }
  const stop = watchHidden(
    els,
    'rect',
    (el, hidden) => {
      const st = state.get(el);
      if (!st) return;
      const act = reportAction(st.paused, hidden);
      if (act === 'pause') {
        st.paused = true;
        hold(el, st);
      } else if (act === 'resume') {
        resume(st);
        st.paused = false;
      }
    },
    IO,
  );
  return () => {
    stop();
    for (const [el, on] of started) el.removeEventListener('animationstart', on);
    for (const st of state.values()) if (st.paused) resume(st);
  };
}
