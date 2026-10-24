// `fw ci wait`: register a run (or a branch) with the budget state, then block on the local runs-status file. A waiter
// makes no GitHub call except one charged `gh run view` per run id nobody has seen yet, and one charged
// `gh run view --json jobs` per finished decisive run (both cached for everyone, under a per-run lock). The first waiter
// that wins `poller.lock` also runs the poller; when it leaves, another waiter takes over.
// The verdict is fwcore's (`ci.verdict`, lean/Fw/Ci/Verdict.lean): a run passes only when its guard decided to run, some
// other job ran and every job that ran succeeded; a run whose guard skipped is `not-run` (exit 4), never a pass, even
// though GitHub's run conclusion is `success` (task ci-own-trigger round 2). Round 3: a heavy job that stopped at its
// `stale:` step (a newer push is the tip) is `stale`, never a pass; `--branch` without `--workflow` waits for every lane
// the head commit requests, plus lean (fwcore `ci.required`), on that exact commit and passes only when each has a pass
// run (Lean `combine_requested_never_pass`; round 5: no skip stands in for a pass, lean included,
// `wait_needs_default_pass`). Round 4: a message that could not be read (`msg` null or absent) is an unknown request,
// and fwcore answers not-run at once (Lean `unknown_request_never_pass`); round 5: the message comes from git only.
import { mkdirSync, readdirSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import type { Env } from "./core.ts";
import { ghCharged } from "./charged.ts";
import { lockAsync, tryLock, type Lock } from "./lock.ts";
import { pollOnce, tickBudget, LIST_FIELDS } from "./poller.ts";
import { killOk, markerText } from "./waiters.ts";
import { dispatchOnly, selectOne, wanted, type WRun, type Want } from "./want.ts";
import { locked, paths, readJson, readStatus, stepEvent, stepUnlocked, writeAtomic, type Row, type Status } from "./state.ts";

export type Target =
  | { kind: "run"; runId: number }
  /** `since`: epoch second of the commit being waited for (runs created before it are not ours; for a dispatch want it is the poller's window, so a dispatch created before `since` is
   *  never read: pass an earlier `--since`). `msg`: the commit's
   *  message (null or absent: unknown); without `workflow` it selects the lanes mode (every requested lane on this sha). */
  | { kind: "branch"; branch: string; workflow?: string; sha: string; since: number; msg?: string | null;
      /** With `workflow`: the identity of the run waited for (Lean Fw.Ci.Dispatch.select): a push of `sha`, or a dispatch's nonce.
       *  Absent: the newest run of the workflow for the commit (legacy; `fw run`'s count and gate dispatches still use it). */
      want?: Want };

/** 0 pass, 1 fail, 2 a gh error, 3 timeout / budget stop, 4 not run (every decisive run's guard skipped). */
export type Waited = { code: 0 | 1 | 2 | 3 | 4; lines: string[] };

/** What one wait measured about its own latency (task ci-wait-lag), all epoch ms unless noted; written on the `fw ci wait`
 *  span. Fields in the order the run's finish travels: GitHub marks the run done (`updMs`, GitHub's `updatedAt`, whole
 *  seconds), the poller's list shows it completed (`tickMs`, whole seconds), this waiter reads the file (`readMs`),
 *  fetches the jobs (`readMs` to `viewEndMs`), fwcore decides (`doneMs`), the waiter's cleanup ends (`retMs`).
 *  `how`: done = a tick after this wait began showed the run completed (the only kind whose lag is the wait's own);
 *  late = the file already showed it when the wait began; already = the run was completed before the wait began;
 *  grace = a requested lane had no run and the missing-lane grace elapsed (lag by design); timeout; stopped. */
export type WaitPhases = {
  how: "done" | "late" | "already" | "grace" | "timeout" | "stopped";
  /** This process held poller.lock when it decided (it ran the tick itself). */
  holder: boolean;
  regMs: number;
  /** Ids of the runs the verdict covers. */
  runIds: number[];
  updMs?: number;
  prevTickMs?: number;
  tickMs?: number;
  pollS?: number;
  retryUntilS?: number;
  prevPollS?: number;
  readMs?: number;
  viewEndMs?: number;
  doneMs?: number;
  retMs: number;
  /** Charged `gh run view --json jobs` calls this wait made, jobs answered from the cache, ms waiting for the per-run lock, ms inside the charged calls. */
  views: number; cached: number; lockMs: number; ghMs: number;
  /** Passes of the wait loop. */
  loops: number;
};
export type WaitOpts = { timeoutS: number; nowMs?: () => number; phases?: (p: WaitPhases) => void };
type Probe = { ms: () => number; ph: WaitPhases };

/** Local re-read period of a waiter, seconds (file reads and lock checks only, no GitHub call); `slice` in limits.json. */
export const SLICE = 2;

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
    ...(g ? { guard: g.conclusion ?? "" } : {}),
    steps: (g?.steps ?? []).map((s) => ({ name: s.name, conclusion: s.conclusion })),
    jobs: heavy.map((j) => j.conclusion ?? ""), // an open job is "" as `gh` prints it; Lean reads a string
    heavySteps: heavy.flatMap((j) => (j.steps ?? []).map((s) => ({ name: s.name, conclusion: s.conclusion }))),
  };
}

