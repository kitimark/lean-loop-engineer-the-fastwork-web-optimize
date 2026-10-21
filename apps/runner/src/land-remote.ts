// The remote tier of a land (task land-wait): `fw land` pushes the merge commit to `ci/land-<task>-<sha7>`, the land lane of a CI
// provider runs the Lean-selected remote tier, and this file waits for it, normalizes each provider's run to a lane run record
// and lets fwcore decide (`console.landRemote`, Lean `Fw.Console.LandRemote.verdict`; golden land-remote.jsonl).
// No decision is made here: git, process and gh calls, JSON reading and timing spans only. Both adapters are complete. GitHub comes
// first; when it has no free job slot the legs it cannot take go to CircleCI (task land-lane-circleci: Lean `Fw.Ci.Overflow`, ops
// `ci.overflow` and `ci.overflowCombine`; land-overflow.ts gathers the facts). Each provider's group is waited for on its own, with
// `allow` set to that provider, and the group verdicts are combined by fwcore.
import { spawn } from "node:child_process";
import { paths, readJson, readStatus, type RunFacts } from "@fw/gh-budget";
import type { FwCall, Gh } from "./run.ts";

export type Provider = "github" | "circleci";
export type RunState = "queued" | "running" | "pass" | "fail" | "cancelled" | "timeout" | "unavailable";
/** One lane run of one provider, bound to the commit and suite list it ran (Lean `Run`). */
export type LaneRun = { provider: Provider; sha: string; laneId: string; laneDigest: string; state: RunState };
export type Want = { sha: string; laneId: string; laneDigest: string };
export type RemoteVerdict = { kind: "accept" | "refuse" | "wait" | "try" | "local"; reason: string; ok: boolean; provider: Provider | null };

export const LANE_ID = "land";
/** The providers whose pass counts, in preference order, until circleci-pilot's routing rule feeds this list. */
export const DEFAULT_ALLOW: Provider[] = ["github"];
/** The step name the land lane prints after its suites: `lane: sha=<merge commit> digest=<lane digest>` (.github/workflows/land.yml). */
export const BIND_STEP = /^lane: sha=([0-9a-f]{40}) digest=(\S+)$/;

export type RemoteInput = { localOk: boolean; needed: boolean; allow: Provider[]; want: Want; waitsLeft: number; runs: LaneRun[] };

/** fwcore `console.landRemote`. */
export function remoteVerdict(call: FwCall, i: RemoteInput): RemoteVerdict {
  return call({ op: "console.landRemote", localOk: i.localOk, needed: i.needed, allow: i.allow, want: i.want, waitsLeft: i.waitsLeft, runs: i.runs }) as RemoteVerdict;
}

/** fwcore `console.landDigest`: the digest the lane prints for these remote check ids. */
export function remoteDigest(call: FwCall, ids: string[]): string {
  return (call({ op: "console.landDigest", ids }) as { digest: string }).digest;
}

// ---- GitHub: `gh run view --json ...` of the land run, normalized ------------------------------------------------------
export type GhStep = { name: string; conclusion?: string | null };
export type GhJob = { name: string; conclusion?: string | null; steps?: GhStep[] };
export type GhRunView = { workflowName?: string; headSha: string; conclusion: string | null; status?: string; createdAt?: string; startedAt?: string; updatedAt?: string; jobs?: GhJob[] };
export const RUN_VIEW_FIELDS = "workflowName,headSha,conclusion,status,createdAt,startedAt,updatedAt,jobs";

/** The sha and digest the lane bound itself to, from its `lane:` step name; null when no job reached that step. */
export function laneBind(view: GhRunView): { sha: string; digest: string } | null {
  for (const j of view.jobs ?? []) for (const s of j.steps ?? []) {
    const m = BIND_STEP.exec(s.name);
    if (m) return { sha: m[1]!, digest: m[2]! }; // BIND_STEP needs a 40-hex sha and a digest: the empty name of a lane that failed early binds nothing
  }
  return null;
}

