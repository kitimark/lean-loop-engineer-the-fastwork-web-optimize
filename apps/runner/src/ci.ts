// `fw ci <run id> | --branch ci/<x> [--workflow chromium-counts] [--store <dir>]`: pull the artifacts of a finished
// chromium-counts run into the artifact store (`.fw-console/store/`), one store key per target in the run.
// Every decision is fwcore's: `store.ciRun` (lean/Fw/Store/Ci.lean) accepts or refuses the run, names the shard
// artifacts and their entry directories per target and gives each target's key inputs; `store.manifest` (via `ingest`
// in run.ts) checks the manifest and gives the key and the object paths. This file is gh calls (all through the request
// budget, `chargedGh`), file reads and copies.
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { UsageError } from "./lib.ts";
import { realEnv } from "@fw/gh-budget";
import { chargedGh, fwcoreCall, ingest, storeDir, type FwCall, type Gh } from "./run.ts";
import { GhClock, ciStateParts, phasedEnv } from "./run-phases.ts";
import { record, type Span } from "./timing.ts";
type StateSpan = Pick<Span, "tool" | "step" | "startMs" | "durMs" | "exit">;

export const CI_USAGE = "usage: fw ci <run id> | --branch ci/<x> [--workflow chromium-counts] [--store <dir>]\n" +
  "  a run id or --branch is required (a main push runs no measurement). With --branch: the latest run of the workflow\n" +
  "  on that branch. Refuses a run that did not succeed or lacks a shard.";

export type CiArgs = { runId?: string; workflow: string; branch?: string; store?: string };
export function parseCiArgs(argv: string[]): CiArgs {
  const a: CiArgs = { workflow: "chromium-counts" };
  const val = (i: number, f: string) => { const v = argv[i + 1]; if (v === undefined || v.startsWith("--")) throw new UsageError(`flag ${f} needs a value\n${CI_USAGE}`); return v; };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    if (f === "--workflow") a.workflow = val(i++, f);
    else if (f === "--branch") a.branch = val(i++, f);
    else if (f === "--store") a.store = val(i++, f);
    else if (f.startsWith("--")) throw new UsageError(`unknown flag ${f}\n${CI_USAGE}`);
    else if (/^[0-9]+$/.test(f) && !a.runId) a.runId = f;
    else throw new UsageError(`unexpected argument ${f}\n${CI_USAGE}`);
  }
  if (!a.runId && !a.branch) throw new UsageError(`a run id or --branch is required\n${CI_USAGE}`);
  return a;
}

// ---- fwcore `store.ciRun` -----------------------------------------------------------------------------------------
export type CiJob = { name: string; conclusion: string | null };
export type CiRunInfo = { runId: string; workflowName: string; status: string; conclusion: string | null; headSha: string; jobs: CiJob[] };
/** What `fw ci` read from one downloaded shard artifact (`counts.json`, `image-id.txt`). */
export type CiFacts = { name: string; profile: string; image: string; search?: string; target?: string };
export type CiMeta = { engine: string; target: string; preset: string; fw: string[]; profile: string; gitSha: string; image: string; runId: string };
export type CiTarget = { target: "original" | "rewrite"; classes: string; shards: { artifact: string; dir: string }[]; meta?: CiMeta; key?: [string, string][] };
export type CiReply = { accept: boolean; refusals: string[]; targets: CiTarget[] };

/** fwcore `store.ciRun`: without `got` the check before the download, with it the full check and the key inputs. */
export function ciRun(call: FwCall, run: CiRunInfo, got?: { artifacts: CiFacts[]; classes: string[] }): CiReply {
  return call({ op: "store.ciRun", run, ...(got ?? {}) }) as CiReply;
}

// ---- I/O --------------------------------------------------------------------------------------------------------------
export type CiDeps = { call: FwCall; gh: Gh; store: string; tmp: string; log: (l: string) => void };

const rd = (p: string) => readFileSync(p, "utf8");
const copyTree = (from: string, to: string, prefix = ""): void => {
  for (const e of readdirSync(from, { withFileTypes: true })) {
    if (e.isDirectory()) copyTree(join(from, e.name), to, `${prefix}${e.name}/`);
    else { mkdirSync(dirname(join(to, prefix + e.name)), { recursive: true }); copyFileSync(join(from, e.name), join(to, prefix + e.name)); }
  }
};

export async function latestRunId(gh: Gh, workflow: string, branch: string): Promise<string | null> {
  const rows = JSON.parse(await gh(["run", "list", "--workflow", workflow, "--branch", branch, "--limit", "1", "--json", "databaseId"])) as { databaseId: number }[];
  return rows[0] ? String(rows[0].databaseId) : null;
}

/** The state word `fw review ready` reads for one run: `complete` (completed, success), `failed` (completed otherwise) or `running`. I/O glue, no decision. */
export function runStateWord(status: string, conclusion: string | null): "running" | "complete" | "failed" {
  if (status !== "completed") return "running";
  return conclusion === "success" ? "complete" : "failed";
}