/** Lanes mode: a branch target without `--workflow` (no message: the request is unknown, never a pass). */
const lanesMode = (t: Target): boolean => t.kind === "branch" && t.workflow === undefined;
const msgOf = (t: Target): string | null => (t.kind === "branch" ? t.msg ?? null : null);

const wrun = (r: Row): WRun => ({ id: r.databaseId, event: r.event ?? "", title: r.displayTitle ?? "", sha: r.headSha });

/** The hint of a push wait that selects no run while the workflow has only `workflow_dispatch` runs of the commit (Lean
 *  `Fw.Ci.Dispatch.dispatchOnly`), else null. */
export function hintOf(st: Status | null, t: Target): string | null {
  if (!st || t.kind !== "branch" || t.workflow === undefined || t.want?.kind !== "push") return null;
  const rows = st.rows.filter((r) => r.headBranch === t.branch && r.workflowName === t.workflow).map(wrun);
  return dispatchOnly(t.want, rows)
    ? `hint: ${t.workflow} has only workflow_dispatch runs of ${t.want.sha.slice(0, 7)}, no push run; to wait for a dispatch pass --nonce <n> (fw run prints it)`
    : null;
}

/** The ids of several runs that carry the nonce of a dispatch wait (Lean `Fw.Ci.Dispatch.selectOne` is `ambiguous`), else null.
 *  Two runs with one nonce cannot both be the dispatch's; the wait fails instead of taking the newest. */
export function ambiguousIds(rows: Row[], t: Target): number[] | null {
  if (t.kind !== "branch" || t.want?.kind !== "dispatch") return null;
  const mine = rows.filter((r) => r.headBranch === t.branch && (t.workflow === undefined || r.workflowName === t.workflow)).map(wrun);
  const one = selectOne(t.want, mine);
  return one.kind === "ambiguous" ? one.ids : null;
}

/** Which rows decide the wait: the run; in lanes mode the newest run of each workflow for the exact commit; else the
 *  newest run of the workflow on the branch for the exact commit, created after it. */
export function relevant(rows: Row[], t: Target): Row[] {
  if (t.kind === "run") return rows.filter((r) => r.databaseId === t.runId);
  if (ambiguousIds(rows, t)) return []; // several runs of one nonce decide nothing (Lean `selectOne`); the wait reports it
  const mine = lanesMode(t)
    ? rows.filter((r) => r.headBranch === t.branch && r.headSha.startsWith(t.sha))
    : t.want !== undefined
      // identity (Lean `Fw.Ci.Dispatch.select`): a push is its commit's push run; a dispatch is its nonce's run on any head sha
      // (`dispatch_any_sha`), so neither is cut by the sha or the time of the commit being waited for here. Which runs reach this
      // list at all is the poller's window (`createdSince` = the waiter's `since`): a dispatch created before `since` is not read
      ? rows.filter((r) => r.headBranch === t.branch && (t.workflow === undefined || r.workflowName === t.workflow) && wanted(t.want!, wrun(r)))
      : rows.filter((r) => r.headBranch === t.branch && r.headSha.startsWith(t.sha) && (t.workflow === undefined || r.workflowName === t.workflow) && epoch(r.createdAt) >= t.since);
  const newest = new Map<string, Row>();
  for (const r of mine) { const k = r.workflowName; if (!newest.has(k) || r.databaseId > newest.get(k)!.databaseId) newest.set(k, r); }
  return [...newest.values()];
}

/** Seconds after the newest run of a commit was created, all of them finished, before a requested lane with no run
 *  counts as missing (GitHub creates the runs of one push together: INFERRED). */
export const MISSING_GRACE_S = 300;

