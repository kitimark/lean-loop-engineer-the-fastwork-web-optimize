import { CLOSE_MS, flags, step, type Ev, type Phase } from './logic';

export interface MenuEnv {
  /** One-shot timer; returns its cancel. */
  after(ms: number, cb: () => void): () => void;
  /** The phase changed. */
  onPhase(phase: Phase): void;
}

/**
 * The menu controller (N2:12750-12776): holds the phase, applies the pure `step` (Lean `NavLangMenu.step`) and its timer
 * action. The 140 ms close timer is re-armed on every close and cleared on open; its expiry is the `timer` event.
 */
export function createMenuController(env: MenuEnv, initial: Phase = 'closed') {
  let phase = initial;
  let cancel: (() => void) | null = null;

  const clearTimer = () => {
    cancel?.();
    cancel = null;
  };

  function dispatch(ev: Ev) {
    const out = step({ phase, ev });
    if (out.timer === 'clear') clearTimer();
    if (out.timer === 'rearm') {
      clearTimer();
      cancel = env.after(CLOSE_MS, () => {
        cancel = null;
        dispatch('timer');
      });
    }
    if (out.phase !== phase) {
      phase = out.phase;
      env.onPhase(phase);
    }
  }

  return {
    dispatch,
    phase: () => phase,
    flags: () => flags({ phase }),
    dispose: clearTimer,
  };
}

export type MenuController = ReturnType<typeof createMenuController>;
