import { spawn } from "node:child_process";
import { paths, readJson, readStatus, type RunFacts } from "@fw/gh-budget";
import type { FwCall, Gh } from "./run.ts";

export type Provider = "github" | "circleci";
export type RunState = "queued" | "running" | "pass" | "fail" | "cancelled" | "timeout" | "unavailable";
export type LaneRun = { provider: Provider; sha: string; laneId: string; laneDigest: string; state: RunState };
export type Want = { sha: string; laneId: string; laneDigest: string };
export type RemoteVerdict = { kind: "accept" | "refuse" | "wait" | "try" | "local"; reason: string; ok: boolean; provider: Provider | null };

export const LANE_ID = "land";
export const DEFAULT_ALLOW: Provider[] = ["github"];
export const BIND_STEP = /^lane: sha=([0-9a-f]{40}) digest=(\S+)$/;

export type RemoteInput = { localOk: boolean; needed: boolean; allow: Provider[]; want: Want; waitsLeft: number; runs: LaneRun[] };

export function remoteVerdict(call: FwCall, i: RemoteInput): RemoteVerdict {
  return call({ op: "console.landRemote", localOk: i.localOk, needed: i.needed, allow: i.allow, want: i.want, waitsLeft: i.waitsLeft, runs: i.runs }) as RemoteVerdict;
}

export function remoteDigest(call: FwCall, ids: string[]): string {
  return (call({ op: "console.landDigest", ids }) as { digest: string }).digest;
}

export type GhStep = { name: string; conclusion?: string | null };
export type GhJob = { name: string; status?: string | null; conclusion?: string | null; steps?: GhStep[] };
export type GhRunView = { workflowName?: string; headSha: string; conclusion: string | null; status?: string; createdAt?: string; startedAt?: string; updatedAt?: string; jobs?: GhJob[] };
export const RUN_VIEW_FIELDS = "workflowName,headSha,conclusion,status,createdAt,startedAt,updatedAt,jobs";

export function laneBind(view: GhRunView): { sha: string; digest: string } | null {
  for (const j of view.jobs ?? []) for (const s of j.steps ?? []) {
    const m = BIND_STEP.exec(s.name);
    if (m) return { sha: m[1]!, digest: m[2]! };
  }
  return null;
}

export function laneRead(call: FwCall, code: number, out = "", view: GhRunView | null = null, reads = 0): { state: RunState; reread: boolean } {
  return call({ op: "console.landLaneState", exit: code, timedOut: /timed out after/.test(out), saidFail: SAID_FAIL.test(out), status: view?.status ?? "", conclusion: view?.conclusion ?? "", jobs: legRecords(view), reads }) as { state: RunState; reread: boolean };
}
export function laneStateOf(call: FwCall, code: number, out = "", view: GhRunView | null = null): RunState {
  return laneRead(call, code, out, view).state;
}
export const SAID_FAIL = /-> fail\b/;
export const WAIT_UNCOVERED = 6;

export type JobRecord = { status: string; conclusion: string };
export function legRecords(view: GhRunView | null): JobRecord[] | null {
  const legs = (view?.jobs ?? []).filter((j) => j.name !== "guard");
  return legs.every((j) => typeof j.status === "string") ? legs.map((j) => ({ status: j.status!, conclusion: j.conclusion ?? "" })) : null;
}

export function failureDetail(call: FwCall, id: string | undefined, view: GhRunView | null, checks: string[]): string {
  const jobs = (view?.jobs ?? []).filter((j) => j.name !== "guard");
  const states = (call({ op: "console.landLegStates", jobs: jobs.map((j) => ({ status: j.status ?? "", conclusion: j.conclusion ?? "" })) }) as { legs: string[] }).legs;
  const bad = jobs.filter((_, k) => states[k] === "fail");
  const legs = bad.map((j) => {
    const leg = /^land \((.+)\)$/.exec(j.name)?.[1];
    const ids = leg ? (call({ op: "console.landLeg", leg, ids: checks }) as { ids: string[] }).ids : [];
    return `${leg ?? j.name} ${j.conclusion}${ids.length ? ` [checks ${ids.join(" ")}]` : ""}`;
  });
  return `run ${id ?? "?"}${legs.length ? `, failed legs: ${legs.join("; ")}` : view ? ", no failed leg in the run record" : ", run record not read"}`;
}