/** fwcore `console.landLaneState` (Lean `Fw.Console.LandRemote.laneState`): the state of a lane run from the `fw ci wait` exit code (0 pass,
 *  1 fail, 3 the slice ran out with the run still going, 4 not run, else gh unavailable; exit 3 is `running` only when the output says
 *  `timed out after`) and the run's own status and conclusion. A run that completed with conclusion failure is `fail` whatever the exit
 *  code was: the waiter can say 2, 3 or 4 about a failed run (a refused or failed gh call for its jobs, a skipped guard). */
export function laneStateOf(call: FwCall, code: number, out = "", view: GhRunView | null = null): RunState {
  const state = (call({ op: "console.landLaneState", exit: code, timedOut: /timed out after/.test(out), status: view?.status ?? "", conclusion: view?.conclusion ?? "" }) as { state: RunState }).state;
  return state === "pass" && !legsPass(call, view) ? "fail" : state;
}

/** Does the run pass the verdict over the land lane's parallel legs? Lean decides (`Fw.Console.LandLegs.legsVeto`, op `console.landLegsVeto`);
 *  this only hands it the conclusions of the jobs but the guard, or `null` when the record has none (a job without a
 *  conclusion: the poller's cached facts), which Lean says does not veto. A job list that is empty is also no veto. */
export function legsPass(call: FwCall, view: GhRunView | null): boolean {
  const legs = (view?.jobs ?? []).filter((j) => j.name !== "guard");
  const results = legs.every((j) => typeof j.conclusion === "string") ? legs.map((j) => j.conclusion === "success") : null;
  return !(call({ op: "console.landLegsVeto", results }) as { veto: boolean }).veto;
}

/** Normalize one GitHub land run. A pass counts only for the sha and digest the lane printed; a lane that failed before it printed
 *  them is attributed to what was asked for (a failure refuses, the safe side), a pass without a binding binds to nothing. */
export function normalizeGithub(state: RunState, view: GhRunView | null, ctx: { marker: string; want: Want }): LaneRun {
  const run = (sha: string, laneDigest: string): LaneRun => ({ provider: "github", sha, laneId: LANE_ID, laneDigest, state });
  if (!view) return state === "pass" ? run("", "") : run(ctx.want.sha, ctx.want.laneDigest);
  const bind = view.headSha === ctx.marker ? laneBind(view) : null;
  if (bind) return run(bind.sha, bind.digest);
  if (state === "fail" && view.headSha === ctx.marker) return run(ctx.want.sha, ctx.want.laneDigest);
  if (state === "queued" || state === "running" || state === "cancelled" || state === "unavailable" || state === "timeout") return run(ctx.want.sha, ctx.want.laneDigest);
  return run("", "");
}

/** TS stand-in: a land that gave GitHub only some legs (`[legs:a,b]` in the marker) passes only if the run has a job for each of them.
 *  The matrix job of a leg is named `land (<leg>)`; the poller's cached record holds no such jobs, so it never covers. */
export function legsCovered(view: GhRunView | null, legs: string[]): boolean {
  const names = (view?.jobs ?? []).map((j) => j.name);
  return legs.every((l) => names.includes(`${LANE_ID} (${l})`));
}

const ms = (t?: string): number | null => { const n = t ? Date.parse(t) : NaN; return Number.isFinite(n) ? n : null; };
/** Queue and lane durations of a finished run from its timestamps (null when GitHub did not report them). */
export function runTimes(view: GhRunView): { startMs: number; queueMs: number; laneMs: number } | null {
  const c = ms(view.createdAt), s = ms(view.startedAt), u = ms(view.updatedAt);
  return c !== null && s !== null && u !== null && s >= c && u >= s ? { startMs: c, queueMs: s - c, laneMs: u - s } : null;
}

