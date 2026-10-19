// The remote tier of a land (task land-wait): `fw land` pushes the merge commit to `ci/land-<task>-<sha7>`, the land lane of a CI
// provider runs the Lean-selected remote tier, and this file waits for it, normalizes each provider's run to a lane run record
// and lets fwcore decide (`console.landRemote`, Lean `Fw.Console.LandRemote.verdict`; golden land-remote.jsonl).
// No decision is made here: git, process and gh calls, JSON reading and timing spans only. The GitHub adapter is complete; the
// CircleCI adapter is a stub (follow-up after circleci-pilot lands scripts/circleci.mjs).
import { spawn } from "node:child_process";
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
export type GhRunView = { headSha: string; conclusion: string | null; status?: string; createdAt?: string; startedAt?: string; updatedAt?: string; jobs?: GhJob[] };
export const RUN_VIEW_FIELDS = "headSha,conclusion,status,createdAt,startedAt,updatedAt,jobs";

/** The sha and digest the lane bound itself to, from its `lane:` step name; null when no job reached that step. */
export function laneBind(view: GhRunView): { sha: string; digest: string } | null {
  for (const j of view.jobs ?? []) for (const s of j.steps ?? []) {
    const m = BIND_STEP.exec(s.name);
    if (m) return { sha: m[1]!, digest: m[2]! }; // BIND_STEP needs a 40-hex sha and a digest: the empty name of a lane that failed early binds nothing
  }
  return null;
}

/** `fw ci wait` exit code -> run state (0 pass, 1 fail, 3 the slice ran out with the run still going, 4 not run, else gh unavailable).
 *  Exit 3 also comes back at once when the poller is stopped or the gh budget refuses a call (gh-budget wait.ts); only the output
 *  `timed out after` means a run still going, any other exit 3 is `unavailable` (no tight poll loop, no retry on a refusal). */
export const stateOfWaitExit = (code: number, out = ""): RunState =>
  code === 0 ? "pass" : code === 1 ? "fail" : code === 3 ? (/timed out after/.test(out) ? "running" : "unavailable") : code === 4 ? "cancelled" : "unavailable";

/** Normalize one GitHub land run. A pass counts only for the sha and digest the lane printed; a lane that failed before it printed
 *  them is attributed to what was asked for (a failure refuses, the safe side), a pass without a binding binds to nothing. */
export function normalizeGithub(code: number, view: GhRunView | null, ctx: { marker: string; want: Want }, out = ""): LaneRun {
  const state = stateOfWaitExit(code, out);
  const run = (sha: string, laneDigest: string): LaneRun => ({ provider: "github", sha, laneId: LANE_ID, laneDigest, state });
  if (!view) return state === "pass" ? run("", "") : run(ctx.want.sha, ctx.want.laneDigest);
  const bind = view.headSha === ctx.marker ? laneBind(view) : null;
  if (bind) return run(bind.sha, bind.digest);
  if (state === "fail" && view.headSha === ctx.marker) return run(ctx.want.sha, ctx.want.laneDigest);
  if (state === "queued" || state === "running" || state === "cancelled" || state === "unavailable" || state === "timeout") return run(ctx.want.sha, ctx.want.laneDigest);
  return run("", "");
}

const ms = (t?: string): number | null => { const n = t ? Date.parse(t) : NaN; return Number.isFinite(n) ? n : null; };
/** Queue and lane durations of a finished run from its timestamps (null when GitHub did not report them). */
export function runTimes(view: GhRunView): { startMs: number; queueMs: number; laneMs: number } | null {
  const c = ms(view.createdAt), s = ms(view.startedAt), u = ms(view.updatedAt);
  return c !== null && s !== null && u !== null && s >= c && u >= s ? { startMs: c, queueMs: s - c, laneMs: u - s } : null;
}

// ---- adapters ------------------------------------------------------------------------------------------------------
export type Handle = { provider: Provider; branch: string; marker: string };
export type StartCtx = { task: string; mergeSha: string; want: Want };
export type Polled = { run: LaneRun; times?: { startMs: number; queueMs: number; laneMs: number } | null };
export interface Adapter {
  provider: Provider;
  /** Push the merge commit and start the lane; throws when the provider cannot be reached. */
  start(c: StartCtx): Promise<Handle>;
  /** One bounded wait (`sliceS` seconds); a run still going comes back `running`. */
  poll(h: Handle, c: StartCtx, sliceS: number, signal?: AbortSignal): Promise<Polled>;
}

