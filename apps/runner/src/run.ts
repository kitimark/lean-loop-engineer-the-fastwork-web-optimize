// `fw run --target original|rewrite --fw <part:variant,...> --preset <name> --engines chromium,webkit [--dry]` (PLAN 10.1).
// CI-first: this never measures on this machine. It asks fwcore (`store.plan`) for the jobs, prints them (--dry), or
// dispatches each GitHub Actions workflow with `gh`, waits for the run on the shared poller (`fw ci wait`), downloads its artifacts and files them in the
// content-addressed store (`.fw-console/store/`). Every rule (which jobs, what is blocked, whether a manifest is valid,
// the object paths, the verdict) is Lean's (lean/Fw/Store); the only TS stand-in here is sha256 and file I/O.
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { ghCharged, realEnv, waitFor, type Env, type Target, type Waited } from "@fw/gh-budget";
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { GateReply, ManifestReply, PlanReply, ReduceReply, type PlanJob, type RunManifest } from "@fw/contracts";
import { UsageError } from "./lib.ts";
import { recordRunKind } from "./timing.ts";
import { newNonce, parseRunRows, pickRun, titleOf } from "./run-pick.ts";

export type RunArgs = {
  target: string; preset: string; fw: string[]; engines: string[]; profile?: string; runs?: number; dry: boolean;
  ref?: string; sha?: string; images: Record<string, string>; fromRun: Record<string, string>;
  /** `--gate`: dispatch breakpoint-gate.yml instead of the count workflows; `--engines` then takes one gate value. */
  gate?: boolean; presetGiven?: boolean;
  /** `--trajectory`: dispatch trajectory-probe.yml (the same inputs as `--gate`, plus `--widths`). */
  trajectory?: boolean; widths?: string;
};

export const RUN_USAGE = "usage: fw run --target original|rewrite [--preset <name>] [--fw part:variant,...] --engines chromium,webkit\n" +
  "       fw run --gate [--engines both|chromium|playwright-webkit] [--preset <name> | --fw part:variant,...] [--ref <branch>]\n" +
  "       fw run --trajectory [--engines both|chromium|playwright-webkit] [--preset <name> | --fw part:variant,...] [--widths 390,640,641,1280] [--ref <branch>]\n" +
  "              [--profile <id>] [--runs 2..10]\n" +
  "              [--ref <pushed branch>] [--sha <git sha>] [--image engine=sha256:...] [--from-run engine=<run id>] [--dry]";

/**
 * argv after `run` -> RunArgs. `--target` and `--engines` are required (the target is part of the store key, and an
 * original run must not file under a rewrite key); `--fw` may repeat and take commas; `--image` and `--from-run` take
 * `engine=value`. Whether the target name is valid and fits the preset and flags is fwcore's (`store.plan` problems).
 */
