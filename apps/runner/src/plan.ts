// `fw plan sync <work-graph.json>` and `fw plan show`.
// Sync only turns the file into typed commands (deps first, so the reducer's "dep must be defined" rule holds).
// Show only prints the board's `plan`, which fwcore derived. Neither decides anything about ready/blocked/done.
import { createHash } from "node:crypto";
import { Command, type Actor, type Plan } from "@fw/contracts";
import { UsageError } from "./lib.ts";

type GraphTask = {
  id: string; title: string; stream: string; milestone?: string | null; deps?: string[]; owner: string;
  writes?: string[]; devices?: string[]; evidence?: string | null;
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
      writes: t.writes ?? [], devices: t.devices ?? [], evidence: t.evidence ?? null };
    cmds.push(Command.parse({ type: "task.define", key: `plan:d:${t.id}:${digest(body)}`, actor, ...body }));
  }
  return cmds;
}

/** Text for `fw plan show`: ready (by parallel-safe group), running, blocked (with blockers), critical path. */
export function renderPlan(p: Plan): string {
  const byId = new Map(p.tasks.map((t) => [t.id, t]));
  const count = (s: string) => p.tasks.filter((t) => t.state === s).length;
  const L: string[] = [`${p.tasks.length} tasks: ${count("done")} done, ${count("running")} running, ${count("ready")} ready, ${count("blocked")} blocked`];
  for (const m of p.milestones) L.push(`  ${m.id} ${m.done}/${m.total}  ${m.title.slice(0, 70)}`);
  L.push("READY (tasks in one group can run in parallel):");
  p.parallelSafe.forEach((g, i) => L.push(`  group ${i + 1}: ${g.join(", ")}`));
  if (p.parallelSafe.length === 0) L.push("  none");
  L.push("RUNNING:");
  for (const t of p.tasks.filter((x) => x.state === "running")) L.push(`  ${t.id} (agent ${t.agent ?? "?"})`);
  L.push("BLOCKED (waiting on):");
  for (const t of p.tasks.filter((x) => x.state === "blocked")) L.push(`  ${t.id} <- ${t.blockers.join(", ")}`);
  L.push(`CRITICAL PATH (${p.criticalPath.length}): ${p.criticalPath.map((id) => byId.get(id)?.id ?? id).join(" -> ") || "none"}`);
  return L.join("\n");
}