/** The list sizes `fw ci state` tries in turn (Lean `Fw.Ci.StateList.limits`): 100 newest runs cover about an hour of a busy repository
 *  (MEASURED 2026-10-21: 100 runs spanned 51 min); gh pages up to 1000 in one call, 22.3 s for the 1000 list (MEASURED 2026-10-23). */
export const STATE_LIMITS = [100, 400, 1000] as const;

export type StateStep = { step: "found" | "ended" | "older" | "absent" | "exhausted" } | { step: "grow"; next: number };

/** What to do after one `gh run list` of `limit` rows (newest first, ids ascending with age reversed) for `id`. TS stand-in for Lean
 *  `Fw.Ci.StateList.step`, checked against `packages/contracts/golden/ci/state-list.jsonl` in `apps/runner/test/ci-state.test.ts`;
 *  marked for replacement by an fwcore op. */
export function stateStep(narrowed: boolean, limit: number, id: number, ids: number[]): StateStep {
  if (ids.includes(id)) return { step: "found" };
  if (ids.length < limit) return { step: "ended" };
  if (!ids.every((x) => id < x)) return { step: "absent" };
  if (!narrowed) return { step: "older" };
  const i = STATE_LIMITS.indexOf(limit as (typeof STATE_LIMITS)[number]);
  const next = i >= 0 ? STATE_LIMITS[i + 1] : undefined;
  return next === undefined ? { step: "exhausted" } : { step: "grow", next };
}

/** `fw ci state <run id> [--branch b] [--workflow w]`: read one run by identity from `gh run list` (list calls only, never `gh run view` or `gh api`).
 *  With `--branch` or `--workflow` the list is filtered, so an older run is in reach and the list grows (100, 400, 1000) while the id is older than its
 *  oldest row; without them one list of 100 is read and an older id stops there (`stateStep`). Prints `<id> <state>`; exit 0, or 2 when not found. */
export async function ciState(runId: string, d: { gh: Gh; log: (l: string) => void; branch?: string; workflow?: string }): Promise<number> {
  if (!/^[0-9]+$/.test(runId)) throw new UsageError("usage: fw ci state <run id> [--branch <b>] [--workflow <w>]");
  const narrow = [...(d.branch ? ["--branch", d.branch] : []), ...(d.workflow ? ["--workflow", d.workflow] : [])];
  const id = Number(runId);
  let limit: number = STATE_LIMITS[0];
  for (;;) {
    const rows = JSON.parse(await d.gh(["run", "list", ...narrow, "--limit", String(limit), "--json", "databaseId,status,conclusion"])) as { databaseId: number; status: string; conclusion: string | null }[];
    const s = stateStep(narrow.length > 0, limit, id, rows.map((x) => x.databaseId));
    if (s.step === "found") { const r = rows.find((x) => x.databaseId === id)!; d.log(`${runId} ${runStateWord(r.status, r.conclusion)}`); return 0; }
    if (s.step === "grow") { limit = s.next; continue; }
    d.log(s.step === "older" ? `${runId} unknown (older than the newest ${limit} runs; pass --branch or --workflow)` : `${runId} unknown`);
    return 2;
  }
}

/** The whole command. Exit code: 0 stored (or unchanged), 2 refused. */
export async function ciMain(args: CiArgs, d: CiDeps): Promise<number> {
  const runId = args.runId ?? (args.branch ? await latestRunId(d.gh, args.workflow, args.branch) : null);
  if (!runId) { d.log(`refused: no run of ${args.workflow} on ${args.branch ?? "(no branch given)"}`); return 2; }
  const v = JSON.parse(await d.gh(["run", "view", runId, "--json", "workflowName,status,conclusion,headSha,jobs"])) as Omit<CiRunInfo, "runId">;
  const run: CiRunInfo = { runId, workflowName: v.workflowName, status: v.status, conclusion: v.conclusion ?? "", headSha: v.headSha, jobs: v.jobs.map((j) => ({ name: j.name, conclusion: j.conclusion ?? "" })) };
  // Check the run itself first, so a failed run downloads nothing.
  const pre = ciRun(d.call, run);
  if (!pre.accept) { for (const r of pre.refusals) d.log(`refused: ${r}`); return 2; }
  mkdirSync(d.tmp, { recursive: true });
  const dl = mkdtempSync(join(d.tmp, `ci-${runId}-`));
  try {
    await d.gh(["run", "download", runId, "-D", dl, "--pattern", "chromium-counts-*", "--pattern", "chromium-classes"]);
    // Read the facts of every shard artifact fwcore named that was downloaded; the missing ones fwcore refuses.
    const artifacts = pre.targets.flatMap((t) => t.shards).filter((s) => existsSync(join(dl, s.artifact))).map((s): CiFacts => {
      const c = JSON.parse(rd(join(dl, s.artifact, "counts.json"))) as { profile: { id: string }; meta: { search?: string; target?: string } };
      return { name: s.artifact, profile: c.profile.id, image: rd(join(dl, s.artifact, "image-id.txt")).trim(), search: c.meta.search ?? "", ...(c.meta.target === undefined ? {} : { target: c.meta.target }) };
    });
    const cdir = join(dl, "chromium-classes");
    const classes = existsSync(cdir) ? readdirSync(cdir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name) : [];
    const sel = ciRun(d.call, run, { artifacts, classes });
    if (!sel.accept) { for (const r of sel.refusals) d.log(`refused: ${r}`); return 2; }
    for (const t of sel.targets) {
      const m = t.meta;
      if (!m) throw new Error(`fwcore store.ciRun accepted ${t.target} without key inputs`);
      const stage = join(dl, `stage-${t.target}`);
      for (const s of t.shards) copyTree(join(dl, s.artifact), stage, `${s.dir}/`);
      copyTree(join(cdir, t.classes), stage, "classes/");
      writeFileSync(join(stage, "ci.json"), JSON.stringify({ schema: "fw.ci-run/1", workflow: run.workflowName, runId, headSha: run.headSha, conclusion: run.conclusion }, null, 2) + "\n");
      const r = ingest(d.call, d.store, stage, { engine: m.engine, image: m.image } as never,
        { target: m.target, preset: m.preset, fw: m.fw, profile: m.profile, gitSha: m.gitSha, runId: m.runId }, { keepSameRun: true });
      d.log(`${t.target}: run ${runId} ${run.conclusion} @ ${run.headSha.slice(0, 7)} key ${r.digest} ${r.unchanged ? "unchanged" : `stored, ${r.objects} new objects, ${r.reused} already stored`} (${r.manifest.entries.length} artifacts)`);
    }
    return 0;
  } catch (e) {
    if (e instanceof UsageError) { d.log(`refused: ${e.message}`); return 2; }
    throw e;
  } finally { rmSync(dl, { recursive: true, force: true }); }
}

