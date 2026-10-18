// `fw ci wait`: register a run (or a branch) with the budget state, then block on the local runs-status file. A waiter
// makes no GitHub call except one charged `gh run view` per run id nobody has seen yet, and one charged
// `gh run view --json jobs` per finished decisive run (both cached for everyone, under a per-run lock). The first waiter
// that wins `poller.lock` also runs the poller; when it leaves, another waiter takes over.
// The verdict is fwcore's (`ci.verdict`, lean/Fw/Ci/Verdict.lean): a run passes only when its guard decided to run, some
// other job ran and every job that ran succeeded; a run whose guard skipped is `not-run` (exit 4), never a pass, even
// though GitHub's run conclusion is `success` (task ci-own-trigger round 2). Round 3: a heavy job that stopped at its
// `stale:` step (a newer push is the tip) is `stale`, never a pass; `--branch` without `--workflow` waits for every lane
// the head commit requests (fwcore `ci.required`) on that exact commit and passes only when each has a pass run (a
// default lane may also be skipped as unchanged; Lean `combine_requested_never_pass`).
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
  /** `since`: epoch second of the commit being waited for (runs created before it are not ours). `msg`: the commit's
   *  message; without `workflow` it selects the lanes mode (every requested lane on this sha). */
  | { kind: "branch"; branch: string; workflow?: string; sha: string; since: number; msg?: string };

/** 0 pass, 1 fail, 2 a gh error, 3 timeout / budget stop, 4 not run (every decisive run's guard skipped). */
export type Waited = { code: 0 | 1 | 2 | 3 | 4; lines: string[] };

/** Local re-read period of a waiter, seconds (file reads and lock checks only, no GitHub call). */
const SLICE = 2;

const epoch = (iso: string) => Math.floor(Date.parse(iso) / 1000);
const fnv = (s: string) => { let h = 0x811c9dc5; for (const c of s) { h ^= c.charCodeAt(0); h = Math.imul(h, 0x01000193) >>> 0; } return h; };
/** Watch id for a branch waiter: far above real run ids, stable per (branch, workflow, sha). */
export const sentinelId = (t: { branch: string; workflow?: string; sha: string }) => 1_000_000_000_000_000 + fnv(`${t.branch}\n${t.workflow ?? ""}\n${t.sha}`);

const line = (r: Row) => `run ${r.databaseId} ${r.workflowName || "-"} ${r.conclusion ?? r.status}`;

/** One job of `gh run view --json jobs` (the fields the verdict reads). */
type Job = { name: string; conclusion: string | null; steps?: { name: string; conclusion: string | null }[] };
type Step = { name: string; conclusion: string | null };
/** The facts of one run for `ci.verdict`: the guard job (absent: the workflow has none), its steps, the other jobs and
 *  their steps (`heavySteps`: a `stale:` step that failed makes the run `stale`, Lean `Fw.Ci.Verdict.staleOf`). */
export type RunFacts = { guard?: string | null; steps: Step[]; jobs: (string | null)[]; heavySteps?: Step[] };

/** The jobs of a finished run as `ci.verdict` facts (no decision: the guard is the job named `guard`). */
export function factsOf(jobs: Job[]): RunFacts {
  const g = jobs.find((j) => j.name === "guard");
  const heavy = jobs.filter((j) => j !== g);
  return {
    ...(g ? { guard: g.conclusion } : {}),
    steps: (g?.steps ?? []).map((s) => ({ name: s.name, conclusion: s.conclusion })),
    jobs: heavy.map((j) => j.conclusion),
    heavySteps: heavy.flatMap((j) => (j.steps ?? []).map((s) => ({ name: s.name, conclusion: s.conclusion }))),
  };
}

/** Lanes mode: a branch target without `--workflow` (no message: only the default lanes are requested). */
const lanesMode = (t: Target): boolean => t.kind === "branch" && t.workflow === undefined;
const msgOf = (t: Target): string => (t.kind === "branch" ? t.msg ?? "" : "");

/** Which rows decide the wait: the run; in lanes mode the newest run of each workflow for the exact commit; else the
 *  newest run of the workflow on the branch created after the commit. */
export function relevant(rows: Row[], t: Target): Row[] {
  if (t.kind === "run") return rows.filter((r) => r.databaseId === t.runId);
  const mine = lanesMode(t)
    ? rows.filter((r) => r.headBranch === t.branch && r.headSha.startsWith(t.sha))
    : rows.filter((r) => r.headBranch === t.branch && (t.workflow === undefined || r.workflowName === t.workflow) && epoch(r.createdAt) >= t.since);
  const newest = new Map<string, Row>();
  for (const r of mine) { const k = r.workflowName; if (!newest.has(k) || r.databaseId > newest.get(k)!.databaseId) newest.set(k, r); }
  return [...newest.values()];
}

/** Seconds after the newest run of a commit was created, all of them finished, before a requested lane with no run
 *  counts as missing (GitHub creates the runs of one push together: INFERRED). */
export const MISSING_GRACE_S = 300;

