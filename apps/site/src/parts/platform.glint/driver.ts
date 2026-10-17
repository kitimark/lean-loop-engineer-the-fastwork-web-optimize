import { init, step, type Ev, type St } from './logic';

export interface GlintEnv {
  clock: { subscribe(tick: (t: number) => void): () => void };
  now(): number;
  /** `prefers-reduced-motion: reduce` now */
  reduced(): boolean;
  /** called after every transition with the new state (the component maps `v` to the rendered `<animate>` pair) */
  onState(s: St, prev: St): void;
}

/**
 * The play state of the secure-network glint: events go through the Lean-proved transition (logic.ts `step`); the start
 * timer is a clock subscription that fires when the due time has passed (never a setTimeout). The driver is glue.
 */
export function createGlintDriver(env: GlintEnv) {
  let state = init(env.reduced());
  let off: (() => void) | null = null;
  const dispatch = (event: Ev) => {
    const prev = state;
    state = step({ state, now: env.now(), event });
    if (state.timer !== null && off === null) {
      off = env.clock.subscribe((t) => {
        if (state.timer !== null && t >= state.timer) dispatch({ kind: 'fire' });
      });
    }
    if (state.timer === null && off !== null) {
      off();
      off = null;
    }
    if (state !== prev) env.onState(state, prev);
  };
  return {
    get state() {
      return state;
    },
    ratio: (ratio: number) => dispatch({ kind: 'ratio', ratio }),
    reducedChanged: (value: boolean) => dispatch({ kind: 'reduced', value }),
    dispose() {
      off?.();
      off = null;
    },
  };
}