// ---- adapters ------------------------------------------------------------------------------------------------------
export type Handle = { provider: Provider; branch: string; marker: string; /** CircleCI: the pipeline the trigger started */ pipelineId?: string };
/** The legs of the land lane (lean/land-legs.txt) and the split of them between the providers (fwcore `ci.overflow`). */
export type LegSplit = { all: string[]; gh: string[]; cc: string[] };
/** `legs` is absent for a land that runs wholly on GitHub (the marker and the matrix are then what they always were). */
export type StartCtx = { task: string; mergeSha: string; want: Want; legs?: LegSplit };
export type Polled = { run: LaneRun; times?: { startMs: number; queueMs: number; laneMs: number } | null; /** why the land run record was not read (the waiter outcome stands) */ note?: string };
export interface Adapter {
  provider: Provider;
  /** Push the merge commit and start the lane; throws when the provider cannot be reached. */
  start(c: StartCtx): Promise<Handle>;
  /** One bounded wait (`sliceS` seconds); a run still going comes back `running`. */
  poll(h: Handle, c: StartCtx, sliceS: number, signal?: AbortSignal): Promise<Polled>;
}

export type GithubDeps = {
  git: (args: string[]) => string;
  /** fwcore, for the lane state (`console.landLaneState`). */
  call: FwCall;
  /** Personal-data scan of the lines the push adds to origin (scripts/scrub.mjs --range): the text of the hits, or null when clean. */
  scan?: (mergeSha: string) => string | null;
  /** `pnpm -s fw ci wait ...`: exit code and output; ends early (code 3) when the signal aborts. */
  wait: (args: string[], signal?: AbortSignal) => Promise<{ code: number; out: string }>;
  gh: Gh;
  /** The waiter's cached facts (gh-budget runs-status file and meta/<id>.jobs.json; they cost no budget) for the land run of this handle. */
  now?: () => number;
  cache?: (h: Handle, id?: string) => GhRunView | null;
};

/** The land run of a handle from the waiter's cached files: the newest completed row of the lane workflow on the lane branch and marker
 *  commit, with the steps of its cached jobs when the waiter wrote them. Null when the poller has no such row. */
export function cachedLaneView(dir: string, h: Handle, id?: string): GhRunView | null {
  const rows = (readStatus(dir)?.rows ?? []).filter((r) => r.workflowName === LANE_ID && r.headBranch === h.branch && r.headSha === h.marker && r.status === "completed" && (!id || String(r.databaseId) === id));
  const r = rows.sort((a, b) => b.databaseId - a.databaseId)[0];
  if (!r) return null;
  const f = readJson<RunFacts>(paths(dir).jobs(r.databaseId));
  const jobs: GhJob[] = f ? [{ name: "guard", steps: f.steps }, { name: "lane", steps: f.heavySteps ?? [] }] : [];
  return { workflowName: r.workflowName, headSha: r.headSha, conclusion: r.conclusion, status: r.status, createdAt: r.createdAt, jobs };
}

/** The branch a merge commit is pushed to: unique per commit, so a re-land never needs a force push. */
export const landBranch = (task: string, mergeSha: string): string => `ci/land-${task.replace(/[^A-Za-z0-9._-]/g, "_")}-${mergeSha.slice(0, 7)}`;

/** The message of the marker commit. `[ci:land]` starts the GitHub land lane, so a land whose legs all run on CircleCI leaves it out
 *  (GitHub then starts nothing); a land that gives GitHub only some legs says which in `[legs:a,b]`, which the guard of land.yml reads. */
export function markerMessage(c: StartCtx): string {
  const base = `land ${c.task} ${c.mergeSha.slice(0, 7)}`;
  const l = c.legs;
  if (!l) return `[ci:land] ${base}`;
  if (l.gh.length === 0) return base;
  return l.gh.length === l.all.length ? `[ci:land] ${base}` : `[ci:land] ${base} [legs:${l.gh.join(",")}]`;
}

/** Pushes the marker commit and the lane branch once per (merge commit, marker message); the providers of one land share the result,
 *  so both see one branch and one marker sha. A failed push stays failed for both. */
export type Pusher = (c: StartCtx) => Promise<{ branch: string; marker: string }>;
export function makePusher(d: Pick<GithubDeps, "git" | "scan">): Pusher {
  const memo = new Map<string, Promise<{ branch: string; marker: string }>>();
  return (c) => {
    const msg = markerMessage(c);
    const key = `${c.mergeSha}\n${msg}`;
    let p = memo.get(key);
    if (!p) {
      p = (async () => {
        const hit = d.scan?.(c.mergeSha);
        if (hit) throw new Error(`personal-data scan refused the push of ${c.mergeSha.slice(0, 7)}: ${hit}`);
        const tree = d.git(["rev-parse", `${c.mergeSha}^{tree}`]);
        const marker = d.git(["commit-tree", tree, "-p", c.mergeSha, "-m", msg]);
        const branch = landBranch(c.task, c.mergeSha);
        d.git(["branch", "-f", branch, marker]);
        d.git(["push", "origin", branch]);
        return { branch, marker };
      })();
      memo.set(key, p);
    }
    return p;
  };
}