/** A verdict read found the run on a newer attempt: the rows said it finished, the run is running again. */
type Stale = { stale: { runId: number; attempt: number } };
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

/** What a jobs read gives: the facts, a failure, or `stale` (the run is on a newer attempt than the row said). */
type Jobs = { facts: RunFacts; bad?: string[] } | { fail: Waited } | { stale: { runId: number; attempt: number } };
/** The cached jobs of one run: the facts and the attempt they were read at; `bad`: the names of the jobs that did not succeed (display only). */
type JobsRec = { attempt?: number; facts: RunFacts; bad?: string[] };

/** Re-reads of a jobs view that shows jobs without a conclusion, and the pause between them (seconds). GitHub fills the
 *  conclusion of a matrix job a moment after the run is marked completed (Lean `Fw.Ci.Attempt.jobsSettled`). */
export const OPEN_REREADS = 6;
export const OPEN_PAUSE_S = 5;
/** The jobs that ended other than success or skipped (display only; the verdict is Lean's). */
const badJobs = (jobs: Job[]): string[] => jobs.filter((j) => j.conclusion !== "success" && j.conclusion !== "skipped" && j.conclusion !== "neutral").map((j) => j.name);
const openFacts = (f: RunFacts): boolean => f.jobs.some((c) => !c) || (f.guard !== undefined && !f.guard);

const freshRead = (env: Env, readAt: number | undefined): boolean => readAt !== undefined && env.core({ op: "ci.attempt", read: readAt, now: env.now() }).fresh === true;
const attemptOf = (env: Env, q: Record<string, unknown>, key: "reuse" | "settled" | "current" | "jobsSettled"): boolean => env.core({ op: "ci.attempt", ...q })[key] === true;

/** The facts of a finished run: one charged `gh run view <id> --json jobs,attempt`, cached in meta/<id>.jobs.json with the
 *  attempt it was read at (the cache answers only for that attempt, Lean `Fw.Ci.Attempt.reuse`), one call per run id and
 *  attempt however many waiters ask. A view on a newer attempt than the row is `stale`, not a verdict (`settled`). */
async function jobsOf(env: Env, row: Row, deadline: number, pr: Probe): Promise<Jobs> {
  const runId = row.databaseId;
  const file = paths(env.dir).jobs(runId);
  // a cache written with an open job (before this check existed) is read again
  const hit = (k: JobsRec | null): k is JobsRec => k !== null && !openFacts(k.facts) && attemptOf(env, { recorded: k.attempt ?? null, live: row.attempt ?? null }, "reuse");
  const k = readJson<JobsRec>(file);
  if (hit(k)) { pr.ph.cached++; return { facts: k.facts, ...(k.bad ? { bad: k.bad } : {}) }; }
  mkdirSync(join(env.dir, "meta"), { recursive: true });
  const t0 = pr.ms();
  const l = await lockAsync(paths(env.dir).jobsLock(runId), 120, env.now, env.sleepUntil);
  pr.ph.lockMs += pr.ms() - t0;
  try {
    const k2 = readJson<JobsRec>(file);
    if (hit(k2)) { pr.ph.cached++; return { facts: k2.facts, ...(k2.bad ? { bad: k2.bad } : {}) }; }
    for (let reread = 0; ; reread++) {
      const g0 = pr.ms();
      const res = await ghCharged(env, ["run", "view", String(runId), "--json", "jobs,attempt"], { cost: 3, block: true, deadline });
      pr.ph.ghMs += pr.ms() - g0;
      pr.ph.views++;
      if (!res.ran) return { fail: { code: 3, lines: [`wait: no gh call for the jobs of run ${runId}: ${res.decision} (${res.reason}); see \`fw ci budget\``] } };
      if (res.code !== 0) return { fail: { code: 2, lines: [`wait: gh run view ${runId} --json jobs failed: ${res.error ?? "unknown"}`] } };
      const v = JSON.parse(res.stdout) as { jobs?: Job[]; attempt?: number };
      const jobs = v.jobs ?? [];
      const rec: JobsRec = { ...(v.attempt === undefined ? {} : { attempt: v.attempt }), facts: factsOf(jobs), bad: badJobs(jobs) };
      // cache only a view that settles the row: a view of a newer, still running attempt must not become the verdict later
      if (v.attempt !== undefined && !attemptOf(env, { row: row.attempt ?? null, view: v.attempt }, "settled")) return { stale: { runId, attempt: v.attempt } };
      // a job without a conclusion right after the finish is GitHub's lag, not a failure (Lean `jobsSettled`): read again, never cache it
      const ago = row.updatedAt ? Math.max(0, env.now() - epoch(row.updatedAt)) : 0;
      const open = jobs.filter((j) => !j.conclusion).length;
      if (!attemptOf(env, { open, ago }, "jobsSettled")) {
        if (reread < OPEN_REREADS && env.now() + OPEN_PAUSE_S < deadline) { await env.sleepUntil(env.now() + OPEN_PAUSE_S); continue; }
        return { facts: rec.facts, bad: rec.bad! };
      }
      writeAtomic(file, JSON.stringify(rec));
      return { facts: rec.facts, bad: rec.bad! };
    }
  } finally {
    l.release();
  }
}

