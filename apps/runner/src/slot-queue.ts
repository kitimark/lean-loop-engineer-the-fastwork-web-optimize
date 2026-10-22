// The holder a slot ticket waited behind (task timing-queue-wait). I/O glue only: it records who blocked the ticket and
// for how long; whether that wait is a queue wait, a slow step or an alert is decided by Lean (Fw.Obs.Timing.judgeQ).
import type { Entry, Kind, Verdict } from "./slot-core.ts";

/** Written on the span of an acquire (and of a `slot wait`): the holder waited behind, the wait, and that holder's lease. */
export type Queue = { kind: Kind; owner: string; waitMs: number; leaseMs: number };
export type Behind = { kind: Kind; owner: string; leaseS: number };

type WaitWhy = Exclude<Verdict, { verdict: "admit" }>["why"];

/** The live holders a waiting ticket is behind, by the reason it waits: a measure window or pass is held by the measure
 *  lease, a Simulator ticket by the Simulator lease, memory pressure from outside the queue by no holder, anything else by any live holder. */
export function blockers(why: WaitWhy, live: readonly Entry[]): Entry[] {
  switch (why) {
    case "pass": case "gap": case "unknown": case "measureBusy": return live.filter((h) => h.kind === "measure");
    case "simBusy": return live.filter((h) => h.kind === "sim");
    case "memLow": return [];
    default: return [...live];
  }
}

/** The blocking holder with the longest tenure (the first of equals), or null when none blocks. The tenure is till - since,
 *  not Entry.leaseS: a renewal moves till and keeps since, while leaseS is only the length of one renewal. */
export function behindOf(why: WaitWhy, live: readonly Entry[]): Behind | null {
  let best: Entry | null = null;
  for (const h of blockers(why, live)) if (best === null || h.till - h.since > best.till - best.since) best = h;
  return best === null ? null : { kind: best.kind, owner: best.owner, leaseS: best.till - best.since };
}

/** Keep the holder with the longer lease (the earlier one on a tie). */
export const mergeBehind = (a: Behind | null, b: Behind | null): Behind | null => (a === null ? b : b !== null && b.leaseS > a.leaseS ? b : a);

/** The span field: null unless some poll saw a blocking holder and the ticket waited. */
export const queueOf = (b: Behind | null, waitMs: number): Queue | null =>
  b === null || !(waitMs > 0) ? null : { kind: b.kind, owner: b.owner, waitMs: Math.round(waitMs), leaseMs: Math.round(b.leaseS * 1000) };

// The CLI entry (`fw slot acquire`) opens its span before the slot code runs and closes it on exit: the slot code leaves
// the queue here, on the process, so both can live in different module instances.
const NOTE = Symbol.for("fw.slot.queue");
export const noteQueue = (q: Queue | null): void => { (globalThis as Record<symbol, unknown>)[NOTE] = q; };
/** `{ queue }` for the span extras, or `{}` when the process did not wait behind a holder. */
export function queueExtra(): { queue?: Queue } {
  const q = (globalThis as Record<symbol, unknown>)[NOTE] as Queue | null | undefined;
  return q ? { queue: q } : {};
}
