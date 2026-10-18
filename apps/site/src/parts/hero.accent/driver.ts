import { next, waitFor, type AccentState } from './logic';

/** The clock surface the chain needs: a real interval (used as a one-shot timeout, like the original's `setTimeout`). */
export interface AccentClock {
  interval(ms: number, cb: () => void): () => void;
}

export interface AccentHooks {
  /** The state class changed (idle / draw-out / draw-in). */
  onState(state: AccentState): void;
  /** The word changed (cursor value, -1 = base word). */
  onCursor(cursor: number): void;
}

/**
 * The faithful chain (N2:3679-3716). One pending timer at a time; each fires once and schedules the next. `setVisible`
 * is the `IntersectionObserver` callback: leaving the viewport band cancels the pending timer, coming back restarts the
 * wait of the current state (the original does not resume the remainder). Returns `stop` (the cleanup, N2:3711-3714).
 */
export function startAccentChain(opts: { clock: AccentClock; hooks: AccentHooks }): {
  stop(): void;
  setVisible(visible: boolean): void;
} {
  let cancel: (() => void) | null = null;
  let visible = true;
  let disposed = false;
  let cursor = -1;
  let state: AccentState = 'idle';
  let firstIdle = true;

  const clear = () => {
    cancel?.();
    cancel = null;
  };
  const after = (ms: number, fn: () => void) => {
    clear();
    const off = opts.clock.interval(ms, () => {
      off();
      if (cancel === off) cancel = null;
      fn();
    });
    cancel = off;
  };
  const step = () => {
    if (disposed || !visible) return;
    clear();
    if (state === 'idle') {
      const wait = waitFor('idle', firstIdle && cursor < 0);
      if (cursor < 0) firstIdle = false;
      after(wait, () => {
        if (disposed || !visible) return;
        state = 'draw-out';
        opts.hooks.onState(state);
        step();
      });
    } else if (state === 'draw-out') {
      after(waitFor('draw-out', false), () => {
        if (disposed || !visible) return;
        cursor = next({ c: cursor });
        opts.hooks.onCursor(cursor);
        state = 'draw-in';
        opts.hooks.onState(state);
        step();
      });
    } else {
      after(waitFor('draw-in', false), () => {
        if (disposed || !visible) return;
        state = 'idle';
        opts.hooks.onState(state);
        step();
      });
    }
  };
  step();
  return {
    stop() {
      disposed = true;
      clear();
    },
    setVisible(v) {
      if (v === visible) return;
      visible = v;
      clear();
      if (visible) step();
    },
  };
}
