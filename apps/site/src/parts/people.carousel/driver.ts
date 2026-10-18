import type { MotionClock } from '../../engine/clock';
import { afterRest, afterSwap, REST_MS, START, SWAP_MS, type State } from './logic';
import { after } from '../people/shared';

/**
 * The carousel loop (N2:11289-11302) as timers on the clock. The original is an async function: wait for the section to be
 * active, wait 800 ms, and if still active show the swap template for 220 ms, then, if still active, advance the ring. The
 * decisions at the two timer ends are `afterRest` / `afterSwap` (Lean `Fw.Parts.PeopleCarousel`); the activity callback
 * clears the swap flag at once when the activity is lost (N2:11303-11308 `m`).
 */
export function createLoop(opts: { clock: MotionClock; onState: (s: State) => void }) {
  let state: State = START;
  let active = false;
  let disposed = false;
  let cancel: (() => void) | null = null;
  let waiting = false;

  const set = (s: State) => {
    state = s;
    opts.onState(s);
  };

  function begin() {
    if (disposed) return;
    if (!active) {
      waiting = true; // `await p()`
      return;
    }
    cancel = after(opts.clock, REST_MS, () => {
      cancel = null;
      if (disposed) return;
      if (active) {
        set(afterRest({ ...state, active }));
        cancel = after(opts.clock, SWAP_MS, () => {
          cancel = null;
          if (disposed) return;
          set(afterSwap({ ...state, active }));
          begin();
        });
      } else begin();
    });
  }

  return {
    /** the engine's visibility signal (also the first call, before `start`) */
    setActive(a: boolean) {
      active = a;
      if (!a) {
        if (state.swapping) set({ ...state, swapping: false });
      } else if (waiting) {
        waiting = false;
        begin();
      }
    },
    start: begin,
    dispose() {
      disposed = true;
      cancel?.();
      cancel = null;
    },
    get state() {
      return state;
    },
  };
}
