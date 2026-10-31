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

interface Held {
  readonly start: CSSNumberish | null;
  readonly cur: number;
  readonly at: number;
}

interface ElState {
  paused: boolean;
  readonly held: Map<Animation, Held>;
}

export const resumeTime = (h: Held, now: number): number => h.cur + (now - h.at);

export function watchSweepPause(els: Element[], IO: typeof IntersectionObserver = IntersectionObserver, now: () => number = () => performance.now()): () => void {
  const state = new Map<Element, ElState>();
  for (const el of els) state.set(el, { paused: false, held: new Map() });
  const hold = (el: Element, st: ElState) => {
    for (const a of el.getAnimations()) {
      if (st.held.has(a) || a.playState !== 'running') continue;
      st.held.set(a, { start: a.startTime, cur: Number(a.currentTime ?? 0), at: now() });
      a.pause();
    }
  };
  const resume = (st: ElState) => {
    for (const [a, h] of st.held) {
      if (a.playState !== 'paused') continue;
      if (h.start == null) a.currentTime = resumeTime(h, now());
      a.play();
      if (h.start != null) a.startTime = h.start;
    }
    st.held.clear();
  };
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
    for (const st of state.values()) if (st.paused) resume(st);
  };
}
