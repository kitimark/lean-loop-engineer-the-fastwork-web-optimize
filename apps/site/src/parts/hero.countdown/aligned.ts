import type { MotionClock } from '../../engine/clock';

/**
 * Clock-aligned scheduling for hero.countdown (ledger n=8, KD#19; Lean: lean/Fw/Parts/HeroCountdown.lean `drift_skips`,
 * `remainingSeconds_ceil`, lean/Fw/Parts/HeroCountdownOpt.lean `same_run_noClaim`). The original's `setInterval(1000)` can
 * drift: with every tick late by at least delta > 0 a tick eventually crosses two second boundaries and a digit is
 * skipped (`drift_skips`). A timeout chain aimed at T0 + k * 1000 never drifts. One callback per second, the same work as
 * the interval, so the Lean claim is `noClaim`: this is a correctness variant, not a work win.
 * NOT WIRED: hero.countdown/index.tsx chooses the scheduler and is edited by a running lane; see the handoff.
 */

export const PERIOD_MS = 1000;

/** The next aim strictly after `now`: T0 + k * 1000 with the least k such that the aim is later than `now`. */
export function nextAim(t0: number, now: number): number {
  return t0 + PERIOD_MS * (Math.floor(Math.max(0, now - t0) / PERIOD_MS) + 1);
}

/** The delay to wait from `now` to the next aim. Always in (0, 1000]. */
export function delayToAim(t0: number, now: number): number {
  return nextAim(t0, now) - now;
}

export interface AlignedOptions {
  clock: Pick<MotionClock, 'interval'>;
  /** `performance.now()` */
  now: () => number;
  /** One refresh, as the interval would run it. */
  refresh: () => void;
}

/** Runs `refresh` once now (T0 = now) and then at T0 + k * 1000. Returns the cleanup. */
export function startAligned(o: AlignedOptions): () => void {
  const t0 = o.now();
  let cancel: (() => void) | null = null;
  let stopped = false;
  const arm = () => {
    const off = o.clock.interval(delayToAim(t0, o.now()), () => {
      off();
      if (cancel === off) cancel = null;
      if (stopped) return;
      o.refresh();
      arm();
    });
    cancel = off;
  };
  o.refresh();
  arm();
  return () => {
    stopped = true;
    cancel?.();
    cancel = null;
  };
}
