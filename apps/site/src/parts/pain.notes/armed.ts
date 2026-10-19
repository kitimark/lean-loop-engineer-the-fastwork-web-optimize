/**
 * Variant `visible` of pain.notes (ledger n=21; Lean: lean/Fw/Parts/PainNotesOpt.lean `armed`, `tickV`, `resumeAt`).
 * The 3 s rotation interval runs only while its notes can be seen: the section is in view, wider than 860 px and not
 * covered by the commission card. A re-arm resumes on the original's tick grid, never on a fresh 3 s period
 * (`naive_rearm_shifts`). Pure decisions; the driver owns the timers.
 */

/** The original's interval period (Lean `period`). */
export const PERIOD_MS = 3000;

export interface Ctx {
  inView: boolean;
  narrow: boolean;
  covered: boolean;
}

/** Lean `armed c`: in view, not narrow, not covered. */
export function armed(c: Ctx): boolean {
  return c.inView && !c.narrow && !c.covered;
}

/** Lean `tickAt t0 k`: the original's k-th tick after it was armed at t0 (k from 0). */
export function tickAt(t0: number, k: number): number {
  return t0 + PERIOD_MS * (k + 1);
}

/** Lean `resumeAt t0 now`: the original's first tick at or after `now` (and never `t0` itself). Whole ms. */
export function resumeAt(t0: number, now: number): number {
  return t0 + PERIOD_MS * Math.max(1, Math.floor((Math.max(0, now - t0) + (PERIOD_MS - 1)) / PERIOD_MS));
}

/** Lean `ticksIn t0 a b`: how many ticks of an interval armed at t0 fire in (a, b]. */
export function ticksIn(t0: number, a: number, b: number): number {
  let n = 0;
  for (let k = 0; k < b; k += 1) {
    const t = tickAt(t0, k);
    if (a < t && t <= b) n += 1;
  }
  return n;
}
