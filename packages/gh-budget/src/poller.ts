// The elected poller's one step: ask `ci.budget.next`; on `issue` make ONE `gh run list` (every run created since
// `createdSince`, one call covers all waiters) and write the runs-status file. Waiters read that file and call no gh.
import { appendFileSync } from "node:fs";
import type { Env, Json } from "./core.ts";
import { chargedCall } from "./charged.ts";
import { loadState, locked, paths, readStatus, stepEvent, stepUnlocked, writeStatus, type Row } from "./state.ts";

export const LIST_FIELDS = "status,conclusion,databaseId,headBranch,workflowName,headSha,createdAt";
/** gh rows per page (a page is what `pages` in the budget state counts). */
const PAGE = 100;

export const iso = (t: number): string => new Date(t * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");

export type Poll = {
  /** Epoch second at which the poller should ask again. */
  wakeAt: number;
  /** A gh call was made (the runs-status file may have changed). */
  ticked: boolean;
  /** fwcore said stop (not idle); written to the runs-status file for the waiters. */
  stopped?: string;
};

/** Watches fwcore dropped (expired, unseen, uncovered) are logged to `incidents.jsonl`, then acknowledged. The decision
 *  to drop is fwcore's (`Fw.Ci.Budget.expire`, `listed`); this only writes them down. */
export function drainIncidents(env: Env): number {
  return locked(env, () => {
    const inc = (loadState(env.dir)?.incidents as Json[] | undefined) ?? [];
    if (inc.length === 0) return 0;
    appendFileSync(paths(env.dir).incidents, inc.map((i) => JSON.stringify(i)).join("\n") + "\n");
    stepUnlocked(env, { ack: inc.length });
    return inc.length;
  });
}

export async function pollOnce(env: Env): Promise<Poll> {
  try { return await pollTick(env); } finally { drainIncidents(env); }
}

async function pollTick(env: Env): Promise<Poll> {
  const res = await chargedCall(
    env,
    (state, now) => env.core({ op: "ci.budget.next", now, state }),
    (r) => {
      const pages = Number(r.pages ?? 1); // fwcore's pages: at most the cap its tick share allows
      return ["run", "list", ...(r.createdSince == null ? [] : ["--created", `>=${iso(Number(r.createdSince))}`]),
        "--limit", String(PAGE * pages), "--json", LIST_FIELDS];
    },
  );
  const now = env.now();
  if (!res.ran) {
    if (res.decision === "wait") return { wakeAt: res.until, ticked: false };
    if (res.reason === "idle") return { wakeAt: now + 2, ticked: false };
    writeStatus(env.dir, { rows: [], ...(readStatus(env.dir) ?? {}), at: now, stopped: res.reason, stoppedAt: now });
    return { wakeAt: now + 2, ticked: false, stopped: res.reason };
  }
  if (res.code !== 0) return { wakeAt: now, ticked: true }; // observed by fwcore already; `next` answers with the backoff
  let rows: Row[];
  try {
    const j: unknown = JSON.parse(res.stdout);
    if (!Array.isArray(j)) throw new Error("not a list");
    rows = j as Row[];
  } catch {
    return { wakeAt: now, ticked: true };
  }
  const since = res.reply.createdSince == null ? null : Number(res.reply.createdSince);
  writeStatus(env.dir, { at: now, tickAt: now, createdSince: since, rows });
  // Runs that finished no longer need ticks; one more page when the list came back full (glue rules, see the handoff).
  const st = loadState(env.dir);
  const watched = (st?.watched as { runId: number }[] | undefined) ?? [];
  for (const w of watched) if (rows.some((r) => r.databaseId === w.runId && r.status === "completed")) stepEvent(env, { unregister: w.runId });
  // fwcore decides which watches this list covers: it keeps or drops each (`listed`); a full list was cut at the page limit
  const read = Number(res.reply.pages ?? 1);
  stepEvent(env, { listed: { rows: rows.map((r) => ({ runId: r.databaseId, createdAt: Math.floor(Date.parse(r.createdAt) / 1000) })), full: rows.length >= PAGE * read } });
  const pages = Math.floor(rows.length / PAGE) + 1;
  if (pages !== Number(st?.pages ?? 1)) stepEvent(env, { pages });
  return { wakeAt: now, ticked: true };
}