/** A `fail` verdict without a reason names the jobs that did not succeed (display only), so a fail is never a bare word. */
const failedNote = (verdict: string, bad: string[] | undefined): string =>
  verdict === "fail" && bad && bad.length > 0 ? ` (jobs not success: ${bad.slice(0, 6).join(", ")}${bad.length > 6 ? `, +${bad.length - 6}` : ""})` : "";

/** Lanes mode: the newest run of each requested lane for the commit, then fwcore `ci.verdict {msg, lanes}` decides
 *  (Lean `combineRequested`): a lane with no run is `missing`, never a pass. */
async function lanesVerdictOf(env: Env, msg: string | null, required: string[], rs: Row[], deadline: number, pr: Probe): Promise<Waited | Stale> {
  const lanes: Record<string, RunFacts | null> = {};
  const bads: Record<string, string[]> = {};
  for (const n of required) {
    const r = rs.find((x) => x.workflowName === n);
    if (!r) { lanes[n] = null; continue; }
    const f = await jobsOf(env, r, deadline, pr);
    if ("fail" in f) return f.fail;
    if ("stale" in f) return f;
    lanes[n] = f.facts;
    bads[n] = f.bad ?? [];
  }
  pr.ph.viewEndMs = pr.ms();
  const v = env.core({ op: "ci.verdict", msg, lanes });
  pr.ph.doneMs = pr.ms();
  const per = v.lanes as { name: string; verdict: string; code: number; reason: string }[];
  const lines = per.map((p) => {
    const r = rs.find((x) => x.workflowName === p.name);
    return `${r ? line(r) : `lane ${p.name} no run`} -> ${p.verdict}${p.reason ? ` (${p.reason})` : failedNote(p.verdict, bads[p.name])}`;
  });
  return { code: Number(v.code) as Waited["code"], lines: [...lines, `lanes ${required.join(",")} -> ${String(v.verdict)}`] };
}

/** The verdict of finished decisive runs: their jobs, then fwcore `ci.verdict` decides (Lean `Fw.Ci.Verdict`). */
async function verdictOf(env: Env, rs: Row[], deadline: number, pr: Probe): Promise<Waited | Stale> {
  const facts: RunFacts[] = [];
  const bads: string[][] = [];
  for (const r of rs) {
    const f = await jobsOf(env, r, deadline, pr);
    if ("fail" in f) return f.fail;
    if ("stale" in f) return f;
    facts.push(f.facts);
    bads.push(f.bad ?? []);
  }
  pr.ph.viewEndMs = pr.ms();
  const v = env.core({ op: "ci.verdict", runs: facts });
  pr.ph.doneMs = pr.ms();
  const per = v.runs as { verdict: string; code: number; reason: string }[];
  const lines = rs.map((r, i) => `${line(r)} -> ${per[i]!.verdict}${per[i]!.reason ? ` (${per[i]!.reason})` : failedNote(per[i]!.verdict, bads[i])}`);
  return { code: Number(v.code) as Waited["code"], lines };
}

// ---- registration with a refcount, so one waiter leaving does not unwatch a run another waiter still waits on ----------
const key = (id: number) => `r${id}`;

/** Register a waiter: its marker (pid and process start time) and the `register` event go in ONE locked block, and the
 *  poller reads the waiters dir under the same lock (`readMarkers`), so no sweep sees a watch without its marker. */
export function addWaiter(env: Env, id: number, createdAt: number): string {
  const dir = paths(env.dir).waiters;
  mkdirSync(dir, { recursive: true });
  const marker = join(dir, `${key(id)}.${process.pid}.${randomBytes(4).toString("hex")}`);
  locked(env, () => {
    writeFileSync(marker, markerText());
    stepUnlocked(env, { register: { runId: id, createdAt } });
  });
  return marker;
}