export function githubAdapter(d: GithubDeps, push: Pusher = makePusher(d)): Adapter {
  return {
    provider: "github",
    async start(c) {
      const { branch, marker } = await push(c);
      return { provider: "github", branch, marker };
    },
    async poll(h, c, sliceS, signal) {
      const w = await d.wait(["-s", "fw", "ci", "wait", "--branch", h.branch, "--workflow", LANE_ID, "--sha", h.marker, "--timeout", String(sliceS)], signal);
      const norm = { marker: h.marker, want: c.want };
      const partial = !!c.legs && c.legs.gh.length < c.legs.all.length;
      if (signal?.aborted) return { run: normalizeGithub(laneStateOf(d.call, 3, "timed out after abort"), null, norm), times: null };
      // Whatever the waiter returned, read the run's own record unless it is plainly still going: the conclusion decides (Lean laneState).
      const going = w.code === 3 && /timed out after/.test(w.out);
      let view: GhRunView | null = null;
      let note: string | undefined;
      if (!going) {
        let id = /\brun (\d+)\b/.exec(w.out)?.[1];
        // Cached facts first (no budget): a completed failed record, or a record whose jobs show the bind, is enough.
        const hit = d.cache?.(h, id) ?? null;
        if (hit && (hit.conclusion === "failure" || (!partial && laneBind(hit)))) view = hit;
        else {
          const o = { deadline: Math.ceil((d.now?.() ?? Date.now()) / 1000 + sliceS), ...(signal ? { signal } : {}) };
          try {
            if (!id) { // exit 2/3/4 can come without a run id in the output: find the land run of the marker commit on the lane branch (never another workflow's)
              const rows = JSON.parse(await d.gh(["run", "list", "--workflow", LANE_ID, "--branch", h.branch, "--commit", h.marker, "--json", "databaseId", "--limit", "1"], o)) as { databaseId: number }[];
              id = rows[0] ? String(rows[0].databaseId) : undefined;
            }
            if (id) {
              const v = JSON.parse(await d.gh(["run", "view", id, "--json", RUN_VIEW_FIELDS], o)) as GhRunView;
              view = v.workflowName === LANE_ID ? v : null; // only the land workflow's own run decides
            }
          } catch (e) {
            view = hit; // budget or gh refused: the cached record (if any) stands; with none the waiter's outcome stands, logged
            note = `land run record not read (${e instanceof Error ? e.message : String(e)})`;
          }
        }
      }
      let state = laneStateOf(d.call, w.code, w.out, view);
      if (partial && state === "pass" && !legsCovered(view, c.legs!.gh)) { state = "fail"; note = `${note ? `${note}; ` : ""}the run has no job for every leg given to GitHub (${c.legs!.gh.join(",")})`; }
      return { run: normalizeGithub(state, view, norm), times: view ? runTimes(view) : null, ...(note ? { note } : {}) };
    },
  };
}

// ---- CircleCI: the land lane of .circleci/config.yml, one pipeline for the legs given to it --------------------------------
/** What a land job wrote (`lane.json`, .circleci/job.sh `land_suites`) plus its workflow's conclusion, as scripts/circleci.mjs `fetchPipeline` returns it. */
export type CircleLane = { job: string; conclusion: string; leg: string; sha: string; digest: string; engine: string; rc: number };
export type CircleFetch = { /** `vcs.revision` of the pipeline: the commit CircleCI checked out */ sha: string; lanes: CircleLane[]; times?: { queueMs: number; laneMs: number } | null };
export type CircleDeps = {
  call: FwCall;
  /** the marker commit and branch, shared with the GitHub adapter of the same land */
  push: Pusher;
  /** key check, then `POST /project/{slug}/pipeline/run` with lane=land and these legs; the pipeline id. Throws when CircleCI refuses. */
  trigger: (branch: string, legs: string[]) => Promise<string>;
  /** `waitPipeline`: exit 0 pass, 1 fail, 3 still going after `timeoutS`, 4 not run or cancelled, 5 the pilot stop rule; polls at 120 s or slower */
  wait: (pipelineId: string, timeoutS: number, signal?: AbortSignal) => Promise<number>;
  /** `fetchPipeline`: the lane records of the finished jobs */
  fetch: (pipelineId: string) => Promise<CircleFetch>;
  now?: () => number;
};

