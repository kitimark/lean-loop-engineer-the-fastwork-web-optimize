// `fw plan sync <work-graph.json>` and `fw plan show`.
// Sync only turns the file into typed commands (deps first, so the reducer's "dep must be defined" rule holds).
// Show only prints the board's `plan`, which fwcore derived. Neither decides anything about ready/blocked/done.
import { createHash } from "node:crypto";
import { Command, type Actor, type Plan } from "@fw/contracts";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { UsageError } from "./lib.ts";
import { coreCandidates, coreCaller, type CoreCall } from "./watch.ts";

type GraphTask = {
  id: string; title: string; stream: string; milestone?: string | null; deps?: string[]; owner: string;
  writes?: string[]; devices?: string[]; needs?: string[]; evidence?: string | null; cut?: boolean;
};
export type WorkGraph = { milestones: { id: string; title: string }[]; tasks: GraphTask[] };

/** Dependencies first (Kahn, ties keep file order). Throws on a cycle or an unknown dep, naming the tasks. */
export function topoSort(tasks: GraphTask[]): GraphTask[] {
  const byId = new Map(tasks.map((t) => [t.id, t]));
  for (const t of tasks) for (const d of t.deps ?? []) if (!byId.has(d)) throw new UsageError(`task ${t.id}: dep ${d} is not in the graph`);
  const out: GraphTask[] = [];
  const placed = new Set<string>();
  while (out.length < tasks.length) {
    const next = tasks.find((t) => !placed.has(t.id) && (t.deps ?? []).every((d) => placed.has(d)));
    if (!next) throw new UsageError(`dependency cycle among: ${tasks.filter((t) => !placed.has(t.id)).map((t) => t.id).join(", ")}`);
    out.push(next); placed.add(next.id);
  }
  return out;
}

/** The contract caps titles at 200 characters; a longer one is clipped here (the file keeps the full text). */
const clip = (s: string) => (s.length <= 200 ? s : `${s.slice(0, 199)}…`);
const digest = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex").slice(0, 10);

/** Commands for the whole file: milestones, then tasks in dependency order. The key carries a digest of the content,
 *  so re-syncing an unchanged file is a no-op (duplicate) and an edited task is a new upsert. */
export function syncCommands(g: WorkGraph, actor: Actor = "lead"): Command[] {
  const cmds: Command[] = [];
  for (const m of g.milestones) {
    cmds.push(Command.parse({ type: "milestone.define", key: `plan:m:${m.id}:${digest([m.id, m.title])}`, actor, milestone: m.id, title: clip(m.title) }));
  }
  for (const t of topoSort(g.tasks)) {
    const body = { task: t.id, title: clip(t.title), stream: t.stream, milestone: t.milestone ?? null, deps: t.deps ?? [], owner: t.owner,
      writes: t.writes ?? [], devices: t.devices ?? [],
      // only when present, so a task without needs keeps its key (digest) from before the field existed
      ...(t.needs?.length ? { needs: t.needs } : {}), evidence: t.evidence ?? null,
      // likewise only when true (a task cut from the plan: fwcore derives state "cut")
      ...(t.cut ? { cut: true } : {}) };
    cmds.push(Command.parse({ type: "task.define", key: `plan:d:${t.id}:${digest(body)}`, actor, ...body }));
  }
  return cmds;
}

/** Text for `fw plan show`: agent-ready (by parallel-safe group), the device lane (ready, then blocked with blockers),
 *  running, agent-blocked (with blockers), critical path, cut. Lane, state, blockers and groups all come from fwcore. */
export function renderPlan(p: Plan): string {
  const byId = new Map(p.tasks.map((t) => [t.id, t]));
  const count = (s: string) => p.tasks.filter((t) => t.state === s).length;
  const L: string[] = [`${p.tasks.length} tasks: ${count("done")} done, ${count("running")} running, ${count("ready")} ready, ${count("blocked")} blocked, ${count("cut")} cut`];
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

/** `fw plan lint <work-graph.json>`: exit code 1 when fwcore finds errors. */
export async function lintCli(args: string[], cwd: string, core?: CoreCall, commits?: { sha: string; body: string }[]): Promise<number> {
  if (!args[0]) throw new UsageError("usage: fw plan lint <work-graph.json>");
  const g = JSON.parse(readFileSync(args[0], "utf8")) as WorkGraph;
  const root = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).trim();
  const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).trim();
  const call = core ?? coreCaller(coreCandidates(root, join(common, "..")));
  const r = (await call({ op: "plan.lint",
    tasks: g.tasks.map((t) => ({ id: t.id, title: t.title, deps: t.deps ?? [], evidence: t.evidence ?? null })),
    commits: commits ?? mainCommits(cwd) })) as unknown as LintReply;
  console.log(renderLint(r));
  return r.ok ? 0 : 1;
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

/** Plan sync through the plain command door (no capability), for `fw land`'s internal sync: the single-use capability
 *  of the `pnpm fw land ...` call may already be spent on a card's land request, and the hook only mints one for a
 *  command that starts with `pnpm fw`. The caller has checked `syncRefusal`. Throws when a command was refused. */
export async function syncViaCommands(http: { post(path: string, body: unknown): Promise<{ status: number; body: any }> }, g: WorkGraph): Promise<string> {
  let applied = 0, unchanged = 0;
  for (const c of syncCommands(g)) {
    const r = await http.post("/api/commands", c);
    if (r.body?.ok) { if (r.body.duplicate) unchanged++; else applied++; }
    else throw new Error(`plan sync refused ${c.type}: ${r.body?.reason ?? r.status}`);
  }
  return `plan sync: ${applied} applied, ${unchanged} unchanged`;
}
