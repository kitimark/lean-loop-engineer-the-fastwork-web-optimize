// `fw plan sync <work-graph.json>` and `fw plan show`.
// Sync only turns the file into typed commands (deps first, so the reducer's "dep must be defined" rule holds).
// Show only prints the board's `plan`, which fwcore derived. Neither decides anything about ready/blocked/done.
import { createHash } from "node:crypto";
import {
  type Command, type Actor, type Plan, type PlanTask, type ContentDigest, type GraphTask, type WorkGraph, type OnMain,
  topoSort as sharedTopoSort, syncCommands as sharedSyncCommands,
} from "@fw/contracts";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { UsageError } from "./lib.ts";
import { onMainSet } from "../../console-api/src/reconcile/git.ts";
import { coreCandidates, coreCaller, type CoreCall } from "./watch.ts";
import { lintClosure, scopeBatch, type ScopeBatch } from "./plan-closure.ts";

export type { WorkGraph } from "@fw/contracts";

export const PLAN_SUBS = ["sync", "show", "lint", "overlap"] as const;

export const digest: ContentDigest = (v) => createHash("sha256").update(JSON.stringify(v)).digest("hex").slice(0, 10);
const usage = (m: string) => new UsageError(m);

/** Dependencies first (Kahn, ties keep file order). Throws a UsageError on a cycle or an unknown dep, naming the tasks.
 *  The shared implementation lives in @fw/contracts (the console reconciler syncs with the same code). */
export const topoSort = (tasks: GraphTask[]): GraphTask[] => sharedTopoSort(tasks, usage);

/** Commands for the whole file: milestones, then tasks in dependency order. The key carries a digest of the content,
 *  so re-syncing an unchanged file is a no-op (duplicate) and an edited task is a new upsert. */
export const syncCommands = (g: WorkGraph, actor: Actor = "lead", onMain?: OnMain): Command[] =>
  sharedSyncCommands(g, actor, digest, usage, onMain);

/** The ancestry fact for plan sync and lint: membership in one `git rev-list <main>` read lazily in `cwd` (an unknown
 *  sha is not on main). Glue only; Lean decides what an off-main sha means. */
export const gitOnMain = (cwd: string, main = "main"): OnMain => {
  let test: ((sha: string) => boolean) | null = null;
  return (sha) => (test ??= onMainSet(cwd, main))(sha);
};
/** Glue filter as in @fw/contracts plan-sync: only strings that can be a commit id are asked about. */
const shaLike = (e: string) => /^[0-9a-f]{7,40}$/.test(e) && !/^[0-9]{8,}$/.test(e);

/** Text for `fw plan show`: agent-ready (by parallel-safe group), the device lane (ready, then blocked with blockers),
 *  running, agent-blocked (with blockers), critical path, cut. Lane, state, blockers and groups all come from fwcore. */
/** One line for an outcome mark (display only). */
export function outcomeText(o: PlanTask["outcome"]): string {
  if (!o) return "";
  if (o.kind === "handedBack") return `by ${o.agent}${o.tip ? ` at ${o.tip}` : ", no commit"}`;
  if (o.kind === "integrated") return `into ${o.branch} at ${o.tip}`;
  return o.reason;
}

export function renderPlan(p: Plan): string {
  const byId = new Map(p.tasks.map((t) => [t.id, t]));
  const count = (s: string) => p.tasks.filter((t) => t.state === s).length;
  const L: string[] = [`${p.tasks.length} tasks: ${count("done")} done, ${count("running")} running, ${count("handedBack")} handed back, ${count("integrated")} integrated, ${count("parked")} parked, ${count("ready")} ready, ${count("blocked")} blocked, ${count("cut")} cut`];
  for (const m of p.milestones) L.push(`  ${m.id} ${m.done}/${m.total}  ${m.title.slice(0, 70)}`);
  L.push("READY (tasks in one group can run in parallel):");
  p.parallelSafe.forEach((g, i) => L.push(`  group ${i + 1}: ${g.join(", ")}`));
  if (p.parallelSafe.length === 0) L.push("  none");
  L.push("DEVICE (needs you + the iPhone):");
  const dev = p.tasks.filter((x) => x.lane === "device");
  for (const t of dev.filter((x) => x.state === "ready")) L.push(`  ready    ${t.id}  ${t.title.slice(0, 90)}`);
  for (const t of dev.filter((x) => x.state === "blocked")) L.push(`  blocked  ${t.id} <- ${t.blockers.join(", ")}`);
  if (!dev.some((x) => x.state === "ready" || x.state === "blocked")) L.push("  none");
  L.push("RUNNING:");
  for (const t of p.tasks.filter((x) => x.state === "running")) L.push(`  ${t.id} (agent ${t.agent ?? "?"})`);
  // task-state-truth: tasks whose agents ended, with where the work went (the outcome mark fwcore derived)
  const ended = p.tasks.filter((x) => x.state === "handedBack" || x.state === "integrated" || x.state === "parked");
  if (ended.length > 0) L.push(`ENDED, NOT LANDED (${ended.length}):`);
  for (const t of ended) L.push(`  ${t.state.padEnd(10)} ${t.id}  ${outcomeText(t.outcome)}`);
  L.push("BLOCKED (waiting on):");
  for (const t of p.tasks.filter((x) => x.state === "blocked" && x.lane === "agent")) L.push(`  ${t.id} <- ${t.blockers.join(", ")}`);
  L.push(`CRITICAL PATH (${p.criticalPath.length}): ${p.criticalPath.map((id) => byId.get(id)?.id ?? id).join(" -> ") || "none"}`);
  const cut = p.tasks.filter((x) => x.state === "cut").map((x) => x.id);
  L.push(`CUT (${cut.length}): ${cut.join(", ") || "none"}`);
  return L.join("\n");
}