export function parseRunArgs(argv: string[]): RunArgs {
  const a: RunArgs = { target: "", preset: "original", fw: [], engines: [], dry: false, images: {}, fromRun: {} };
  const val = (i: number, flag: string) => {
    const v = argv[i + 1];
    if (v === undefined || v.startsWith("--")) throw new UsageError(`flag ${flag} needs a value\n${RUN_USAGE}`);
    return v;
  };
  const kv = (v: string, flag: string): [string, string] => {
    const at = v.indexOf("=");
    if (at <= 0) throw new UsageError(`flag ${flag} wants engine=value, got ${v}`);
    return [v.slice(0, at), v.slice(at + 1)];
  };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    if (f === "--dry") a.dry = true;
    else if (f === "--target") a.target = val(i++, f);
    else if (f === "--gate") a.gate = true;
    else if (f === "--trajectory") a.trajectory = true;
    else if (f === "--widths") a.widths = val(i++, f);
    else if (f === "--preset") { a.preset = val(i++, f); a.presetGiven = true; }
    else if (f === "--fw") a.fw.push(...val(i++, f).split(",").filter(Boolean));
    else if (f === "--engines") a.engines = val(i++, f).split(",").filter(Boolean);
    else if (f === "--profile") a.profile = val(i++, f);
    else if (f === "--runs") { const n = Number(val(i++, f)); if (!Number.isInteger(n)) throw new UsageError("--runs wants an integer"); a.runs = n; }
    else if (f === "--ref") a.ref = val(i++, f);
    else if (f === "--sha") a.sha = val(i++, f);
    else if (f === "--image") { const [k, v] = kv(val(i++, f), f); a.images[k] = v; }
    else if (f === "--from-run") { const [k, v] = kv(val(i++, f), f); a.fromRun[k] = v; }
    else throw new UsageError(`unknown flag ${f}\n${RUN_USAGE}`);
  }
  if (a.gate && a.trajectory) throw new UsageError(`--gate and --trajectory are separate lanes\n${RUN_USAGE}`);
  if (a.widths !== undefined && !a.trajectory) throw new UsageError(`--widths belongs to --trajectory\n${RUN_USAGE}`);
  if (a.trajectory) {
    if (a.engines.length > 1) throw new UsageError(`--trajectory takes one --engines value (both, chromium or playwright-webkit)\n${RUN_USAGE}`);
    if (a.target || a.profile || a.runs !== undefined) throw new UsageError(`--trajectory takes no --target, --profile or --runs\n${RUN_USAGE}`);
    return a;
  }
  if (a.gate) {
    if (a.engines.length > 1) throw new UsageError(`--gate takes one --engines value (both, chromium or playwright-webkit)\n${RUN_USAGE}`);
    if (a.target || a.profile || a.runs !== undefined) throw new UsageError(`--gate takes no --target, --profile or --runs (breakpoint-gate has none)\n${RUN_USAGE}`);
    return a;
  }
  if (a.engines.length === 0) throw new UsageError(`--engines is required\n${RUN_USAGE}`);
  if (!a.target) throw new UsageError(`--target is required (original = the snapshot, rewrite = apps/site)\n${RUN_USAGE}`);
  return a;
}

// ---- fwcore ----------------------------------------------------------------------------------------------------------
export type FwCall = (req: Record<string, unknown>) => Record<string, unknown>;

function fwcoreBin(cwd: string): string {
  const rel = "lean/.lake/build/bin/fwcore";
  const common = spawnSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).stdout.trim();
  const top = spawnSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).stdout.trim();
  const cands = [process.env.FW_CORE_BIN, top && join(top, rel), common && join(dirname(common), rel)].filter((x): x is string => !!x);
  const bin = cands.find((p) => existsSync(p));
  if (!bin) throw new Error("fwcore not built: sh scripts/fwcore-build.sh");
  return bin;
}

/** One request to fwcore, one reply. An `error` reply throws. */
export function fwcoreCall(cwd: string): FwCall {
  const bin = fwcoreBin(cwd);
  return (req) => {
    const r = spawnSync(bin, [], { input: JSON.stringify({ ...req, id: 0 }) + "\n", env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" }, maxBuffer: 1 << 30 });
    if (r.status !== 0) throw new Error(`fwcore exited with ${r.status ?? r.signal}: ${r.stderr}`);
    const { id: _id, ...rest } = JSON.parse(r.stdout.toString().trim().split("\n")[0]!) as Record<string, unknown>;
    if (typeof rest.error === "string") throw new UsageError(`fwcore ${String(req.op)}: ${rest.error}`);
    return rest;
  };
}

// ---- the store -----------------------------------------------------------------------------------------------------------
export const sha256 = (b: Buffer | string) => createHash("sha256").update(b).digest("hex");

/** The run key: sha256 of the canonical JSON of the key pairs fwcore returned (L3: sha256 has no collisions here). */
export const keyDigest = (key: [string, string][]) => sha256(JSON.stringify(key));

/** Digests of the runs already in the store (one directory per run under runs/). */
export function presentRuns(store: string): string[] {
  const d = join(store, "runs");
  return existsSync(d) ? readdirSync(d).filter((n) => existsSync(join(d, n, "manifest.json"))) : [];
}

const walk = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]));

export type Ingest = { manifest: RunManifest; path: string; objects: number; reused: number; digest: string; unchanged?: boolean };

/**
 * File a downloaded CI run: hash every file, copy it to its content-addressed object (fwcore gives the path), build the
 * manifest and have fwcore validate it before it is written. Throws, naming the problems, when fwcore refuses.
 */