/** Normalize one CircleCI land pipeline, the way `normalizeGithub` does. A pass counts only when the pipeline ran the marker commit,
 *  every leg asked for has a lane record that passed (Lean `legsVeto` over those legs), and the records agree on one sha and one digest;
 *  Lean then compares that sha and digest with what was asked for. A failure is attributed to what was asked for (it refuses). */
export function normalizeCircle(call: FwCall, state: RunState, f: CircleFetch | null, ctx: { marker: string; want: Want; legs: string[] }): LaneRun {
  const run = (sha: string, laneDigest: string, st: RunState = state): LaneRun => ({ provider: "circleci", sha, laneId: LANE_ID, laneDigest, state: st });
  const asked = (st: RunState = state) => run(ctx.want.sha, ctx.want.laneDigest, st);
  if (state !== "pass" && state !== "fail") return asked();
  if (!f) return state === "pass" ? run("", "") : asked();
  const mine = ctx.legs.map((leg) => f.lanes.find((l) => l.leg === leg));
  const results = mine.map((l) => l !== undefined && l.rc === 0 && l.conclusion === "pass");
  const veto = results.length > 0 && (call({ op: "console.landLegsVeto", results }) as { veto: boolean }).veto;
  if (state === "fail" || veto) return asked("fail");
  const shas = new Set(mine.map((l) => l!.sha)), digests = new Set(mine.map((l) => l!.digest));
  if (f.sha !== ctx.marker || mine.length === 0 || shas.size !== 1 || digests.size !== 1) return run("", "");
  return run([...shas][0]!, [...digests][0]!);
}

export function circleciAdapter(d: CircleDeps): Adapter {
  return {
    provider: "circleci",
    async start(c) {
      const { branch, marker } = await d.push(c);
      const legs = c.legs?.cc ?? [];
      if (legs.length === 0) throw new Error("no leg is given to CircleCI");
      return { provider: "circleci", branch, marker, pipelineId: await d.trigger(branch, legs) };
    },
    async poll(h, c, sliceS, signal) {
      const id = h.pipelineId;
      if (!id) throw new Error("the CircleCI handle has no pipeline");
      const mk = (state: RunState): LaneRun => ({ provider: "circleci", sha: c.want.sha, laneId: LANE_ID, laneDigest: c.want.laneDigest, state });
      const code = await d.wait(id, sliceS, signal);
      const going = code === 3;
      // exit 3 is `running` only when the slice ran out (Lean laneState reads the output text for that)
      const state = signal?.aborted ? laneStateOf(d.call, 3, "timed out after abort") : laneStateOf(d.call, code, going ? "timed out after" : "");
      if (going || signal?.aborted || state === "unavailable" || state === "cancelled") return { run: mk(state) };
      let f: CircleFetch | null = null, note: string | undefined;
      try { f = await d.fetch(id); } catch (e) { note = `pipeline ${id} record not read (${e instanceof Error ? e.message : String(e)})`; }
      const t = f?.times;
      const end = (d.now ?? Date.now)();
      return { run: normalizeCircle(d.call, state, f, { marker: h.marker, want: c.want, legs: c.legs?.cc ?? [] }),
        times: t ? { startMs: end - t.queueMs - t.laneMs, queueMs: t.queueMs, laneMs: t.laneMs } : null, ...(note ? { note } : {}) };
    },
  };
}

