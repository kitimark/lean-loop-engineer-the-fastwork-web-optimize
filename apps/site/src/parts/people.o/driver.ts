import type { MotionClock } from '../../engine/clock';
import { after } from '../people/shared';
import { EXPAND_DELAY, STACK_DELAY } from './logic';

export interface OFlags {
  stack: boolean;
  expanded: boolean;
}

/**
 * The opening timeline of the "o" (N2:6214-6250): when the heading enters the viewport (observer threshold 0.35) the stack
 * shows after 1300 ms and the row opens 120 ms later (standalone: the stack at once, the row after 120 ms; reduced motion:
 * both at once); leaving clears both (reduced motion: sets both). `reset` is also called to drop a hovered face (N2:6218).
 * The timer plan is `plan` / `phase` in logic.ts (Lean `Fw.Parts.PeopleO`).
 */
export function createOpener(opts: {
  clock: MotionClock;
  reduced: boolean;
  standalone: boolean;
  onFlags: (f: OFlags) => void;
  onReset: () => void;
}) {
  const cancels: Array<() => void> = [];
  let inside = false;

  const clear = () => {
    for (const c of cancels.splice(0)) c();
  };
  const reset = () => {
    clear();
    opts.onReset();
    opts.onFlags(opts.reduced ? { stack: true, expanded: true } : { stack: false, expanded: false });
  };
  const enter = () => {
    reset();
    if (opts.reduced) return;
    if (opts.standalone) {
      opts.onFlags({ stack: true, expanded: false });
      cancels.push(after(opts.clock, EXPAND_DELAY, () => opts.onFlags({ stack: true, expanded: true })));
      return;
    }
    cancels.push(
      after(opts.clock, STACK_DELAY, () => {
        opts.onFlags({ stack: true, expanded: false });
        cancels.push(after(opts.clock, EXPAND_DELAY, () => opts.onFlags({ stack: true, expanded: true })));
      }),
    );
  };

  return {
    /** observer callback (N2:6246-6250) */
    visibility(isIntersecting: boolean) {
      if (isIntersecting && !inside) enter();
      if (!isIntersecting && inside) reset();
      inside = isIntersecting;
    },
    dispose: clear,
  };
}