export function ingest(call: FwCall, store: string, dir: string, job: PlanJob, meta: { target: string; preset: string; fw: string[]; profile: string; gitSha: string; runId: string }, opts: { keepSameRun?: boolean } = {}): Ingest {
  const files = walk(dir).map((p) => ({ p, name: relative(dir, p).split("\\").join("/") })).sort((x, y) => (x.name < y.name ? -1 : x.name > y.name ? 1 : 0));
  const entries = files.map(({ p, name }) => { const b = readFileSync(p); return { name, digest: sha256(b), bytes: b.length, p }; });
  const manifest: RunManifest = {
    engine: job.engine, target: meta.target as RunManifest["target"], preset: meta.preset, fw: meta.fw, profile: meta.profile, gitSha: meta.gitSha, image: job.image as RunManifest["image"],
    runId: meta.runId, entries: entries.map(({ name, digest, bytes }) => ({ name, digest, bytes })),
  };
  const checked = ManifestReply.parse(call({ op: "store.manifest", manifest }));
  if (!checked.valid) throw new UsageError(`manifest refused: ${checked.problems.join("; ")}`);
  const digest = keyDigest(checked.key as [string, string][]);
  const mpath = join(store, "runs", digest, "manifest.json");
  if (opts.keepSameRun && existsSync(mpath)) {
    // `fw ci`: the key is already filed. The same run again changes nothing; another run of the same key is not ours to overwrite.
    const old = JSON.parse(readFileSync(mpath, "utf8")) as RunManifest;
    if (old.runId !== manifest.runId) throw new UsageError(`key ${digest.slice(0, 12)} is already stored from run ${old.runId}; run ${manifest.runId} has the same key (not overwritten)`);
    return { manifest: old, path: mpath, objects: 0, reused: entries.length, digest, unchanged: true };
  }
  let reused = 0;
  entries.forEach((e, i) => {
    const dest = join(store, checked.paths![i]!);
    if (existsSync(dest)) { reused++; return; }
    mkdirSync(dirname(dest), { recursive: true });
    copyFileSync(e.p, dest);
  });
  mkdirSync(dirname(mpath), { recursive: true });
  writeFileSync(mpath, JSON.stringify(manifest, null, 2) + "\n");
  return { manifest, path: mpath, objects: entries.length - reused, reused, digest };
}

// ---- gh (CI) ---------------------------------------------------------------------------------------------------------------
// Every gh call goes through `ghCharged` (packages/gh-budget): fwcore's `ci.budget.reserve` decides whether it runs, and a
// wait or stop means gh is not started. Waiting for a run is `waitFor` (the same engine as `fw ci wait`): the shared poller
// makes the list calls, however many waiters there are.
/** Bounds of one gh call: `deadline` (epoch second) ends a budget wait, an aborted `signal` stops the call before it starts. */
export type GhOpts = { deadline?: number; signal?: AbortSignal };
export type Gh = (args: string[], o?: GhOpts) => Promise<string>;

/** Requests one gh command costs (research/notes/2026/10-18-gh-rate-budget.md §1; the budget arithmetic itself is fwcore's).
 *  A download is booked at an upper bound: 1 listing plus the artifacts of one run. */
export function ghCost(args: string[]): number {
  const [a, b] = args;
  if (a === "run" && b === "list") return args.includes("--workflow") ? 2 : 3;
  if (a === "run" && b === "view") return args.some((x) => x.includes("jobs")) ? 3 : 2;
  if (a === "run" && b === "download") return 15;
  if (a === "workflow" && b === "run") return 2;
  return 1;
}

/** A `Gh` that books each call with the budget and sleeps while fwcore says wait. A stop or a gh failure throws. */
export function chargedGh(env: Env): Gh {
  return async (args, o) => {
    const what = args.slice(0, 3).join(" ");
    if (o?.signal?.aborted) throw new Error(`gh ${what} not made: aborted`);
    const res = await ghCharged(env, args, { cost: ghCost(args), block: true, ...(o?.deadline !== undefined ? { deadline: o.deadline } : {}) });
    if (!res.ran) throw new Error(`gh ${what} not made: the request budget says ${res.decision} (${res.reason}); see \`fw ci budget\``);
    if (res.code !== 0) throw new Error(`gh ${what} failed: ${res.error ?? "unknown"}`);
    return res.stdout;
  };
}