// ---- the wait ---------------------------------------------------------------------------------------------------------
export type AwaitInput = {
  call: FwCall;
  adapters: Partial<Record<Provider, Adapter>>;
  allow: Provider[];
  ctx: StartCtx;
  /** the local tier's verdict (true = passed); a failure ends the wait and the land is refused */
  local: Promise<boolean>;
  log: (line: string) => void;
  /** record a timing span (steps `remote push`, `remote queue`, `remote lane`) */
  span: (step: string, startMs: number, durMs: number, exit: number | null) => void;
  now?: () => number;
  /** the lane's whole budget in seconds (land.yml timeout-minutes 45 plus queue) */
  deadlineS?: number;
  sliceS?: number;
  waitsLeft?: number;
};
export type AwaitOutcome = { verdict: RemoteVerdict; runs: LaneRun[] };

/** Sleep `ms` (nothing when <= 0); ends early when the signal aborts. A run that came back `running` sooner than its slice must not be polled at once. */
const sleepOut = (ms: number, signal: AbortSignal): Promise<void> => ms <= 0 ? Promise.resolve() : new Promise((res) => {
  const t = setTimeout(done, ms);
  function done() { clearTimeout(t); signal.removeEventListener("abort", done); res(); }
  signal.addEventListener("abort", done, { once: true });
});

/** Ask fwcore what to do with the runs so far and do it: start the provider it names, wait for runs going, stop on accept, refuse or
 *  local. The final verdict uses the real local tier result. */
export async function awaitRemote(i: AwaitInput): Promise<AwaitOutcome> {
  const now = i.now ?? Date.now;
  const deadline = now() + (i.deadlineS ?? 50 * 60) * 1000;
  const slice = i.sliceS ?? 540;
  const runs = new Map<string, LaneRun>();
  const attempted = new Set<Provider>();
  const handles = new Map<Provider, Handle>();
  const ac = new AbortController();
  let localOk: boolean | null = null;
  void i.local.then((ok) => { localOk = ok; if (!ok) ac.abort(); });
  let waits = i.waitsLeft ?? 0;
  const decide = (l: boolean): RemoteVerdict =>
    remoteVerdict(i.call, { localOk: l, needed: true, allow: i.allow, want: i.ctx.want, waitsLeft: waits, runs: [...runs.values()] });
  const mk = (provider: Provider, state: RunState): LaneRun => ({ provider, sha: i.ctx.want.sha, laneId: LANE_ID, laneDigest: i.ctx.want.laneDigest, state });
  for (;;) {
    const v = decide(localOk ?? true);
    if (v.kind === "accept" || v.kind === "refuse" || v.kind === "local" || ac.signal.aborted) break;
    if (v.kind === "try") {
      const p = v.provider!;
      if (attempted.has(p)) { // the lane of this provider ran something else: no second push, the provider counts as unavailable
        runs.set(`${p}:attempted`, mk(p, "unavailable"));
        i.log(`remote: ${p}: its lane run is not bound to ${i.ctx.want.sha.slice(0, 7)} and this digest; not pushing again`);
        continue;
      }
      attempted.add(p);
      const a = i.adapters[p];
      const t0 = now();
      try {
        if (!a) throw new Error(`no adapter for ${p}`);
        handles.set(p, await a.start(i.ctx));
        i.span("remote push", t0, now() - t0, 0);
        runs.set(p, mk(p, "queued"));
        i.log(`remote: ${p}: pushed ${handles.get(p)!.branch}; lane queued`);
      } catch (e) {
        i.span("remote push", t0, now() - t0, 1);
        runs.set(p, mk(p, "unavailable"));
        i.log(`remote: ${p}: unavailable: ${e instanceof Error ? e.message : String(e)}`);
      }
      continue;
    }
    // wait: poll the runs going, or (degraded) the unavailable ones once more
    const degraded = v.reason === "provider-degraded-waiting";
    if (degraded) waits--;
    const open = [...runs.values()].filter((r) => (degraded ? r.state === "unavailable" : r.state === "queued" || r.state === "running"));
    await Promise.all(open.map(async (r) => {
      const h = handles.get(r.provider), a = i.adapters[r.provider];
      if (!h || !a) return;
      try {
        const t1 = now();
        const p = await a.poll(h, i.ctx, slice, ac.signal);
        if (p.run.state === "running" && !ac.signal.aborted) await sleepOut(slice * 1000 - (now() - t1), ac.signal);
        runs.set(r.provider, p.run);
        if (p.note) i.log(`remote: ${r.provider}: ${p.note}`);
        if (p.times && p.run.state !== "running") {
          i.span("remote queue", p.times.startMs, p.times.queueMs, 0);
          i.span("remote lane", p.times.startMs + p.times.queueMs, p.times.laneMs, p.run.state === "pass" ? 0 : 1);
        }
        if (p.run.state === "running") i.log(`remote: ${r.provider}: lane still running`);
      } catch (e) {
        runs.set(r.provider, mk(r.provider, "unavailable"));
        i.log(`remote: ${r.provider}: unavailable: ${e instanceof Error ? e.message : String(e)}`);
      }
    }));
    if (now() >= deadline) for (const [p, r] of runs) if (r.state === "queued" || r.state === "running") runs.set(p, { ...r, state: "timeout" });
  }
  const ok = await i.local;
  return { verdict: decide(ok), runs: [...runs.values()] };
}

