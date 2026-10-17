// `fw ci wait`: register a run (or a branch) with the budget state, then block on the local runs-status file. A waiter
// makes no GitHub call except one charged `gh run view` per run id nobody has seen yet (cached for everyone). The
// first waiter that wins `poller.lock` also runs the poller; when it leaves, another waiter takes over.
import { mkdirSync, readdirSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import type { Env } from "./core.ts";
import { ghCharged } from "./charged.ts";
import { lockAsync, tryLock, type Lock } from "./lock.ts";
import { pollOnce, LIST_FIELDS } from "./poller.ts";
import { locked, paths, readJson, readStatus, stepUnlocked, writeAtomic, type Row, type Status } from "./state.ts";

export type Target =
  | { kind: "run"; runId: number }
  /** `since`: epoch second of the commit being waited for (runs created before it are not ours). */
  | { kind: "branch"; branch: string; workflow?: string; sha: string; since: number };

export type Waited = { code: 0 | 1 | 2 | 3; lines: string[] };

/** Local re-read period of a waiter, seconds (file reads and lock checks only, no GitHub call). */
const SLICE = 2;

const epoch = (iso: string) => Math.floor(Date.parse(iso) / 1000);
const fnv = (s: string) => { let h = 0x811c9dc5; for (const c of s) { h ^= c.charCodeAt(0); h = Math.imul(h, 0x01000193) >>> 0; } return h; };
/** Watch id for a branch waiter: far above real run ids, stable per (branch, workflow, sha). */
export const sentinelId = (t: { branch: string; workflow?: string; sha: string }) => 1_000_000_000_000_000 + fnv(`${t.branch}\n${t.workflow ?? ""}\n${t.sha}`);

const line = (r: Row) => `run ${r.databaseId} ${r.workflowName || "-"} ${r.conclusion ?? r.status}`;

/** Which rows decide the wait: the run, or the newest run of each workflow on the branch created after the commit. */
function relevant(rows: Row[], t: Target): Row[] {
  if (t.kind === "run") return rows.filter((r) => r.databaseId === t.runId);
  const mine = rows.filter((r) => r.headBranch === t.branch && (t.workflow === undefined || r.workflowName === t.workflow) && epoch(r.createdAt) >= t.since);
  const newest = new Map<string, Row>();
  for (const r of mine) { const k = r.workflowName; if (!newest.has(k) || r.databaseId > newest.get(k)!.databaseId) newest.set(k, r); }
  return [...newest.values()];
}

type Eval = { done: Row[] } | { stopped: string } | { pending: true };
function evaluate(st: Status | null, t: Target, regAt: number): Eval {
  if (!st) return { pending: true };
  const rs = relevant(st.rows, t);
  if (rs.length > 0 && rs.every((r) => r.status === "completed")) return { done: rs };
  if (st.stopped && (st.stoppedAt ?? 0) >= regAt) return { stopped: st.stopped };
  return { pending: true };
}

/** Exit code of a finished wait: 0 when every decisive run succeeded, else 1. */
const verdict = (rs: Row[]): 0 | 1 => (rs.every((r) => r.conclusion === "success") ? 0 : 1);

// ---- registration with a refcount, so one waiter leaving does not unwatch a run another waiter still waits on ----------
const key = (id: number) => `r${id}`;

function addWaiter(env: Env, id: number, createdAt: number): string {
  const dir = paths(env.dir).waiters;
  mkdirSync(dir, { recursive: true });
  const marker = join(dir, `${key(id)}.${process.pid}.${randomBytes(4).toString("hex")}`);
  locked(env, () => {
    writeFileSync(marker, "");
    stepUnlocked(env, { register: { runId: id, createdAt } });
  });
  return marker;
}

function alivePid(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; }
}

