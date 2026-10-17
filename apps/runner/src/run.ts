// `fw run --target original|rewrite --fw <part:variant,...> --preset <name> --engines chromium,webkit [--dry]` (PLAN 10.1).
// CI-first: this never measures on this machine. It asks fwcore (`store.plan`) for the jobs, prints them (--dry), or
// dispatches each GitHub Actions workflow with `gh`, waits for the run, downloads its artifacts and files them in the
// content-addressed store (`.fw-console/store/`). Every rule (which jobs, what is blocked, whether a manifest is valid,
// the object paths, the verdict) is Lean's (lean/Fw/Store); the only TS stand-in here is sha256 and file I/O.
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { ManifestReply, PlanReply, ReduceReply, type PlanJob, type RunManifest } from "@fw/contracts";
import { UsageError } from "./lib.ts";

export type RunArgs = {
  target: string; preset: string; fw: string[]; engines: string[]; profile?: string; runs?: number; dry: boolean;
  ref?: string; sha?: string; images: Record<string, string>; fromRun: Record<string, string>;
};

export const RUN_USAGE = "usage: fw run --target original|rewrite [--preset <name>] [--fw part:variant,...] --engines chromium,webkit\n" +
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
    else if (f === "--preset") a.preset = val(i++, f);
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
  if (!bin) throw new Error("fwcore not built: cd lean && lake build");
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

export type Ingest = { manifest: RunManifest; path: string; objects: number; reused: number };

/**
 * File a downloaded CI run: hash every file, copy it to its content-addressed object (fwcore gives the path), build the
 * manifest and have fwcore validate it before it is written. Throws, naming the problems, when fwcore refuses.
 */
export function ingest(call: FwCall, store: string, dir: string, job: PlanJob, meta: { target: string; preset: string; fw: string[]; profile: string; gitSha: string; runId: string }): Ingest {
  const files = walk(dir).map((p) => ({ p, name: relative(dir, p).split("\\").join("/") })).sort((x, y) => (x.name < y.name ? -1 : x.name > y.name ? 1 : 0));
  const entries = files.map(({ p, name }) => { const b = readFileSync(p); return { name, digest: sha256(b), bytes: b.length, p }; });
  const manifest: RunManifest = {
    engine: job.engine, target: meta.target as RunManifest["target"], preset: meta.preset, fw: meta.fw, profile: meta.profile, gitSha: meta.gitSha, image: job.image as RunManifest["image"],
    runId: meta.runId, entries: entries.map(({ name, digest, bytes }) => ({ name, digest, bytes })),
  };
  const checked = ManifestReply.parse(call({ op: "store.manifest", manifest }));
  if (!checked.valid) throw new UsageError(`manifest refused: ${checked.problems.join("; ")}`);
  let reused = 0;
  entries.forEach((e, i) => {
    const dest = join(store, checked.paths![i]!);
    if (existsSync(dest)) { reused++; return; }
    mkdirSync(dirname(dest), { recursive: true });
    copyFileSync(e.p, dest);
  });
  const digest = keyDigest(checked.key as [string, string][]);
  const mpath = join(store, "runs", digest, "manifest.json");
  mkdirSync(dirname(mpath), { recursive: true });
  writeFileSync(mpath, JSON.stringify(manifest, null, 2) + "\n");
  return { manifest, path: mpath, objects: entries.length - reused, reused };
}

// ---- gh (CI) ---------------------------------------------------------------------------------------------------------------
export type Gh = (args: string[]) => string;
export const ghCli: Gh = (args) => {
  const r = spawnSync("gh", args, { encoding: "utf8", env: { ...process.env, GH_PROMPT_DISABLED: "1" }, maxBuffer: 1 << 28 });
  if (r.status !== 0) throw new Error(`gh ${args.slice(0, 3).join(" ")} failed: ${r.stderr.trim()}`);
  return r.stdout;
};

/** `gh workflow run` arguments of a job. */
export const dispatchArgs = (job: PlanJob, ref: string): string[] =>
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