/** The overflow of one land: the legs of the lane and how the providers share them. `plan` is fwcore `ci.overflow` over the facts of this moment
 *  (land-overflow.ts); it returns null when the facts could not be gathered, which is the all-GitHub land. */
export type OverflowPlan = { legs: string[]; plan: () => Promise<{ gh: string[]; cc: string[]; reason: string; note?: string } | null> };

/** Wait for the legs of each provider as a group of its own (`allow` is that provider alone, so a group never borrows the other
 *  provider's run) and combine the group verdicts with fwcore `ci.overflowCombine` (Lean `Overflow.pickKind`: a refusal first, then
 *  local, then the first group that is not an accept, else accept). The verdict returned is the one of the first group of that kind. */
export async function awaitGroups(i: Omit<AwaitInput, "allow" | "ctx"> & { ctx: StartCtx; split: LegSplit }): Promise<AwaitOutcome> {
  const groups = ([["github", i.split.gh], ["circleci", i.split.cc]] as [Provider, string[]][]).filter(([, l]) => l.length > 0);
  const ctx: StartCtx = { ...i.ctx, legs: i.split };
  const outs = await Promise.all(groups.map(([provider]) => awaitRemote({ ...i, allow: [provider], ctx })));
  const kind = (i.call({ op: "ci.overflowCombine", kinds: outs.map((o) => o.verdict.kind) }) as { kind: string | null }).kind;
  const chosen = outs.find((o) => o.verdict.kind === kind) ?? outs[0]!;
  return { verdict: chosen.verdict, runs: outs.flatMap((o) => o.runs) };
}

/** `pnpm -s fw ci wait` as a child process: no CPU while it waits; the signal kills it. */
export function spawnWait(cwd: string): GithubDeps["wait"] {
  return (args, signal) => new Promise((res) => {
    const p = spawn("pnpm", args, { cwd, stdio: ["ignore", "pipe", "pipe"], detached: true }); // own process group: pnpm and the node child die together
    let out = "";
    p.stdout.on("data", (x) => (out += x)); p.stderr.on("data", (x) => (out += x));
    const stop = () => { try { process.kill(-p.pid!, "SIGTERM"); } catch { p.kill("SIGTERM"); } };
    signal?.addEventListener("abort", stop, { once: true });
    p.on("error", (e) => res({ code: 2, out: out + String(e) }));
    p.on("close", (code) => { signal?.removeEventListener("abort", stop); res({ code: code ?? 2, out }); });
  });
}

// ---- the tiered land checks --------------------------------------------------------------------------------------------
/** The fwcore build step of the local plan (Lean `LandTier.Step.build`). */
export const BUILD_ARGV = ["sh", "scripts/fwcore-build.sh"];
export type Local = (argv: string[][]) => Promise<{ bad: string | null; kind: string }>;
export type TierPlan = {
  call: FwCall;
  /** the checks the land selected, with ids */
  checks: { id: string; argv: string[] }[];
  /** the remote ids the lane will select for the merge commit (it has no digests, so it may select more than `checks`) */
  laneIds: string[];
  task: string;
  mergeSha: string;
  adapters: Partial<Record<Provider, Adapter>>;
  allow: Provider[];
  runLocal: Local;
  log: (line: string) => void;
  span: AwaitInput["span"];
  waitsLeft?: number;
  sliceS?: number;
  deadlineS?: number;
  /** a fwcore build already ran in the merge tree (phase 1) */
  built?: boolean;
  /** GitHub first, CircleCI for the legs GitHub has no slot for (absent: every leg on the allowed providers, as before) */
  overflow?: OverflowPlan;
};