export type GithubDeps = {
  git: (args: string[]) => string;
  /** Personal-data scan of the lines the push adds to origin (scripts/scrub.mjs --range): the text of the hits, or null when clean. */
  scan?: (mergeSha: string) => string | null;
  /** `pnpm -s fw ci wait ...`: exit code and output; ends early (code 3) when the signal aborts. */
  wait: (args: string[], signal?: AbortSignal) => Promise<{ code: number; out: string }>;
  gh: Gh;
};

/** The branch a merge commit is pushed to: unique per commit, so a re-land never needs a force push. */
export const landBranch = (task: string, mergeSha: string): string => `ci/land-${task.replace(/[^A-Za-z0-9._-]/g, "_")}-${mergeSha.slice(0, 7)}`;

export function githubAdapter(d: GithubDeps): Adapter {
  return {
    provider: "github",
    async start(c) {
      const hit = d.scan?.(c.mergeSha);
      if (hit) throw new Error(`personal-data scan refused the push of ${c.mergeSha.slice(0, 7)}: ${hit}`);
      const tree = d.git(["rev-parse", `${c.mergeSha}^{tree}`]);
      const marker = d.git(["commit-tree", tree, "-p", c.mergeSha, "-m", `[ci:land] land ${c.task} ${c.mergeSha.slice(0, 7)}`]);
      const branch = landBranch(c.task, c.mergeSha);
      d.git(["branch", "-f", branch, marker]);
      d.git(["push", "origin", branch]);
      return { provider: "github", branch, marker };
    },
    async poll(h, c, sliceS, signal) {
      const w = await d.wait(["-s", "fw", "ci", "wait", "--branch", h.branch, "--workflow", LANE_ID, "--sha", h.marker, "--timeout", String(sliceS)], signal);
      if (signal?.aborted) return { run: normalizeGithub(3, null, { marker: h.marker, want: c.want }, "timed out after abort"), times: null };
      const code = w.code;
      const id = /\brun (\d+) /.exec(w.out)?.[1];
      let view: GhRunView | null = null;
      if (id && (code === 0 || code === 1)) {
        try { view = JSON.parse(await d.gh(["run", "view", id, "--json", RUN_VIEW_FIELDS])) as GhRunView; } catch { view = null; }
      }
      return { run: normalizeGithub(code, view, { marker: h.marker, want: c.want }, w.out), times: view ? runTimes(view) : null };
    },
  };
}

/** The CircleCI adapter is a stub: always `unavailable`, with the reason in the thrown message. It becomes real after circleci-pilot lands
 *  scripts/circleci.mjs (follow-up); `onMain(path)` says whether a file is on main. */
export function circleciAdapter(onMain: (path: string) => boolean): Adapter {
  return {
    provider: "circleci",
    async start() {
      throw new Error(onMain("scripts/circleci.mjs") ? "the CircleCI adapter is not written yet (follow-up after circleci-pilot)" : "scripts/circleci.mjs is not on main (circleci-pilot has not landed)");
    },
    async poll() { throw new Error("the CircleCI adapter never starts a lane"); },
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
};

/** Run the Lean local tier here while the remote tier runs on the land lane; combine the two with `console.landRemote`.
 *  Returns the failure text (null: land may proceed) and its kind. Without a remote check nothing is pushed. */
export async function runTiered(p: TierPlan): Promise<{ bad: string | null; kind: string }> {
  const split = p.call({ op: "console.landTier", ids: p.checks.map((c) => c.id) }) as { local: string[]; remote: string[] };
  const argvOf = (ids: string[]) => p.checks.filter((c) => ids.includes(c.id)).map((c) => c.argv);
  const t0 = Date.now();
  const localP = (async () => {
    const r = await p.runLocal(argvOf(split.local));
    p.span("local tier", t0, Date.now() - t0, r.bad === null ? 0 : 1);
    return r;
  })();
  if (split.remote.length === 0) return localP;
  const want: Want = { sha: p.mergeSha, laneId: LANE_ID, laneDigest: remoteDigest(p.call, p.laneIds) };
  p.log(`remote: ${split.remote.length} remote checks (${split.remote.join(" ")}) wait on the ${p.allow.join("/")} land lane for ${p.mergeSha.slice(0, 7)}, digest ${want.laneDigest}`);
  const out = await awaitRemote({
    call: p.call, adapters: p.adapters, allow: p.allow, ctx: { task: p.task, mergeSha: p.mergeSha, want },
    local: localP.then((r) => r.bad === null), log: p.log, span: p.span, waitsLeft: p.waitsLeft, sliceS: p.sliceS, deadlineS: p.deadlineS,
  });
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