/** One bounded wait on the shared poller (`waitFor`), `timeoutS` at most. */
export type WaitFn = (t: Target, timeoutS: number) => Promise<Waited>;

const WAIT_SLICE_S = 540; // one `fw ci wait` slice; fits a Bash tool call
const WAIT_CAP_S = 4 * 3600;

/** Wait until the target's runs are decided: repeats a timed-out slice, throws when the poller stopped or `capS` passed. */
export async function waitDecided(wait: WaitFn, t: Target, now: () => number, capS = WAIT_CAP_S): Promise<Waited> {
  const start = now();
  for (;;) {
    const t0 = now();
    const w = await wait(t, WAIT_SLICE_S);
    if (w.code !== 3) return w;
    if (now() - t0 < WAIT_SLICE_S) throw new Error(w.lines.join("; ")); // returned early: the poller stopped, it was not a timeout
    if (now() - start >= capS) throw new Error(`gave up waiting after ${capS} s: ${w.lines.join("; ")}`);
  }
}

/** `gh workflow run` arguments of a job. */
export const dispatchArgs = (job: Pick<PlanJob, "workflow" | "inputs">, ref: string): string[] =>
  ["workflow", "run", job.workflow, "--ref", ref, ...Object.entries(job.inputs).flatMap(([k, v]) => ["-f", `${k}=${v}`])];

// ---- the plan ----------------------------------------------------------------------------------------------------------------------
export type Planned = { reply: PlanReply; sha: string; args: RunArgs };

/** Ask fwcore for the plan; the cache column comes from the digests of the job keys against the store. */
export function planRun(call: FwCall, args: RunArgs, sha: string, store: string): Planned {
  const base = { op: "store.plan", target: args.target, preset: args.preset, fw: args.fw, engines: args.engines, sha, images: args.images,
    ...(args.profile ? { profile: args.profile } : {}), ...(args.runs !== undefined ? { runs: args.runs } : {}) };
  const first = PlanReply.parse(call(base));
  const digests = Object.fromEntries(first.jobs.map((j) => [j.engine, keyDigest(j.key as [string, string][])]));
  const reply = first.jobs.length ? PlanReply.parse(call({ ...base, digests, present: presentRuns(store) })) : first;
  return { reply, sha, args };
}

export function renderPlan(p: Planned, dry: boolean): string[] {
  const { reply, args } = p;
  const out = [`fw run${dry ? " (dry)" : ""}: target ${args.target}, preset ${args.preset}, flags ${reply.fw.join(",") || "-"}, sha ${p.sha.slice(0, 7)}`];
  for (const pr of reply.problems) out.push(`  problem: ${pr}`);
  for (const j of reply.jobs) {
    const ins = Object.entries(j.inputs).map(([k, v]) => `${k}=${v}`).join(" ") || "-";
    out.push(`  ${j.engine.padEnd(8)} ${j.workflow}  key ${(j.digest ?? "").slice(0, 12)}  cache ${j.cache ?? "?"}  inputs ${ins}  image ${j.image}` +
      (j.blocked ? `  BLOCKED: ${j.workflow} has no input "${j.blocked}" yet` : ""));
  }
  return out;
}

export type RunDeps = {
  call: FwCall; gh: Gh; wait: WaitFn; store: string; sha: string; branch: string; tmp: string; log: (l: string) => void;
  /** Epoch seconds. */
  now: () => number;
  /** The display name of a workflow file, when it can be read locally (used when the workflow has no earlier run). */
  workflowName?: (file: string) => string | undefined;
  /** The commit of a pushed branch (`--ref`), so a base ref is measured and keyed under its own sha; absent = the checkout's. */
  refSha?: (ref: string) => string | undefined;
  /** Remember the inputs of a run this command dispatched (the timing kind of its spans, timing.ts `recordRunKind`). */
  recordKind?: (runId: number, inputs: PlanJob["inputs"]) => void;
  capS?: number;
  /** The nonce of a dispatch (`--trajectory`); a fresh random one when absent. */
  nonce?: () => string;
  /** Wait between two looks at the run list, seconds; real time when absent. */
  sleep?: (seconds: number) => Promise<void>;
};