/** Run the Lean local tier here while the remote tier runs on the land lane; combine the two with `console.landRemote`.
 *  Returns the failure text (null: land may proceed) and its kind. Without a remote check nothing is pushed. */
export async function runTiered(p: TierPlan): Promise<{ bad: string | null; kind: string }> {
  const split = p.call({ op: "console.landTier", ids: p.checks.map((c) => c.id), built: p.built ?? false }) as { local: string[]; remote: string[]; build: boolean };
  const argvOf = (ids: string[]) => p.checks.filter((c) => ids.includes(c.id)).map((c) => c.argv);
  // Lean `LandTier.localPlan`: the fwcore build first when a local check runs the binary and no build ran yet (`core_user_has_build`)
  const localArgv = () => (split.build ? [BUILD_ARGV, ...argvOf(split.local)] : argvOf(split.local));
  const t0 = Date.now();
  const localP = (async () => {
    const r = await p.runLocal(localArgv());
    p.span("local tier", t0, Date.now() - t0, r.bad === null ? 0 : 1);
    return r;
  })();
  if (split.remote.length === 0) return localP;
  const want: Want = { sha: p.mergeSha, laneId: LANE_ID, laneDigest: remoteDigest(p.call, p.laneIds) };
  p.log(`remote: ${split.remote.length} remote checks (${split.remote.join(" ")}) wait on the ${p.allow.join("/")} land lane for ${p.mergeSha.slice(0, 7)}, digest ${want.laneDigest}`);
  const plan = p.overflow ? await p.overflow.plan().catch((e: unknown) => { p.log(`remote: overflow plan not made (${e instanceof Error ? e.message : String(e)}); every leg on GitHub`); return null; }) : null;
  if (plan) p.log(`remote: overflow ${plan.reason}: GitHub ${plan.gh.join(",") || "none"}, CircleCI ${plan.cc.join(",") || "none"}${plan.note ? ` (${plan.note})` : ""}`);
  const base = { call: p.call, adapters: p.adapters, local: localP.then((r) => r.bad === null), log: p.log, span: p.span, waitsLeft: p.waitsLeft, sliceS: p.sliceS, deadlineS: p.deadlineS };
  const ctx: StartCtx = { task: p.task, mergeSha: p.mergeSha, want };
  const out = plan && plan.cc.length > 0
    ? await awaitGroups({ ...base, ctx, split: { all: p.overflow!.legs, gh: plan.gh, cc: plan.cc } })
    : await awaitRemote({ ...base, allow: p.allow, ctx });
  const local = await localP;
  const v = out.verdict;
  p.log(`remote: verdict ${v.kind} reason=${v.reason}${v.provider ? ` provider=${v.provider}` : ""}`);
  if (v.kind === "accept") return local;
  if (v.kind === "refuse" && v.reason === "local-tier-failed") return local;
  if (v.kind === "local") {
    p.log(`remote: running the remote tier on this Mac instead (${v.reason})`);
    const r = await p.runLocal(argvOf(split.remote));
    return local.bad !== null ? local : r;
  }
  const states = out.runs.map((r) => `${r.provider}:${r.state}`).join(" ") || "no run";
  const lane = v.reason === "remote-lane-failed" ? "the land lane failed" : `the land lane is undecided (${v.reason})`;
  const remoteBad = `remote tier: ${lane} for ${p.mergeSha.slice(0, 7)} (${states}); see the run on branch ${landBranch(p.task, p.mergeSha)}`;
  return { bad: local.bad ? `${local.bad}\n\n${remoteBad}` : remoteBad, kind: local.bad ? local.kind : "checks" };
}