export const CI_SUBS = ["wait", "budget", "circleci", "push", "telemetry", "pool", "state"] as const;

export async function ciCli(argv: string[], cwd: string, env: Record<string, string | undefined> = process.env): Promise<number> {
  const args = parseCiArgs(argv);
  const common = spawnSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).stdout.trim();
  const consoleDir = env.FW_CONSOLE_DIR ?? join(dirname(common), ".fw-console");
  return ciMain(args, { call: fwcoreCall(cwd), gh: chargedGh(realEnv(cwd)), store: args.store ?? storeDir(consoleDir), tmp: join(consoleDir, "tmp"), log: (l) => console.log(l) });
}

/** Sums the time between `loadStart` and `loadEnd` (the state-file read inside the gh-budget lock). I/O glue, no decision. */
export class LoadTimer {
  ms = 0;
  private at: number | null = null;
  constructor(private readonly clock: () => number = () => performance.now()) {}
  on(e: "loadStart" | "loadEnd"): void {
    if (e === "loadStart") this.at = this.clock();
    else if (this.at !== null) { this.ms += this.clock() - this.at; this.at = null; }
  }
}

/** Adds `ci state gh load` (Lean `ciStateLoadStep`) after the lock part and takes the same time out of the lock part, which includes it. */
export function withLoadPart(parts: { step: string; durMs: number }[], loadMs: number): { step: string; durMs: number }[] {
  const i = parts.findIndex((p) => p.step === "ci state gh lock");
  if (i < 0) return parts;
  const load = Math.min(Math.round(loadMs), parts[i]!.durMs);
  return [...parts.slice(0, i), { step: "ci state gh lock", durMs: parts[i]!.durMs - load }, { step: "ci state gh load", durMs: load }, ...parts.slice(i + 1)];
}

/** One span per part of `fw ci state`, each carrying the command's real exit (0 found, 2 not found, 1 a throw). */
export function recordStateParts(parts: { step: string; durMs: number }[], startMs: number, exit: number, rec: (s: StateSpan) => void): void {
  for (const p of parts) rec({ tool: "fw", step: p.step, startMs, durMs: p.durMs, exit });
}

export async function ciStateCli(argv: string[], cwd: string): Promise<number> {
  const usage = "usage: fw ci state <run id> [--branch <b>] [--workflow <w>]";
  const [id, ...rest] = argv;
  if (!id) throw new UsageError(usage);
  const o: { branch?: string; workflow?: string } = {};
  for (let i = 0; i < rest.length; i += 2) {
    const f = rest[i], v = rest[i + 1];
    if ((f !== "--branch" && f !== "--workflow") || v === undefined || v.startsWith("--")) throw new UsageError(usage);
    o[f === "--branch" ? "branch" : "workflow"] = v;
  }
  const clock = new GhClock();
  const load = new LoadTimer();
  const gh = chargedGh({ ...phasedEnv(realEnv(cwd), (e) => clock.on(e)), mark: (e) => load.on(e) });
  const t0 = performance.now(), startMs = Date.now();
  const timed: Gh = async (a, op) => { clock.start(); try { return await gh(a, op); } finally { clock.end(); } };
  let exit = 1; // a throw is a failure; the real exit of the command goes into every part span
  try {
    exit = await ciState(id, { gh: timed, log: (l) => console.log(l), ...o });
    return exit;
  } finally {
    recordStateParts(withLoadPart(ciStateParts(clock, performance.now() - t0), load.ms), startMs, exit, (sp) => record(sp, cwd));
  }
}