/** Leave a run: `unregister` goes first and the marker is unlinked after it, so a step that fails (lock timeout, killed
 *  fwcore) leaves the marker for a later sweep to reap, instead of a watch no marker points at. */
export function dropWaiter(env: Env, id: number, marker: string): void {
  const dir = paths(env.dir).waiters;
  locked(env, () => {
    const rest = readdirSync(dir).filter((n) => n.startsWith(`${key(id)}.`)).filter((n) => join(dir, n) !== marker).filter((n) => {
      if (killOk(Number(n.split(".")[1]))) return true; // a refcount shortcut by pid; `ci.budget.next` sweeps by identity
      try { unlinkSync(join(dir, n)); } catch { /* gone */ }
      return false;
    });
    if (rest.length === 0) stepUnlocked(env, { unregister: id });
    try { unlinkSync(marker); } catch { /* gone */ }
  });
}

/** Cleanups of waits in progress, run synchronously by a signal handler. */
export const cleanups = new Set<() => void>();

// ---- the bootstrap of a run id: its creation time, from the poller's list or one charged view (cached) -----------------
async function createdOf(env: Env, runId: number, deadline: number): Promise<{ row: Row } | { fail: Waited }> {
  // a finished row (in the poller's file or the meta cache) answers only while the view that read it is recent (Lean
  // `Fw.Ci.Attempt.fresh`): a later wait reads the run again, since a rerun may have started
  const fresh = (readAt: number | undefined): boolean => freshRead(env, readAt);
  const listed = (): Row | undefined => {
    const st = readStatus(env.dir);
    const r = st?.rows.find((x) => x.databaseId === runId);
    return r && (r.status !== "completed" || fresh(st?.tickAt ?? st?.at)) ? r : undefined;
  };
  const cached = (): Row | undefined => {
    const m = readJson<Row & { readAt?: number }>(paths(env.dir).meta(runId));
    return m && (m.status !== "completed" || fresh(m.readAt)) ? m : undefined;
  };
  const known = (): Row | undefined => listed() ?? cached();
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
    writeAtomic(paths(env.dir).meta(runId), JSON.stringify({ ...row, readAt: env.now() }));
    return { row };
  } finally {
    l.release();
  }
}

/** The kind of a deciding wait. TS stand-in replaying golden ci-budget/lag-kind.jsonl (Lean `Fw.Ci.Lag.kind`). */
export function waitKind(lanesMissing: boolean, tickMs: number | undefined, regMs: number): "done" | "late" | "grace" {
  if (lanesMissing) return "grace";
  return tickMs !== undefined && tickMs < regMs ? "late" : "done";
}

/** Index of the latest finish, the first on a tie, null for none. TS stand-in replaying golden ci-budget/lag-kind.jsonl (Lean `Fw.Ci.Lag.crit`). */
export function critIndex(upds: number[]): number | null {
  let best: number | null = null;
  upds.forEach((u, i) => { if (best === null || u > upds[best]!) best = i; });
  return best;
}

function noteDecided(pr: Probe, rows: Row[], st: Status | null, prev: Status | null, readMs: number, holder: boolean, required: string[] | null): void {
  const ph = pr.ph;
  ph.runIds = rows.map((r) => r.databaseId);
  ph.holder = holder;
  ph.readMs = readMs;
  const stamped = rows.filter((r) => r.updatedAt && Number.isFinite(Date.parse(r.updatedAt)));
  const ci = critIndex(stamped.map((r) => Date.parse(r.updatedAt!)));
  const crit = ci === null ? undefined : stamped[ci];
  if (crit) ph.updMs = Date.parse(crit.updatedAt!);
  if (st?.tickAt !== undefined) { ph.tickMs = st.tickAt * 1000; Object.assign(ph, tickBudget(st)); }
  const lanesMissing = required !== null && !required.every((n) => rows.some((r) => r.workflowName === n && r.status === "completed"));
  ph.how = waitKind(lanesMissing, ph.tickMs, ph.regMs);
  const before = crit ? prev?.rows.find((r) => r.databaseId === crit.databaseId) : undefined;
  if (before && before.status !== "completed" && prev?.tickAt !== undefined) {
    ph.prevTickMs = prev.tickAt * 1000;
    const q = tickBudget(prev).pollS;
    if (q !== undefined) ph.prevPollS = q;
  }
}