export function legsPass(call: FwCall, view: GhRunView | null): boolean {
  const legs = (view?.jobs ?? []).filter((j) => j.name !== "guard");
  const results = legs.every((j) => typeof j.conclusion === "string") ? legs.map((j) => j.conclusion === "success") : null;
  return !(call({ op: "console.landLegsVeto", results }) as { veto: boolean }).veto;
}

export function normalizeGithub(state: RunState, view: GhRunView | null, ctx: { marker: string; want: Want }): LaneRun {
  const run = (sha: string, laneDigest: string): LaneRun => ({ provider: "github", sha, laneId: LANE_ID, laneDigest, state });
  if (!view) return state === "pass" ? run("", "") : run(ctx.want.sha, ctx.want.laneDigest);
  const bind = view.headSha === ctx.marker ? laneBind(view) : null;
  if (bind) return run(bind.sha, bind.digest);
  if (state === "fail" && view.headSha === ctx.marker) return run(ctx.want.sha, ctx.want.laneDigest);
  if (state === "queued" || state === "running" || state === "cancelled" || state === "unavailable" || state === "timeout") return run(ctx.want.sha, ctx.want.laneDigest);
  return run("", "");
}

export function legsCovered(view: GhRunView | null, legs: string[]): boolean {
  const names = (view?.jobs ?? []).map((j) => j.name);
  return legs.every((l) => names.includes(`${LANE_ID} (${l})`));
}

const ms = (t?: string): number | null => { const n = t ? Date.parse(t) : NaN; return Number.isFinite(n) ? n : null; };
export function runTimes(view: GhRunView): { startMs: number; queueMs: number; laneMs: number } | null {
  const c = ms(view.createdAt), s = ms(view.startedAt), u = ms(view.updatedAt);
  return c !== null && s !== null && u !== null && s >= c && u >= s ? { startMs: c, queueMs: s - c, laneMs: u - s } : null;
}

export type Handle = { provider: Provider; branch: string; marker: string; pipelineId?: string; reads?: number };
export type LegSplit = { all: string[]; gh: string[]; cc: string[] };
export type StartCtx = { task: string; mergeSha: string; want: Want; legs?: LegSplit; checks?: string[]; again?: boolean };
export type Polled = { run: LaneRun; times?: { startMs: number; queueMs: number; laneMs: number } | null; note?: string; detail?: string };
export interface Adapter {
  provider: Provider;
  start(c: StartCtx): Promise<Handle>;
  poll(h: Handle, c: StartCtx, sliceS: number, signal?: AbortSignal): Promise<Polled>;
}

export type GithubDeps = {
  git: (args: string[]) => string;
  call: FwCall;
  scan?: (mergeSha: string) => string | null;
  wait: (args: string[], signal?: AbortSignal) => Promise<{ code: number; out: string }>;
  gh: Gh;
  now?: () => number;
  cache?: (h: Handle, id?: string) => GhRunView | null;
};

export function cachedLaneView(dir: string, h: Handle, id?: string): GhRunView | null {
  const rows = (readStatus(dir)?.rows ?? []).filter((r) => r.workflowName === LANE_ID && r.headBranch === h.branch && r.headSha === h.marker && r.status === "completed" && (!id || String(r.databaseId) === id));
  const r = rows.sort((a, b) => b.databaseId - a.databaseId)[0];
  if (!r) return null;
  const f = readJson<RunFacts>(paths(dir).jobs(r.databaseId));
  const jobs: GhJob[] = f ? [{ name: "guard", steps: f.steps }, { name: "lane", steps: f.heavySteps ?? [] }] : [];
  return { workflowName: r.workflowName, headSha: r.headSha, conclusion: r.conclusion, status: r.status, createdAt: r.createdAt, jobs };
}

export const landBranch = (task: string, mergeSha: string, again = false): string => `ci/land-${task.replace(/[^A-Za-z0-9._-]/g, "_")}-${mergeSha.slice(0, 7)}${again ? "-again" : ""}`;