const epoch = (iso: string) => Math.floor(Date.parse(iso) / 1000);
const runLine = /^run (\d+) /;

/** The whole command. Returns the exit code: 0 ok, 2 refused (problems, blocked job). */
export async function runMain(args: RunArgs, d: RunDeps): Promise<number> {
  const sha = refShaOf(args, d);
  if (args.gate) return runGate(args, d, sha);
  if (args.trajectory) return runGate(args, d, sha, "trajectory");
  const planned = planRun(d.call, args, sha, d.store);
  for (const l of renderPlan(planned, args.dry)) d.log(l);
  if (planned.reply.problems.length) return 2;
  if (args.dry) return 0;
  const blocked = planned.reply.jobs.filter((j) => j.blocked && !args.fromRun[j.engine]);
  if (blocked.length) { d.log(`refused: ${blocked.map((j) => `${j.engine} (${j.blocked})`).join(", ")} cannot express this request; add the input to the workflow first`); return 2; }
  const ref = args.ref ?? d.branch;
  for (const j of planned.reply.jobs) {
    if (j.cache === "hit") { d.log(`${j.engine}: cached at ${j.manifest}`); continue; }
    let runId = args.fromRun[j.engine];
    if (!runId) {
      const before = await latestRun(d.gh, j.workflow, ref);
      const at = d.now();
      await d.gh(dispatchArgs(j, ref));
      d.log(`${j.engine}: dispatched ${j.workflow} on ${ref}; waiting for the run`);
      // the dispatched run is the newest run of that workflow on the ref created after the previous newest one
      const name = before?.workflowName || d.workflowName?.(j.workflow);
      const w = await waitDecided(d.wait, { kind: "branch", branch: ref, ...(name ? { workflow: name } : {}), sha, since: before ? epoch(before.createdAt) + 1 : at - 60 }, d.now, d.capS);
      runId = decided(j.engine, w);
      d.recordKind?.(Number(runId), j.inputs);
    } else {
      runId = decided(j.engine, await waitDecided(d.wait, { kind: "run", runId: Number(runId) }, d.now, d.capS));
    }
    const head = (JSON.parse(await d.gh(["run", "view", runId, "--json", "headSha"])) as { headSha: string }).headSha;
    if (head !== sha) throw new UsageError(`${j.engine}: run ${runId} measured ${head.slice(0, 7)}, not ${sha.slice(0, 7)}`);
    const dir = join(d.tmp, `${j.engine}-${runId}`);
    mkdirSync(dir, { recursive: true });
    await d.gh(["run", "download", runId, "-D", dir]);
    const r = ingest(d.call, d.store, dir, j, { target: args.target, preset: args.preset, fw: planned.reply.fw, profile: args.profile ?? "swipe-v1", gitSha: sha, runId });
    d.log(`${j.engine}: run ${runId} filed, ${r.manifest.entries.length} artifacts (${r.objects} new, ${r.reused} already stored) -> ${relative(d.store, r.path)}`);
  }
  return 0;
}

/** The sha a run is measured at: `--sha`, else the tip of `--ref` (when the caller can resolve it), else the checkout's. */
function refShaOf(args: RunArgs, d: RunDeps): string {
  if (args.sha) return args.sha;
  if (args.ref && d.refSha) {
    const r = d.refSha(args.ref);
    if (!r) throw new UsageError(`cannot resolve --ref ${args.ref} to a commit (not fetched?); pass --sha <40 hex>`);
    return r;
  }
  return d.sha;
}

/** The dispatch of the breakpoint gate: fwcore (`store.gate`) decides the inputs and whether the workflow can express them. */
export function planGate(call: FwCall, args: RunArgs, lane: "gate" | "trajectory" = "gate"): GateReply {
  return GateReply.parse(call({ op: lane === "gate" ? "store.gate" : "store.trajectory", ...(args.engines[0] ? { engines: args.engines[0] } : {}),
    ...(args.presetGiven ? { preset: args.preset } : {}), ...(args.fw.length ? { fw: args.fw } : {}),
    ...(lane === "trajectory" && args.widths !== undefined ? { widths: args.widths } : {}) }));
}

