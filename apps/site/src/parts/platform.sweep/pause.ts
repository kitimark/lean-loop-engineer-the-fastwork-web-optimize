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

const timelineNow = (): number => Number(document.timeline.currentTime ?? performance.now());

export const reportAction = (paused: boolean, rep: boolean): 'pause' | 'resume' | 'none' => (rep ? (paused ? 'none' : 'pause') : paused ? 'resume' : 'none');

export function watchSweepPause(els: Element[]): () => void {
  const state = new Map<Element, { paused: boolean; offs: Map<Animation, number> }>();
  const t0 = timelineNow();
  for (const el of els) {
    const offs = new Map<Animation, number>();
    for (const a of el.getAnimations()) offs.set(a, Number(a.currentTime ?? 0) - t0);
    state.set(el, { paused: false, offs });
  }
  const resume = (st: { offs: Map<Animation, number> }) => {
    const now = timelineNow();
    for (const [a, off] of st.offs) {
      a.currentTime = now + off;
      a.play();
    }
  };
  const stop = watchHidden(els, 'rect', (el, hidden) => {
    const st = state.get(el);
    if (!st) return;
    const act = reportAction(st.paused, hidden);
    if (act === 'pause') {
      for (const a of st.offs.keys()) a.pause();
      st.paused = true;
    } else if (act === 'resume') {
      resume(st);
      st.paused = false;
    }
  });
  return () => {
    stop();
    for (const st of state.values()) if (st.paused) resume(st);
  };
}