export function markerMessage(c: StartCtx): string {
  const base = `land ${c.task} ${c.mergeSha.slice(0, 7)}`;
  const l = c.legs;
  if (!l) return `[ci:land] ${base}`;
  if (l.gh.length === 0) return base;
  return l.gh.length === l.all.length ? `[ci:land] ${base}` : `[ci:land] ${base} [legs:${l.gh.join(",")}]`;
}

export type Pusher = (c: StartCtx) => Promise<{ branch: string; marker: string }>;
export function makePusher(d: Pick<GithubDeps, "git" | "scan">): Pusher {
  const memo = new Map<string, Promise<{ branch: string; marker: string }>>();
  return (c) => {
    const msg = markerMessage(c);
    const key = `${c.mergeSha}\n${c.again ? "again" : "first"}\n${msg}`;
    let p = memo.get(key);
    if (!p) {
      p = (async () => {
        const hit = d.scan?.(c.mergeSha);
        if (hit) throw new Error(`personal-data scan refused the push of ${c.mergeSha.slice(0, 7)}: ${hit}`);
        const tree = d.git(["rev-parse", `${c.mergeSha}^{tree}`]);
        const marker = d.git(["commit-tree", tree, "-p", c.mergeSha, "-m", msg]);
        const branch = landBranch(c.task, c.mergeSha, c.again);
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
      const going = w.code === 3 && /timed out after/.test(w.out);
      let view: GhRunView | null = null;
      let note: string | undefined;
      let id: string | undefined;
      if (!going) {
        id = /\brun (\d+)\b/.exec(w.out)?.[1];
        const uncovered = w.code === WAIT_UNCOVERED;
        if (uncovered) note = `run ${id ?? "?"}: the poller's list does not cover it (waiter exit ${WAIT_UNCOVERED}); its record is read with gh, the poller's file is not used`;
        const hit = uncovered ? null : d.cache?.(h, id) ?? null;
        if (hit && (hit.conclusion === "failure" || (!partial && laneBind(hit) && (w.code === 0 || legRecords(hit) !== null)))) view = hit;
        else {
          const o = { deadline: Math.ceil((d.now?.() ?? Date.now()) / 1000 + sliceS), ...(signal ? { signal } : {}) };
          try {
            if (!id) {
              const rows = JSON.parse(await d.gh(["run", "list", "--workflow", LANE_ID, "--branch", h.branch, "--commit", h.marker, "--json", "databaseId", "--limit", "1"], o)) as { databaseId: number }[];
              id = rows[0] ? String(rows[0].databaseId) : undefined;
            }
            if (id) {
              const v = JSON.parse(await d.gh(["run", "view", id, "--json", RUN_VIEW_FIELDS], o)) as GhRunView;
              view = v.workflowName === LANE_ID ? v : null;
            }
          } catch (e) {
            view = hit;
            note = `${note ? `${note}; ` : ""}land run record not read (${e instanceof Error ? e.message : String(e)})`;
          }
        }
      }
      const read = laneRead(d.call, w.code, w.out, view, h.reads ?? 0);
      let state = read.state;
      if (read.reread) { h.reads = (h.reads ?? 0) + 1; note = `${note ? `${note}; ` : ""}run ${id ?? "?"} completed with a leg GitHub has not finalised (read ${h.reads})${state === "running" ? "; the record is read again after this slice" : "; the reads are used up, the run counts as unavailable"}`; }
      if (partial && state === "pass" && !legsCovered(view, c.legs!.gh)) { state = "fail"; note = `${note ? `${note}; ` : ""}the run has no job for every leg given to GitHub (${c.legs!.gh.join(",")})`; }
      let detail: string | undefined;
      if (state === "fail") {
        let dv = view;
        if (id && legRecords(view) === null) {
          try { const v = JSON.parse(await d.gh(["run", "view", id, "--json", RUN_VIEW_FIELDS], { deadline: Math.ceil((d.now?.() ?? Date.now()) / 1000 + sliceS), ...(signal ? { signal } : {}) })) as GhRunView; if (v.workflowName === LANE_ID) dv = v; } catch {}
        }
        detail = failureDetail(d.call, id, dv, c.checks ?? []);
      }
      return { run: normalizeGithub(state, view, norm), times: view ? runTimes(view) : null, ...(note ? { note } : {}), ...(detail ? { detail } : {}) };
    },
  };
}

export type CircleLane = { job: string; conclusion: string; leg: string; sha: string; digest: string; engine: string; rc: number };
export type CircleFetch = { sha: string; lanes: CircleLane[]; times?: { queueMs: number; laneMs: number } | null };
export type CircleDeps = {
  call: FwCall;
  push: Pusher;
  trigger: (branch: string, legs: string[]) => Promise<string>;
  wait: (pipelineId: string, timeoutS: number, signal?: AbortSignal) => Promise<number>;
  fetch: (pipelineId: string) => Promise<CircleFetch>;
  now?: () => number;
};

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
      const state = signal?.aborted ? laneStateOf(d.call, 3, "timed out after abort") : laneStateOf(d.call, code, going ? "timed out after" : code === 1 ? "-> fail (the pipeline failed)" : "");
      if (going || signal?.aborted || state === "unavailable" || state === "cancelled") return { run: mk(state) };
      let f: CircleFetch | null = null, note: string | undefined;
      try { f = await d.fetch(id); } catch (e) { note = `pipeline ${id} record not read (${e instanceof Error ? e.message : String(e)})`; }
      const t = f?.times;
      const end = (d.now ?? Date.now)();
      const run = normalizeCircle(d.call, state, f, { marker: h.marker, want: c.want, legs: c.legs?.cc ?? [] });
      let detail: string | undefined;
      if (run.state === "fail") {
        const failed = (c.legs?.cc ?? []).filter((leg) => !f?.lanes.some((l) => l.leg === leg && l.rc === 0 && l.conclusion === "pass")).map((leg) => {
          const ids = (d.call({ op: "console.landLeg", leg, ids: c.checks ?? [] }) as { ids: string[] }).ids;
          return `${leg}${ids.length ? ` [checks ${ids.join(" ")}]` : ""}`;
        });
        detail = `pipeline ${id}, failed legs: ${failed.join("; ") || "none named"}`;
      }
      return { run, ...(detail ? { detail } : {}),
        times: t ? { startMs: end - t.queueMs - t.laneMs, queueMs: t.queueMs, laneMs: t.laneMs } : null, ...(note ? { note } : {}) };
    },
  };
}