function dropWaiter(env: Env, id: number, marker: string): void {
  const dir = paths(env.dir).waiters;
  locked(env, () => {
    try { unlinkSync(marker); } catch { /* gone */ }
    const rest = readdirSync(dir).filter((n) => n.startsWith(`${key(id)}.`)).filter((n) => {
      if (alivePid(Number(n.split(".")[1]))) return true;
      try { unlinkSync(join(dir, n)); } catch { /* gone */ }
      return false;
    });
    if (rest.length === 0) stepUnlocked(env, { unregister: id });
  });
}

/** Cleanups of waits in progress, run synchronously by a signal handler. */
export const cleanups = new Set<() => void>();

// ---- the bootstrap of a run id: its creation time, from the poller's list or one charged view (cached) -----------------
async function createdOf(env: Env, runId: number, deadline: number): Promise<{ row: Row } | { fail: Waited }> {
  const known = (): Row | undefined => readStatus(env.dir)?.rows.find((r) => r.databaseId === runId) ?? readJson<Row>(paths(env.dir).meta(runId)) ?? undefined;
  const k = known();
  if (k) return { row: k };
  mkdirSync(join(env.dir, "meta"), { recursive: true });
  const l = await lockAsync(paths(env.dir).metaLock(runId), 120, env.now, env.sleepUntil); // one view per run id, however many waiters start together
  try {
    const k2 = known();
    if (k2) return { row: k2 };
    const res = await ghCharged(env, ["run", "view", String(runId), "--json", LIST_FIELDS], { cost: 2, block: true, deadline });
    if (!res.ran) return { fail: { code: 3, lines: [`wait: no gh call for the run view: ${res.decision} (${res.reason}); see \`fw ci budget\``] } };
    if (res.code !== 0) return { fail: { code: 2, lines: [`wait: gh run view ${runId} failed: ${res.error ?? "unknown"}`] } };
    const row = JSON.parse(res.stdout) as Row;
    writeAtomic(paths(env.dir).meta(runId), JSON.stringify(row));
    return { row };
  } finally {
    l.release();
  }
}

export async function waitFor(env: Env, t: Target, o: { timeoutS: number }): Promise<Waited> {
  const regAt = env.now();
  const deadline = regAt + o.timeoutS;
  let id: number;
  let createdAt: number;
  if (t.kind === "run") {
    id = t.runId;
    const c = await createdOf(env, id, deadline);
    if ("fail" in c) return c.fail;
    if (c.row.status === "completed") return { code: verdict([c.row]), lines: [line(c.row)] };
    createdAt = epoch(c.row.createdAt);
  } else {
    id = sentinelId(t);
    createdAt = t.since;
  }
  const marker = addWaiter(env, id, createdAt);
  let poller: Lock | null = null;
  const cleanup = () => { poller?.release(); poller = null; dropWaiter(env, id, marker); };
  cleanups.add(cleanup);
  try {
    let nextAt = 0;
    for (;;) {
      const ev = evaluate(readStatus(env.dir), t, regAt);
      if ("done" in ev) return { code: verdict(ev.done), lines: ev.done.map(line) };
      if ("stopped" in ev) return { code: 3, lines: [`wait: the poller stopped (${ev.stopped}); see \`fw ci budget\`, \`fw ci budget --resume\``] };
      if (env.now() >= deadline) return { code: 3, lines: [`wait: timed out after ${o.timeoutS} s; run it again to keep waiting (\`fw ci budget\` shows the poller)`] };
      poller ??= tryLock(paths(env.dir).poller);
      let wake = env.now() + SLICE;
      if (poller && env.now() >= nextAt) {
        const p = await pollOnce(env);
        nextAt = p.wakeAt;
        if (p.ticked || p.stopped) continue; // re-read the file we just wrote
      }
      if (poller) wake = Math.min(wake, Math.max(nextAt, env.now() + 1));
      await env.sleepUntil(Math.min(wake, deadline));
    }
  } finally {
    cleanups.delete(cleanup);
    cleanup();
  }
}
