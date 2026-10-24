import { watchHidden } from '../engine.scene/observe';
import { PERIOD_MS, phase } from './logic';

/**
 * platform.sweep `offscreen-pause`: the sweep animation stops while its element is reported offscreen and, on return,
 * is seeked to the document timeline's time plus the animation's fixed start offset, which is the time an uninterrupted
 * animation shows. Spec and proofs: lean/Fw/Parts/PlatformSweepPause.lean (`shown_same`, `reported_no_tick`,
 * `offscreen_ticks_le_one`). Golden: packages/contracts/golden/parts/platform-sweep-pause.jsonl.
 */
export const VARIANT = 'offscreen-pause';
export const FLAG = 'platform.sweep:offscreen-pause';

/** Lean `PlatformSweepPause.St`: animation time, timeline time, paused, start offset. */
export interface PauseState {
  readonly loc: number;
  readonly clk: number;
  readonly paused: boolean;
  readonly off: number;
}

/** Lean `init`: timeline at 0, animation at its offset, running. */
export const init = (off: number): PauseState => ({ loc: off, clk: 0, paused: false, off });

/** Lean `seek`: the observer callbacks at a frame's start (`rep` = reported offscreen). */
export function seek(s: PauseState, rep: boolean): PauseState {
  if (rep) return { ...s, paused: true };
  return s.paused ? { ...s, paused: false, loc: s.clk + s.off } : s;
}

/** Lean `tick`: the timeline always advances, the animation only when not reported offscreen. */
export const tick = (s: PauseState, d: number, rep: boolean): PauseState => ({ ...s, clk: s.clk + d, loc: rep ? s.loc : s.loc + d });

/** Lean `step`: callbacks, then the frame's time. */
export const step = (s: PauseState, d: number, rep: boolean): PauseState => tick(seek(s, rep), d, rep);

/** Lean `ticks`: 1 when the animation moves this frame, 0 when it is paused. */
export const ticks = (rep: boolean): number => (rep ? 0 : 1);

/** Lean `orig`: the original's animation time after the frames (offset plus elapsed timeline time). */
export const orig = (off: number, ds: readonly number[]): number => off + ds.reduce((a, b) => a + b, 0);

export { PERIOD_MS, phase };

const timelineNow = (): number => Number(document.timeline.currentTime ?? performance.now());

/** What a report does to one element's animations: pause them, resume them (seek first), or nothing (Lean `seek`). */
export const reportAction = (paused: boolean, rep: boolean): 'pause' | 'resume' | 'none' => (rep ? (paused ? 'none' : 'pause') : paused ? 'resume' : 'none');

/**
 * DOM glue (no decision beyond `reportAction`): one IntersectionObserver over the sweep elements. Start offsets are read
 * at start from the running animations (`currentTime - timeline`); a report pauses them, the next unreported callback
 * sets `currentTime = timeline + offset` and plays them. Returns the stop function (resumes everything).
 */
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