export type AwaitInput = {
  call: FwCall;
  adapters: Partial<Record<Provider, Adapter>>;
  allow: Provider[];
  ctx: StartCtx;
  local: Promise<boolean>;
  log: (line: string) => void;
  span: (step: string, startMs: number, durMs: number, exit: number | null) => void;
  now?: () => number;
  deadlineS?: number;
  sliceS?: number;
  waitsLeft?: number;
};
export type AwaitOutcome = { verdict: RemoteVerdict; runs: LaneRun[]; startFailed: Provider[]; details: string[] };

const sleepOut = (ms: number, signal: AbortSignal): Promise<void> => ms <= 0 ? Promise.resolve() : new Promise((res) => {
  const t = setTimeout(done, ms);
  function done() { clearTimeout(t); signal.removeEventListener("abort", done); res(); }
  signal.addEventListener("abort", done, { once: true });
});

export async function awaitRemote(i: AwaitInput): Promise<AwaitOutcome> {
  const now = i.now ?? Date.now;
  const deadline = now() + (i.deadlineS ?? 50 * 60) * 1000;
  const slice = i.sliceS ?? 540;
  const runs = new Map<string, LaneRun>();
  const attempted = new Set<Provider>();
  const startFailed: Provider[] = [];
  const details = new Map<Provider, string>();
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
      if (attempted.has(p)) {
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
        startFailed.push(p);
        runs.set(p, mk(p, "unavailable"));
        i.log(`remote: ${p}: unavailable: ${e instanceof Error ? e.message : String(e)}`);
      }
      continue;
    }
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
        if (p.detail) details.set(r.provider, `${r.provider}: ${p.detail}`);
        else details.delete(r.provider);
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
  return { verdict: decide(ok), runs: [...runs.values()], startFailed, details: [...details.values()] };
}

export type OverflowPlan = { legs: string[]; plan: () => Promise<{ gh: string[]; cc: string[]; reason: string; note?: string } | null> };

