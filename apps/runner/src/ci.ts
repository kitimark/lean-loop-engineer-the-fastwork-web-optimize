// `fw ci [<run id>] [--workflow chromium-counts] [--branch main] [--store <dir>]`: pull the artifacts of a finished
// chromium-counts run into the artifact store (`.fw-console/store/`), one store key per target in the run.
// The key, the manifest check, the object paths and the engine/target/preset/profile/image fields are fwcore's
// (`store.manifest`, via `ingest` in run.ts). TS-STAND-IN (to be replaced by a Lean op `store.ciRun`, asked of the lead):
// `selectCiRun` (which run is accepted, which shards must exist, the refusal reasons) and `searchConfig` (preset and flags
// from the rewrite query). Both are pure and table-tested in test/ci.test.ts. The rest is gh calls and file copies.
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { UsageError } from "./lib.ts";
import { fwcoreCall, ghCli, ingest, storeDir, type FwCall, type Gh } from "./run.ts";

export const CI_USAGE = "usage: fw ci [<run id>] [--workflow chromium-counts] [--branch main] [--store <dir>]\n" +
  "  without a run id: the latest run of the workflow on the branch. Refuses a run that did not succeed or lacks a shard.";

export type CiArgs = { runId?: string; workflow: string; branch: string; store?: string };
export function parseCiArgs(argv: string[]): CiArgs {
  const a: CiArgs = { workflow: "chromium-counts", branch: "main" };
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
  return a;
}

// ---- TS stand-in: the run selection rule ----------------------------------------------------------------------------
export type CiJob = { name: string; conclusion: string };
export type CiRunInfo = { runId: string; workflowName: string; status: string; conclusion: string; headSha: string; jobs: CiJob[] };
export type CiSelection = { ok: true; targets: { target: "original" | "rewrite"; shards: string[]; classes: string }[] } | { ok: false; refusals: string[] };

/**
 * Which part of a finished chromium-counts run is stored. Accepted: workflow chromium-counts, completed, success. Shards are
 * the jobs `counts (<target>, r<n>)`; each must have succeeded and have its artifact `chromium-counts-<target>-r<n>`, and
 * each target needs its `chromium-classes/<target>` directory. `have` = artifact names, `classDirs` = dirs under chromium-classes.
 */
export function selectCiRun(run: CiRunInfo, have: string[], classDirs: string[]): CiSelection {
  const refusals: string[] = [];
  if (run.workflowName !== "chromium-counts") refusals.push(`run ${run.runId} is workflow ${run.workflowName}, not chromium-counts`);
  if (run.status !== "completed") refusals.push(`run ${run.runId} is ${run.status}, not completed`);
  else if (run.conclusion !== "success") refusals.push(`run ${run.runId} concluded ${run.conclusion || "unknown"}, not success`);
  const shardJobs = run.jobs.flatMap((j) => { const m = /^counts \((original|rewrite), r([0-9]+)\)$/.exec(j.name); return m ? [{ target: m[1] as "original" | "rewrite", n: m[2]!, job: j }] : []; });
  if (shardJobs.length === 0) refusals.push(`run ${run.runId} has no counts shard jobs`);
  const targets = [...new Set(shardJobs.map((s) => s.target))].sort();
  const out = targets.map((target) => ({ target, shards: shardJobs.filter((s) => s.target === target).map((s) => `chromium-counts-${target}-r${s.n}`).sort(), classes: target }));
  for (const s of shardJobs) {
    const art = `chromium-counts-${s.target}-r${s.n}`;
    if (s.job.conclusion !== "success") refusals.push(`shard ${art}: job ${s.job.conclusion || "unfinished"}`);
    if (!have.includes(art)) refusals.push(`missing shard artifact ${art}`);
  }
  for (const t of targets) if (!classDirs.includes(t)) refusals.push(`missing chromium-classes/${t}`);
  return refusals.length ? { ok: false, refusals } : { ok: true, targets: out };
}