export type RunDeps = { call: FwCall; gh: Gh; store: string; sha: string; branch: string; tmp: string; log: (l: string) => void; pollMs?: number };

/** The whole command. Returns the exit code: 0 ok, 2 refused (problems, blocked job). */
export function runMain(args: RunArgs, d: RunDeps): number {
  const sha = args.sha ?? d.sha;
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
      const before = latestRun(d.gh, j.workflow, ref);
      d.gh(dispatchArgs(j, ref));
      d.log(`${j.engine}: dispatched ${j.workflow} on ${ref}; waiting for the run`);
      runId = newestRun(d.gh, j.workflow, ref, before, d.pollMs ?? 5000);
    }
    d.gh(["run", "watch", runId, "--exit-status"]);
    const head = (JSON.parse(d.gh(["run", "view", runId, "--json", "headSha"])) as { headSha: string }).headSha;
    if (head !== sha) throw new UsageError(`${j.engine}: run ${runId} measured ${head.slice(0, 7)}, not ${sha.slice(0, 7)}`);
    const dir = join(d.tmp, `${j.engine}-${runId}`);
    mkdirSync(dir, { recursive: true });
    d.gh(["run", "download", runId, "-D", dir]);
    const r = ingest(d.call, d.store, dir, j, { target: args.target, preset: args.preset, fw: planned.reply.fw, profile: args.profile ?? "swipe-v1", gitSha: sha, runId });
    d.log(`${j.engine}: run ${runId} filed, ${r.manifest.entries.length} artifacts (${r.objects} new, ${r.reused} already stored) -> ${relative(d.store, r.path)}`);
  }
  return 0;
}

/** The id of the newest run of a workflow on a ref, or null when it has none. */
export function latestRun(gh: Gh, workflow: string, ref: string): string | null {
  const rows = JSON.parse(gh(["run", "list", "--workflow", workflow, "--branch", ref, "--limit", "1", "--json", "databaseId"])) as { databaseId: number }[];
  return rows[0] ? String(rows[0].databaseId) : null;
}

/** The run just dispatched: the newest run once it differs from `before` (polls up to 24 times, `pollMs` apart). */
export function newestRun(gh: Gh, workflow: string, ref: string, before: string | null, pollMs: number): string {
  for (let i = 0; i < 24; i++) {
    const id = latestRun(gh, workflow, ref);
    if (id && id !== before) return id;
    if (pollMs > 0) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, pollMs);
  }
  throw new Error(`no new run of ${workflow} on ${ref} appeared after dispatch`);
}

/** Count reduction and verdict: base and var runs per engine -> fwcore's `store.reduce`. */
export function reduceArms(call: FwCall, arms: { engine: string; base: unknown[]; var: unknown[] }[], kMax = 4, tMax = 24): ReduceReply {
  return ReduceReply.parse(call({ op: "store.reduce", kMax, tMax, arms }));
}

export const storeDir = (consoleDir: string) => join(consoleDir, "store");
export const isDir = (p: string) => existsSync(p) && statSync(p).isDirectory();

/** `fw run ...` from the shell. Needs no console-api. */
export function runCli(argv: string[], cwd: string, env: Record<string, string | undefined> = process.env): number {
  const vcs = (...a: string[]) => spawnSync("git", a, { cwd, encoding: "utf8" }).stdout.trim();
  const args = parseRunArgs(argv);
  const consoleDir = env.FW_CONSOLE_DIR ?? join(dirname(vcs("rev-parse", "--path-format=absolute", "--git-common-dir")), ".fw-console");
  return runMain(args, {
    call: fwcoreCall(cwd), gh: ghCli, store: storeDir(consoleDir), sha: vcs("rev-parse", "HEAD"), branch: vcs("rev-parse", "--abbrev-ref", "HEAD"),
    tmp: join(consoleDir, "tmp"), log: (l) => console.log(l),
  });
}
