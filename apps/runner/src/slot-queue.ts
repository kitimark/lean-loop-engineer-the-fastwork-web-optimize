import type { Kind } from "./slot-core.ts";

export const WHY_TAGS: readonly string[] = ["queued", "older", "full", "simBusy", "drain", "memory", "memLow", "simFirst", "pass", "gap", "unknown", "measureBusy"];

export type WaitMs = { why: string; ms: number };
export type Queue = { kind: Kind; waitMs: number; waits: WaitMs[] };

export function addWait(acc: readonly WaitMs[], why: string, ms: number): WaitMs[] {
  if (!(ms > 0) || !Number.isFinite(ms)) return [...acc];
  const i = acc.findIndex((w) => w.why === why);
  if (i < 0) return [...acc, { why, ms }];
  return acc.map((w, j) => (j === i ? { why, ms: w.ms + ms } : w));
}

export const queueOf = (kind: Kind, waits: readonly WaitMs[], waitMs: number): Queue | null =>
  !(waitMs > 0) || waits.length === 0 ? null : { kind, waitMs: Math.round(waitMs), waits: waits.map((w) => ({ why: w.why, ms: Math.round(w.ms) })) };

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

const NOTE = Symbol.for("fw.slot.queue");
export const noteQueue = (q: Queue | null): void => { (globalThis as Record<symbol, unknown>)[NOTE] = q; };
export function queueExtra(): { queue?: Queue } {
  const q = (globalThis as Record<symbol, unknown>)[NOTE] as Queue | null | undefined;
  return q ? { queue: q } : {};
}