type Eval = { done: Row[] } | { stopped: string } | { pending: true };
/** `required`: in lanes mode, the lanes the commit requests (done when each has a finished run, or when every run of the
 *  commit finished `MISSING_GRACE_S` ago; the absent lanes are then `missing`). */
export function evaluate(st: Status | null, t: Target, regAt: number, required: string[] | null = null, now = 0): Eval {
  if (!st) return { pending: true };
  const rs = relevant(st.rows, t);
  const finished = rs.length > 0 && rs.every((r) => r.status === "completed");
  if (required) {
    const done = (n: string) => rs.some((r) => r.workflowName === n && r.status === "completed");
    if (required.every(done)) return { done: rs.filter((r) => required.includes(r.workflowName)) };
    if (finished && now - Math.max(...rs.map((r) => epoch(r.createdAt))) >= MISSING_GRACE_S) return { done: rs.filter((r) => required.includes(r.workflowName)) };
  } else if (finished) return { done: rs };
  if (st.stopped && (st.stoppedAt ?? 0) >= regAt) return { stopped: st.stopped };
  return { pending: true };
}

/** The facts of a finished run: one charged `gh run view <id> --json jobs`, cached in meta/<id>.jobs.json (a finished
 *  run's jobs never change), one call per run id however many waiters ask. */
async function jobsOf(env: Env, runId: number, deadline: number): Promise<{ facts: RunFacts } | { fail: Waited }> {
  const file = paths(env.dir).jobs(runId);
  const k = readJson<RunFacts>(file);
  if (k) return { facts: k };
  mkdirSync(join(env.dir, "meta"), { recursive: true });
  const l = await lockAsync(paths(env.dir).jobsLock(runId), 120, env.now, env.sleepUntil);
  try {
    const k2 = readJson<RunFacts>(file);
    if (k2) return { facts: k2 };
    const res = await ghCharged(env, ["run", "view", String(runId), "--json", "jobs"], { cost: 3, block: true, deadline });
    if (!res.ran) return { fail: { code: 3, lines: [`wait: no gh call for the jobs of run ${runId}: ${res.decision} (${res.reason}); see \`fw ci budget\``] } };
    if (res.code !== 0) return { fail: { code: 2, lines: [`wait: gh run view ${runId} --json jobs failed: ${res.error ?? "unknown"}`] } };
    const facts = factsOf((JSON.parse(res.stdout) as { jobs: Job[] }).jobs ?? []);
    writeAtomic(file, JSON.stringify(facts));
    return { facts };
  } finally {
    l.release();
  }
}

/** Lanes mode: the newest run of each requested lane for the commit, then fwcore `ci.verdict {msg, lanes}` decides
 *  (Lean `combineRequested`): a lane with no run is `missing`, never a pass. */
async function lanesVerdictOf(env: Env, msg: string, required: string[], rs: Row[], deadline: number): Promise<Waited> {
  const lanes: Record<string, RunFacts | null> = {};
  for (const n of required) {
    const r = rs.find((x) => x.workflowName === n);
    if (!r) { lanes[n] = null; continue; }
    const f = await jobsOf(env, r.databaseId, deadline);
    if ("fail" in f) return f.fail;
    lanes[n] = f.facts;
  }
  const v = env.core({ op: "ci.verdict", msg, lanes });
  const per = v.lanes as { name: string; verdict: string; code: number; reason: string }[];
  const lines = per.map((p) => {
    const r = rs.find((x) => x.workflowName === p.name);
    return `${r ? line(r) : `lane ${p.name} no run`} -> ${p.verdict}${p.reason ? ` (${p.reason})` : ""}`;
  });
  return { code: Number(v.code) as Waited["code"], lines: [...lines, `lanes ${required.join(",")} -> ${String(v.verdict)}`] };
}

/** The verdict of finished decisive runs: their jobs, then fwcore `ci.verdict` decides (Lean `Fw.Ci.Verdict`). */
async function verdictOf(env: Env, rs: Row[], deadline: number): Promise<Waited> {
  const facts: RunFacts[] = [];
  for (const r of rs) {
    const f = await jobsOf(env, r.databaseId, deadline);
    if ("fail" in f) return f.fail;
    facts.push(f.facts);
  }
  const v = env.core({ op: "ci.verdict", runs: facts });
  const per = v.runs as { verdict: string; code: number; reason: string }[];
  const lines = rs.map((r, i) => `${line(r)} -> ${per[i]!.verdict}${per[i]!.reason ? ` (${per[i]!.reason})` : ""}`);
  return { code: Number(v.code) as Waited["code"], lines };
}

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
  const required = lanesMode(t) ? ((env.core({ op: "ci.required", msg: msgOf(t) }).lanes ?? []) as string[]) : null;
  let id: number;
  let createdAt: number;
  if (t.kind === "run") {
    id = t.runId;
    const c = await createdOf(env, id, deadline);
    if ("fail" in c) return c.fail;
    if (c.row.status === "completed") return await verdictOf(env, [c.row], deadline);
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
      const ev = evaluate(readStatus(env.dir), t, regAt, required, env.now());
      if ("done" in ev) return required ? await lanesVerdictOf(env, msgOf(t),required, ev.done, deadline) : await verdictOf(env, ev.done, deadline);
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