/** `fw run --gate` or `--trajectory`: dispatch breakpoint-gate.yml or trajectory-probe.yml on the ref and wait for the run. The
 *  lane files nothing in the store; its tables are artifacts of the run (`gh run download <id>`). Exit 0 ok, 2 refused. */
async function runGate(args: RunArgs, d: RunDeps, sha: string, lane: "gate" | "trajectory" = "gate"): Promise<number> {
  const reply = planGate(d.call, args, lane);
  const job = reply.job;
  d.log(`fw run${args.dry ? " (dry)" : ""}: ${lane}, sha ${sha.slice(0, 7)}`);
  for (const pr of reply.problems) d.log(`  problem: ${pr}`);
  if (!job) return 2;
  d.log(`  ${lane.padEnd(8)} ${job.workflow}  inputs ${Object.entries(job.inputs).map(([k, v]) => `${k}=${v}`).join(" ")}` + (job.blocked ? `  BLOCKED: ${job.workflow} has no input "${job.blocked}" yet` : ""));
  if (args.dry) return 0;
  if (job.blocked) { d.log(`refused: ${lane} (${job.blocked}) cannot express this request; add the input to the workflow first`); return 2; }
  const ref = args.ref ?? d.branch;
  let runId = args.fromRun[lane];
  if (!runId && lane === "trajectory") {
    // identity, not recency: the dispatch carries a nonce, the run title echoes it (Lean Fw.Ci.Dispatch.pick)
    const nonce = d.nonce?.() ?? newNonce();
    await d.gh(dispatchArgs({ workflow: job.workflow, inputs: { ...job.inputs, nonce } }, ref));
    d.log(`${lane}: dispatched ${job.workflow} on ${ref} with nonce ${nonce} (run title "${titleOf(nonce)}"); looking for the run`);
    const picked = await findDispatched(d, job.workflow, ref, nonce);
    d.log(`${lane}: the run with nonce ${nonce} is ${picked}`);
    runId = decided(lane, await waitDecided(d.wait, { kind: "run", runId: Number(picked) }, d.now, d.capS));
  } else if (!runId) {
    const before = await latestRun(d.gh, job.workflow, ref);
    const at = d.now();
    await d.gh(dispatchArgs({ workflow: job.workflow, inputs: job.inputs }, ref));
    d.log(`${lane}: dispatched ${job.workflow} on ${ref}; waiting for the run`);
    const name = before?.workflowName || d.workflowName?.(job.workflow);
    const w = await waitDecided(d.wait, { kind: "branch", branch: ref, ...(name ? { workflow: name } : {}), sha, since: before ? epoch(before.createdAt) + 1 : at - 60 }, d.now, d.capS);
    runId = decided(lane, w);
  } else {
    runId = decided(lane, await waitDecided(d.wait, { kind: "run", runId: Number(runId) }, d.now, d.capS));
  }
  const head = (JSON.parse(await d.gh(["run", "view", runId, "--json", "headSha"])) as { headSha: string }).headSha;
  if (head !== sha) throw new UsageError(`${lane}: run ${runId} measured ${head.slice(0, 7)}, not ${sha.slice(0, 7)}`);
  d.log(`${lane}: run ${runId} succeeded at ${sha.slice(0, 7)} (tables: gh run download ${runId})`);
  return 0;
}

const FIND_EVERY_S = 120; // CI polls are at least 120 s apart (shared GitHub token); a dispatch run appears within seconds
const FIND_TRIES = 5;

/** The id of the run a dispatch created, found by its nonce in the run title (Lean `Fw.Ci.Dispatch.pick`); an absent run is
 *  looked for again every 120 s, an ambiguous one is an error (never a guess). */
