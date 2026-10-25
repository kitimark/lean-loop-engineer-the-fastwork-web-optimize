// The elected poller's one step: ask `ci.budget.next`; on `issue` make ONE `gh run list` (every run created since
// `createdSince`, one call covers all waiters) and write the runs-status file. Waiters read that file and call no gh.
import { appendFileSync } from "node:fs";
import type { Env, Json } from "./core.ts";
import { GH_BOUNDS } from "./bounds.gen.ts";
import { chargedCall } from "./charged.ts";
import { LockBusy } from "./lock.ts";
import { readMarkers } from "./waiters.ts";
import { dedupById, dupIds } from "./want.ts";
import { loadState, locked, paths, readStatus, stepEvent, stepUnlocked, writeStatus, type Row, type Status } from "./state.ts";

export const LIST_FIELDS = "status,conclusion,databaseId,headBranch,workflowName,headSha,createdAt,updatedAt,attempt,event,displayTitle";
const PAGE = 100;

export type TickStatus = Status & { interval?: number; retryUntil?: number };

const nat = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;

export function tickBudget(st: Status | null): { pollS?: number; retryUntilS?: number } {
  const t = st as TickStatus | null;
  return { ...(nat(t?.interval) ? { pollS: t.interval } : {}), ...(nat(t?.retryUntil) ? { retryUntilS: t.retryUntil } : {}) };
}

function intervalAt(env: Env, now: number, state: Json): number | undefined {
  try {
    const r = env.core({ op: "ci.budget.status", now, state });
    return nat(r.interval) ? r.interval : undefined;
  } catch {
    return undefined;
  }
}

/** The row's `updatedAt` in epoch milliseconds, 0 when absent (Lean `Fw.Ci.Dispatch.Listed.updatedAt`). */
export function updatedMs(r: Row): number {
  const t = Date.parse(r.updatedAt ?? "");
  return Number.isFinite(t) && t > 0 ? t : 0;
}

export const iso = (t: number): string => new Date(t * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");

export type Poll = {
  /** Epoch second at which the poller should ask again. */
  wakeAt: number;
  /** A gh call was made (the runs-status file may have changed). */
  ticked: boolean;
  /** fwcore said stop (not idle); written to the runs-status file for the waiters. */
  stopped?: string;
};

/** Watches fwcore dropped (unseen, uncovered, orphan) are logged to `incidents.jsonl`, then acknowledged. The decision
 *  to drop is fwcore's (`Fw.Ci.Budget.listed`); this only writes them down. */
export function drainIncidents(env: Env, lockWaitMs?: number): number {
  try { return drainLocked(env, lockWaitMs); } catch (e) { if (e instanceof LockBusy) return 0; throw e; } // the next tick drains
}

function drainLocked(env: Env, lockWaitMs?: number): number {
  return locked(env, () => {
    const inc = (loadState(env.dir)?.incidents as Json[] | undefined) ?? [];
    if (inc.length === 0) return 0;
    appendFileSync(paths(env.dir).incidents, inc.map((i) => JSON.stringify(i)).join("\n") + "\n");
    stepUnlocked(env, { ack: inc.length });
    return inc.length;
  }, lockWaitMs);
}

export async function pollOnce(env: Env, lockWaitMs: number = GH_BOUNDS.pollLockWaitMs): Promise<Poll> {
  try { return await pollTick(env, lockWaitMs); } finally { drainIncidents(env, lockWaitMs); }
}

async function pollTick(env: Env, lockWaitMs: number): Promise<Poll> {
  const res = await chargedCall(
    env,
    // under the state lock: the waiters dir is read here, so fwcore sweeps the watches whose waiter is gone before it
    // computes the window (`Fw.Ci.Budget.sweep`, `next_window_from_live`)
    (state, now) => env.core({ op: "ci.budget.next", now, state, markers: readMarkers(env) }),
    (r) => {
      const pages = Number(r.pages ?? 1); // fwcore's pages: at most the cap its tick share allows
      return ["run", "list", ...(r.createdSince == null ? [] : ["--created", `>=${iso(Number(r.createdSince))}`]),
        "--limit", String(PAGE * pages), "--json", LIST_FIELDS];
    },
    { lockWaitMs },
  );
  const now = env.now();
  if (!res.ran) {
    if (res.decision === "wait") return { wakeAt: res.until, ticked: false };
    if (res.decision === "busy") return { wakeAt: now + GH_BOUNDS.busyRetryS, ticked: false }; // a short wait, never stopped
    if (res.reason === "idle") return { wakeAt: now + 2, ticked: false };
    writeStatus(env.dir, { rows: [], ...(readStatus(env.dir) ?? {}), at: now, stopped: res.reason, stoppedAt: now });
    return { wakeAt: now + 2, ticked: false, stopped: res.reason };
  }
  if (res.code !== 0) return { wakeAt: now, ticked: true }; // observed by fwcore already; `next` answers with the backoff
  let listed: Row[];
  try {
    const j: unknown = JSON.parse(res.stdout);
    if (!Array.isArray(j)) throw new Error("not a list");
    listed = j as Row[];
  } catch {
    return { wakeAt: now, ticked: true };
  }
  const dups = dupIds(listed, (r) => r.databaseId);
  if (dups.length > 0) appendFileSync(paths(env.dir).incidents, JSON.stringify({ duplicateIds: dups, listed: listed.length, pagesRead: Number(res.reply.pages ?? 1), at: now }) + "\n");
  const rows = dedupById(listed, (r) => r.databaseId, updatedMs);
  const since = res.reply.createdSince == null ? null : Number(res.reply.createdSince);
  const pages = Math.floor(listed.length / PAGE) + 1;
  const pre = loadState(env.dir);
  const after = pages !== Number(pre?.pages ?? 1) ? stepEvent(env, { pages }) : pre;
  const interval = intervalAt(env, now, after ?? res.state);
  const retryUntil = (res.reply.state as { retryUntil?: unknown } | undefined)?.retryUntil;
  const tick: TickStatus = { at: now, tickAt: now, createdSince: since, rows, ...(interval === undefined ? {} : { interval }), ...(nat(retryUntil) ? { retryUntil } : {}) };
  writeStatus(env.dir, tick);
  const st = loadState(env.dir);
  const watched = (st?.watched as { runId: number }[] | undefined) ?? [];
  for (const w of watched) if (rows.some((r) => r.databaseId === w.runId && r.status === "completed")) stepEvent(env, { unregister: w.runId });
  // fwcore decides which watches this list covers and whether it was cut at the page limit (`listed`, `isFull`): the glue
  // sends the row count, the pages it asked for and the window start the tick used
  stepEvent(env, { listed: {
    rows: rows.map((r) => ({ runId: r.databaseId, createdAt: Math.floor(Date.parse(r.createdAt) / 1000) })),
    count: listed.length, pagesRead: Number(res.reply.pages ?? 1), ...(since == null ? {} : { createdSince: since }),
  } });
  return { wakeAt: now, ticked: true };
}