/** Preset and flags from the rewrite page query the workflow built: `""`, `?preset=p`, `?fw=a:x,b:y`, `?preset=p&fw=...`. */
export function searchConfig(search: string): { preset: string; fw: string[] } {
  const q = new URLSearchParams(search.startsWith("?") ? search.slice(1) : search);
  return { preset: q.get("preset") ?? "original", fw: (q.get("fw") ?? "").split(",").filter(Boolean) };
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

export function latestRunId(gh: Gh, workflow: string, branch: string): string | null {
  const rows = JSON.parse(gh(["run", "list", "--workflow", workflow, "--branch", branch, "--limit", "1", "--json", "databaseId"])) as { databaseId: number }[];
  return rows[0] ? String(rows[0].databaseId) : null;
}

/** The whole command. Exit code: 0 stored (or unchanged), 2 refused. */
export function ciMain(args: CiArgs, d: CiDeps): number {
  const runId = args.runId ?? latestRunId(d.gh, args.workflow, args.branch);
  if (!runId) { d.log(`refused: no run of ${args.workflow} on ${args.branch}`); return 2; }
  const v = JSON.parse(d.gh(["run", "view", runId, "--json", "workflowName,status,conclusion,headSha,jobs"])) as Omit<CiRunInfo, "runId">;
  const run: CiRunInfo = { runId, workflowName: v.workflowName, status: v.status, conclusion: v.conclusion, headSha: v.headSha, jobs: v.jobs.map((j) => ({ name: j.name, conclusion: j.conclusion })) };
  // Pre-check the run itself (assume the artifacts exist) so a failed run downloads nothing.
  const assumed = run.jobs.flatMap((j) => { const m = /^counts \((original|rewrite), (r[0-9]+)\)$/.exec(j.name); return m ? [`chromium-counts-${m[1]}-${m[2]}`] : []; });
  const pre = selectCiRun(run, assumed, ["original", "rewrite"]);
  if (!pre.ok) { for (const r of pre.refusals) d.log(`refused: ${r}`); return 2; }
  mkdirSync(d.tmp, { recursive: true });
  const dl = mkdtempSync(join(d.tmp, `ci-${runId}-`));
  try {
    d.gh(["run", "download", runId, "-D", dl, "--pattern", "chromium-counts-*", "--pattern", "chromium-classes"]);
    const have = readdirSync(dl);
    const cdir = join(dl, "chromium-classes");
    const classDirs = existsSync(cdir) ? readdirSync(cdir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name) : [];
    const sel = selectCiRun(run, have, classDirs);
    if (!sel.ok) { for (const r of sel.refusals) d.log(`refused: ${r}`); return 2; }
    for (const t of sel.targets) {
      const stage = join(dl, `stage-${t.target}`);
      const facts = t.shards.map((s) => {
        const c = JSON.parse(rd(join(dl, s, "counts.json"))) as { profile: { id: string }; meta: { search?: string; target?: string } };
        return { profile: c.profile.id, search: c.meta.search ?? "", target: c.meta.target ?? t.target, image: rd(join(dl, s, "image-id.txt")).trim() };
      });
      const f0 = facts[0]!;
      if (facts.some((f) => f.profile !== f0.profile || f.search !== f0.search || f.target !== f0.target || f.image !== f0.image)) {
        d.log(`refused: ${t.target} shards disagree on profile, query, target or image`);
        return 2;
      }
      for (const s of t.shards) copyTree(join(dl, s), stage, `${s.replace(/^chromium-counts-[a-z]+-/, "")}/`);
      copyTree(join(cdir, t.classes), stage, "classes/");
      writeFileSync(join(stage, "ci.json"), JSON.stringify({ schema: "fw.ci-run/1", workflow: run.workflowName, runId, headSha: run.headSha, conclusion: run.conclusion }, null, 2) + "\n");
      // An original run takes the default config; the query applies to the rewrite only.
      const cfg = t.target === "rewrite" ? searchConfig(f0.search) : { preset: "original", fw: [] };
      const r = ingest(d.call, d.store, stage, { engine: "chromium", image: f0.image } as never,
        { target: t.target, preset: cfg.preset, fw: cfg.fw, profile: f0.profile, gitSha: run.headSha, runId }, { keepSameRun: true });
      d.log(`${t.target}: run ${runId} ${run.conclusion} @ ${run.headSha.slice(0, 7)} key ${r.digest} ${r.unchanged ? "unchanged" : `stored, ${r.objects} new objects, ${r.reused} already stored`} (${r.manifest.entries.length} artifacts)`);
    }
    return 0;
  } catch (e) {
    if (e instanceof UsageError) { d.log(`refused: ${e.message}`); return 2; }
    throw e;
  } finally { rmSync(dl, { recursive: true, force: true }); }
}

export function ciCli(argv: string[], cwd: string, env: Record<string, string | undefined> = process.env): number {
  const args = parseCiArgs(argv);
  const common = spawnSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).stdout.trim();
  const consoleDir = env.FW_CONSOLE_DIR ?? join(dirname(common), ".fw-console");
  return ciMain(args, { call: fwcoreCall(cwd), gh: ghCli, store: args.store ?? storeDir(consoleDir), tmp: join(consoleDir, "tmp"), log: (l) => console.log(l) });
}
