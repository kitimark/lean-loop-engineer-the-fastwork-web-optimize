// The elected poller's one step: ask `ci.budget.next`; on `issue` make ONE `gh run list` (every run created since
// `createdSince`, one call covers all waiters) and write the runs-status file. Waiters read that file and call no gh.
import type { Env, Json } from "./core.ts";
import { chargedCall } from "./charged.ts";
import { loadState, readStatus, stepEvent, writeStatus, type Row } from "./state.ts";

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

export async function pollOnce(env: Env): Promise<Poll> {
  const res = await chargedCall(
    env,
    (state, now) => env.core({ op: "ci.budget.next", now, state }),
    (r) => {
      const pages = Number((r.state as Json).pages ?? 1);
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
  const pages = Math.floor(rows.length / PAGE) + 1;
  if (pages !== Number(st?.pages ?? 1)) stepEvent(env, { pages });
  return { wakeAt: now, ticked: true };
}