export async function awaitGroups(i: Omit<AwaitInput, "allow" | "ctx"> & { ctx: StartCtx; split: LegSplit }): Promise<AwaitOutcome> {
  const ctx: StartCtx = { ...i.ctx, legs: i.split };
  let again: Promise<AwaitOutcome> | null = null;
  const cc = i.adapters.circleci;
  const onFail = () => {
    if (again) return;
    const st = i.call({ op: "ci.overflowSettle", gh: i.split.gh, cc: i.split.cc, ccStarted: false }) as { again: string[] };
    if (st.again.length === 0) return;
    i.log(`remote: CircleCI could not start; its legs ${st.again.join(",")} run on GitHub`);
    again = awaitRemote({ ...i, allow: ["github"], ctx: { ...i.ctx, legs: { all: i.split.all, gh: st.again, cc: [] }, again: true } });
    again.catch(() => {});
  };
  const adapters: AwaitInput["adapters"] = { ...i.adapters };
  adapters.circleci = {
    provider: "circleci",
    start: async (c) => { try { if (!cc) throw new Error("no adapter for circleci"); return await cc.start(c); } catch (e) { onFail(); throw e; } },
    poll: (h, c, sliceS, signal) => cc!.poll(h, c, sliceS, signal),
  };
  const groups = ([["github", i.split.gh], ["circleci", i.split.cc]] as [Provider, string[]][]).filter(([, l]) => l.length > 0);
  const outs = await Promise.all(groups.map(async ([provider]) => ({ provider, out: await awaitRemote({ ...i, adapters, allow: [provider], ctx }) })));
  const second = again ? await (again as Promise<AwaitOutcome>) : null;
  const judged = [...outs.filter((o) => !(o.provider === "circleci" && second)).map((o) => o.out), ...(second ? [second] : [])];
  const kind = (i.call({ op: "ci.overflowCombine", kinds: judged.map((o) => o.verdict.kind) }) as { kind: string | null }).kind;
  const chosen = judged.find((o) => o.verdict.kind === kind) ?? judged[0]!;
  return { verdict: chosen.verdict, runs: [...outs.flatMap((o) => o.out.runs), ...(second ? second.runs : [])], startFailed: outs.flatMap((o) => o.out.startFailed), details: [...outs.flatMap((o) => o.out.details), ...(second ? second.details : [])] };
}

export function spawnWait(cwd: string): GithubDeps["wait"] {
  return (args, signal) => new Promise((res) => {
    const p = spawn("pnpm", args, { cwd, stdio: ["ignore", "pipe", "pipe"], detached: true });
    let out = "";
    p.stdout.on("data", (x) => (out += x)); p.stderr.on("data", (x) => (out += x));
    const stop = () => { try { process.kill(-p.pid!, "SIGTERM"); } catch { p.kill("SIGTERM"); } };
    signal?.addEventListener("abort", stop, { once: true });
    p.on("error", (e) => res({ code: 2, out: out + String(e) }));
    p.on("close", (code) => { signal?.removeEventListener("abort", stop); res({ code: code ?? 2, out }); });
  });
}

export const BUILD_ARGV = ["sh", "scripts/fwcore-build.sh"];
export type Local = (argv: string[][]) => Promise<{ bad: string | null; kind: string }>;
export type TierPlan = {
  call: FwCall;
  checks: { id: string; argv: string[] }[];
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
  built?: boolean;
  overflow?: OverflowPlan;
};

export async function runTiered(p: TierPlan): Promise<{ bad: string | null; kind: string }> {
  const split = p.call({ op: "console.landTier", ids: p.checks.map((c) => c.id), built: p.built ?? false }) as { local: string[]; remote: string[]; build: boolean };
  const argvOf = (ids: string[]) => p.checks.filter((c) => ids.includes(c.id)).map((c) => c.argv);
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
  const ctx: StartCtx = { task: p.task, mergeSha: p.mergeSha, want, checks: split.remote };
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
  const named = out.details.length ? ` [${out.details.join(" | ")}]` : "";
  const remoteBad = `remote tier: ${lane} for ${p.mergeSha.slice(0, 7)} (${states})${named}; see the run on branch ${landBranch(p.task, p.mergeSha)}`;
  return { bad: local.bad ? `${local.bad}\n\n${remoteBad}` : remoteBad, kind: local.bad ? local.kind : "checks" };
}