export async function waitFor(env: Env, t: Target, o: WaitOpts): Promise<Waited> {
  const ms = o.nowMs ?? (() => env.now() * 1000);
  const ph: WaitPhases = { how: "timeout", holder: false, regMs: ms(), runIds: [], retMs: 0, views: 0, cached: 0, lockMs: 0, ghMs: 0, loops: 0 };
  const w = await waitRun(env, t, o, { ms, ph });
  ph.retMs = ms();
  try { o.phases?.(ph); } catch { /* the measurement never fails a wait */ }
  return w;
}

async function waitRun(env: Env, t: Target, o: WaitOpts, pr: Probe): Promise<Waited> {
  const regAt = env.now();
  const deadline = regAt + o.timeoutS;
  const req = lanesMode(t) ? env.core({ op: "ci.required", msg: msgOf(t) }) : null;
  if (req && req.lanes === null) {
    const sha = t.kind === "branch" ? t.sha : "";
    return { code: Number(req.code) as Waited["code"], lines: [`lanes ? -> ${String(req.verdict)} (${String(req.reason)}; commit ${sha})`] };
  }
  const required = req ? ((req.lanes ?? []) as string[]) : null;
  const floor = new Map<number, number>(); // the newest attempt a jobs view showed, per run id (Lean `Fw.Ci.Attempt.current`)
  let id: number;
  let createdAt: number;
  if (t.kind === "run") {
    id = t.runId;
    const c = await createdOf(env, id, deadline);
    if ("fail" in c) return c.fail;
    if (c.row.status === "completed") {
      pr.ph.how = "already"; pr.ph.runIds = [c.row.databaseId]; pr.ph.readMs = pr.ms();
      if (c.row.updatedAt) pr.ph.updMs = Date.parse(c.row.updatedAt);
      const v = await verdictOf(env, [c.row], deadline, pr);
      if (!("stale" in v)) return v;
      pr.ph.how = "timeout"; // a rerun is running: wait for it like any other run
      floor.set(v.stale.runId, v.stale.attempt);
    }
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
    let cur: Status | null = null; // the newest list this waiter read, and the one before it (lag phases)
    let prev: Status | null = null;
    let reregAt = -1; // the tick at which this waiter last re-registered after a rerun
    for (;;) {
      pr.ph.loops++;
      const st = readStatus(env.dir);
      const readMs = pr.ms();
      if (st && st.tickAt !== undefined && st.tickAt !== cur?.tickAt) { prev = cur; cur = st; }
      let ev = evaluate(st, t, regAt, required, env.now());
      // a list read before this wait began may show a finished run that was rerun since: only a list from this wait's
      // time, or a recent one (Lean `fresh`), decides; the watch registered above brings the next tick
      if ("done" in ev && (st?.tickAt ?? st?.at ?? 0) < regAt && !freshRead(env, st?.tickAt ?? st?.at)) ev = { pending: true };
      if ("done" in ev && ev.done.every((r) => attemptOf(env, { floor: floor.get(r.databaseId) ?? 0, row: r.attempt ?? null }, "current"))) {
        noteDecided(pr, ev.done, st, prev, readMs, poller !== null, required);
        const v = required ? await lanesVerdictOf(env, msgOf(t), required, ev.done, deadline, pr) : await verdictOf(env, ev.done, deadline, pr);
        if (!("stale" in v)) return v;
        floor.set(v.stale.runId, v.stale.attempt);
      }
      if ("done" in ev && st?.tickAt !== undefined && st.tickAt !== reregAt) {
        // the rows say finished but a view showed a newer attempt: the poller dropped the watch on that finish, so watch again
        reregAt = st.tickAt;
        if (ev.done.some((r) => floor.has(r.databaseId))) stepEvent(env, { register: { runId: id, createdAt } }); // the watch this waiter owns
      }
      const amb = ambiguousIds(st?.rows ?? [], t);
      if (amb) { return { code: 2, lines: [`wait: nonce ${t.kind === "branch" && t.want?.kind === "dispatch" ? t.want.nonce : ""} matches several runs (${amb.join(", ")}); not guessing (Lean Fw.Ci.Dispatch.selectOne)`] }; }
      if ("stopped" in ev) { pr.ph.how = "stopped"; return { code: 3, lines: [`wait: the poller stopped (${ev.stopped}); see \`fw ci budget\`, \`fw ci budget --resume\``] }; }
      if (env.now() >= deadline) {
        const hint = hintOf(st, t);
        return { code: 3, lines: [`wait: timed out after ${o.timeoutS} s; run it again to keep waiting (\`fw ci budget\` shows the poller)`, ...(hint ? [hint] : [])] };
      }
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