export async function findDispatched(d: Pick<RunDeps, "gh" | "sleep">, workflow: string, ref: string, nonce: string): Promise<string> {
  const sleep = d.sleep ?? ((s: number) => new Promise<void>((res) => setTimeout(res, s * 1000)));
  for (let i = 0; i < FIND_TRIES; i++) {
    await sleep(FIND_EVERY_S);
    const rows = parseRunRows(await d.gh(["run", "list", "--workflow", workflow, "--branch", ref, "--event", "workflow_dispatch", "--limit", "30", "--json", "databaseId,displayTitle,event"]));
    const p = pickRun(nonce, rows);
    if (p.kind === "found") return String(p.id);
    if (p.kind === "ambiguous") throw new Error(`nonce ${nonce} matches several runs (${p.ids.join(", ")}); not guessing`);
    if (p.kind === "badNonce") throw new Error(`nonce ${nonce} is not valid`);
  }
  throw new Error(`no run titled "${titleOf(nonce)}" on ${ref} after ${FIND_TRIES} looks; the dispatch may have failed (gh run list --workflow ${workflow} --event workflow_dispatch)`);
}

export type LatestRun = { id: string; createdAt: string; workflowName: string };

/** The newest run of a workflow on a ref, or null when it has none. */
export async function latestRun(gh: Gh, workflow: string, ref: string): Promise<LatestRun | null> {
  const rows = JSON.parse(await gh(["run", "list", "--workflow", workflow, "--branch", ref, "--limit", "1", "--json", "databaseId,createdAt,workflowName"])) as { databaseId: number; createdAt?: string; workflowName?: string }[];
  return rows[0] ? { id: String(rows[0].databaseId), createdAt: rows[0].createdAt ?? "", workflowName: rows[0].workflowName ?? "" } : null;
}

/** The run id of a decided wait; a run that did not pass (fwcore `ci.verdict`) stops the command (like `gh run watch
 *  --exit-status`): a failure, and also a run whose guard skipped (exit 4, not run), which GitHub calls `success`. */
function decided(engine: string, w: Waited): string {
  const id = runLine.exec(w.lines[0] ?? "")?.[1];
  if (w.code === 0 && id) return id;
  const why = w.code === 1 ? "the run did not succeed: " : w.code === 4 ? "the run did not run (its guard skipped): " : "cannot wait for the run: ";
  throw new Error(`${engine}: ${why}${w.lines.join("; ")}`);
}

/** Count reduction and verdict: base and var runs per engine -> fwcore's `store.reduce`. */
export function reduceArms(call: FwCall, arms: { engine: string; base: unknown[]; var: unknown[] }[], kMax = 4, tMax = 24): ReduceReply {
  return ReduceReply.parse(call({ op: "store.reduce", kMax, tMax, arms }));
}

export const storeDir = (consoleDir: string) => join(consoleDir, "store");
export const isDir = (p: string) => existsSync(p) && statSync(p).isDirectory();

/** `fw run ...` from the shell. Needs no console-api. */
export async function runCli(argv: string[], cwd: string, env: Record<string, string | undefined> = process.env): Promise<number> {
  const vcs = (...a: string[]) => spawnSync("git", a, { cwd, encoding: "utf8" }).stdout.trim();
  const args = parseRunArgs(argv);
  const consoleDir = env.FW_CONSOLE_DIR ?? join(dirname(vcs("rev-parse", "--path-format=absolute", "--git-common-dir")), ".fw-console");
  const genv = args.dry ? null : realEnv(cwd); // --dry makes no gh call and needs no budget state
  const unused = (): never => { throw new Error("no gh call in --dry"); };
  return runMain(args, {
    call: fwcoreCall(cwd), gh: genv ? chargedGh(genv) : unused, wait: genv ? (t, timeoutS) => waitFor(genv, t, { timeoutS }) : unused,
    now: genv ? genv.now : () => Math.floor(Date.now() / 1000),
    recordKind: (id, inputs) => { recordRunKind(id, inputs, cwd); },
    refSha: (r) => vcs("rev-parse", "--verify", "--quiet", `refs/remotes/origin/${r}^{commit}`) || vcs("rev-parse", "--verify", "--quiet", `refs/heads/${r}^{commit}`) || undefined,
    workflowName: (f) => { try { return /^name:\s*["']?([^"'\n#]+?)["']?\s*(?:#.*)?$/m.exec(readFileSync(join(cwd, ".github", "workflows", f), "utf8"))?.[1]; } catch { return undefined; } },
    store: storeDir(consoleDir), sha: vcs("rev-parse", "HEAD"), branch: vcs("rev-parse", "--abbrev-ref", "HEAD"),
    tmp: join(consoleDir, "tmp"), log: (l) => console.log(l),
  });
}
