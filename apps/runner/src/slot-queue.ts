// The time a slot ticket waited, per wait reason (task timing-queue-wait). I/O glue only: it sums the ms the poll loop
// spent under each reason; whether that wait is a queue wait, a slow step or an alert is decided by Lean
// (Fw.Obs.Timing.judgeQ over the Fw.Sup.Adapt.WhyTag list).
import type { Kind } from "./slot-core.ts";

/** TS stand-in for Lean `Fw.Sup.Adapt.WhyTag.all` (names): checked against the golden `adapt.whyTags` in test/slot-queue.test.ts. */
export const WHY_TAGS: readonly string[] = ["queued", "older", "full", "simBusy", "drain", "memory", "memLow", "simFirst", "pass", "gap", "unknown", "measureBusy"];

export type WaitMs = { why: string; ms: number };
/** Written on the span of an acquire (and of a `slot wait`) that was admitted after waiting: the total and the ms per reason. */
export type Queue = { kind: Kind; waitMs: number; waits: WaitMs[] };

/** Add `ms` under `why`: a sum per reason, in first-seen order. A non-positive or non-finite `ms` adds nothing. */
export function addWait(acc: readonly WaitMs[], why: string, ms: number): WaitMs[] {
  if (!(ms > 0) || !Number.isFinite(ms)) return [...acc];
  const i = acc.findIndex((w) => w.why === why);
  if (i < 0) return [...acc, { why, ms }];
  return acc.map((w, j) => (j === i ? { why, ms: w.ms + ms } : w));
}

/** The span field: null unless the ticket waited under some reason. */
export const queueOf = (kind: Kind, waits: readonly WaitMs[], waitMs: number): Queue | null =>
  !(waitMs > 0) || waits.length === 0 ? null : { kind, waitMs: Math.round(waitMs), waits: waits.map((w) => ({ why: w.why, ms: Math.round(w.ms) })) };

/** Parse the `waits` of a span against the Lean tag list: an entry with an unknown name or a bad ms is dropped (closed
 *  parse), so its ms stay in the judged remainder. */
export function parseWaits(x: unknown): WaitMs[] {
  if (!Array.isArray(x)) return [];
  const out: WaitMs[] = [];
  for (const e of x) {
    const o = e as { why?: unknown; ms?: unknown } | null;
    if (o === null || typeof o !== "object" || typeof o.why !== "string" || !WHY_TAGS.includes(o.why)) continue;
    if (typeof o.ms !== "number" || !Number.isFinite(o.ms) || !(o.ms > 0)) continue;
    out.push({ why: o.why, ms: Math.round(o.ms) });
  }
  return out;
}

// The CLI entry (`fw slot acquire`) opens its span before the slot code runs and closes it on exit: the slot code leaves
// the queue here, on the process, so both can live in different module instances.
const NOTE = Symbol.for("fw.slot.queue");
export const noteQueue = (q: Queue | null): void => { (globalThis as Record<symbol, unknown>)[NOTE] = q; };
/** `{ queue }` for the span extras, or `{}` when the process did not wait. */
export function queueExtra(): { queue?: Queue } {
  const q = (globalThis as Record<symbol, unknown>)[NOTE] as Queue | null | undefined;
  return q ? { queue: q } : {};
}