export type LintFinding = { task: string; code: string; severity: string; detail: string };
export type LintReply = { ok: boolean; errors: number; warnings: number; infos: number; findings: LintFinding[] };

/** Text for `fw plan lint`: errors and warnings one per line, info findings only counted. Severity, codes and
 *  the exit decision all come from fwcore (`plan.lint`); this only prints. */
export function renderLint(r: LintReply): string {
  const L = r.findings.filter((f) => f.severity !== "info").map((f) => `${f.severity.padEnd(5)} ${f.task} ${f.code}${f.detail ? `: ${f.detail.slice(0, 90)}` : ""}`);
  L.push(`plan lint: ${r.errors} errors, ${r.warnings} warnings, ${r.infos} info (evidence without a Task: trailer on main)`);
  if (r.findings.some((f) => f.code === "evNotOnMain")) L.push("evNotOnMain: the evidence commit is not on main yet; plan sync refuses that define until it lands");
  if (r.findings.some((f) => f.code.startsWith("writesClosure"))) L.push("writesClosure: add the named path to the row's writes before the build starts; fw land refuses it otherwise (Open: only if the glob adds a file)");
  return L.join("\n");
}

/** First-parent history of `ref`, newest first, as the {sha, body} pairs `plan.trailers` and `plan.lint` read. */
export function mainCommits(cwd: string, ref = "main"): { sha: string; body: string }[] {
  const out = execFileSync("git", ["log", ref, "--first-parent", "--format=%H%x1f%B%x1e"], { cwd, encoding: "utf8", maxBuffer: 1 << 28 });
  return out.split("\x1e").map((x) => x.replace(/^\n/, "")).filter(Boolean).map((x) => {
    const i = x.indexOf("\x1f");
    return { sha: x.slice(0, i), body: x.slice(i + 1) };
  });
}

/** `fw plan lint <work-graph.json>`: exit code 1 when fwcore finds errors or an open row misses a path of its writes
 *  closure (`Fw.Plan.WritesClosure`, checked against the tracked files). */
export async function lintCli(args: string[], cwd: string, core?: CoreCall, commits?: { sha: string; body: string }[], onMain?: OnMain,
  closure?: { tracked: string[]; batch: ScopeBatch }): Promise<number> {
  if (!args[0]) throw new UsageError("usage: fw plan lint <work-graph.json>");
  const g = JSON.parse(readFileSync(args[0], "utf8")) as WorkGraph;
  const root = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).trim();
  const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).trim();
  const call = core ?? coreCaller(coreCandidates(root, join(common, "..")));
  const om = onMain ?? gitOnMain(cwd);
  const r = (await call({ op: "plan.lint",
    tasks: g.tasks.map((t) => {
      const off = !!t.evidence && shaLike(t.evidence) && !om(t.evidence);
      return { id: t.id, title: t.title, deps: t.deps ?? [], evidence: t.evidence ?? null, ...(off ? { evidenceOnMain: false } : {}) };
    }),
    commits: commits ?? mainCommits(cwd) })) as unknown as LintReply;
  const tracked = closure?.tracked ?? execFileSync("git", ["ls-files"], { cwd: root, encoding: "utf8", maxBuffer: 1 << 28 }).split("\n").filter(Boolean);
  const cs = await lintClosure(g.tasks.map((t) => ({ id: t.id, owner: t.owner, stream: t.stream, writes: t.writes ?? [], done: !!t.evidence || !!t.cut })),
    tracked, closure?.batch ?? scopeBatch(coreCandidates(root, join(common, ".."))));
  const errs = cs.filter((f) => f.severity === "error").length;
  const all: LintReply = { ...r, ok: r.ok && errs === 0, errors: r.errors + errs, warnings: r.warnings + cs.length - errs, findings: [...r.findings, ...cs] };
  console.log(renderLint(all));
  return all.ok ? 0 : 1;
}

/** `fw plan sync` is the live board's only input from the file, so it runs only in the main checkout with HEAD = main:
 *  a draft branch (or a linked worktree) can never reach the board. Returns the refusal, or null when allowed. */
export function syncRefusal(cwd: string, main = "main"): string | null {
  const q = (...a: string[]) => { try { return execFileSync("git", a, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim(); } catch { return null; } };
  const top = q("rev-parse", "--show-toplevel");
  const common = q("rev-parse", "--path-format=absolute", "--git-common-dir");
  if (!top || !common) return "plan sync: not inside a git checkout";
  if (resolve(common, "..") !== resolve(top)) return `plan sync refused: ${top} is a linked worktree; run it in the main checkout ${resolve(common, "..")}`;
  const head = q("symbolic-ref", "--short", "-q", "HEAD");
  if (head !== main) return `plan sync refused: HEAD is ${head ?? "detached"}, not ${main}; drafts never reach the live board`;
  return null;
}
