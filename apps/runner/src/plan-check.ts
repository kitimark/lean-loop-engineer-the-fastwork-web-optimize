// Schema check of docs/team/work-graph.json for the pre-commit checkmap (task graph-schema-precommit). It runs the
// same conversion `fw plan sync` and plan.test run (syncCommands, so the contract's Command schema is the one source of
// every limit) and names the task and field of each refusal. Glue only; no limit is written here.
import { syncCommands, type WorkGraph } from "./plan.ts";

/** One problem per line: `<task id>: <field path>: <message>`, or `<graph>: ...` when no single task is at fault. */
export function checkGraph(text: string): string[] {
  let g: WorkGraph;
  try { g = JSON.parse(text) as WorkGraph; } catch (e) { return [`<graph>: json: ${(e as Error).message}`]; }
  if (!Array.isArray(g.tasks) || !Array.isArray(g.milestones)) return ["<graph>: tasks/milestones: not arrays"];
  const out: string[] = [];
  const why = (id: string, e: unknown) => {
    const issues = (e as { issues?: { path: PropertyKey[]; message: string }[] }).issues;
    if (!issues) { out.push(`${id}: ${(e as Error).message}`); return; }
    for (const i of issues) out.push(`${id}: ${i.path.map(String).join(".") || "(task)"}: ${i.message}`);
  };
  for (const m of g.milestones) { try { syncCommands({ milestones: [m], tasks: [] }); } catch (e) { why(`milestone ${m.id}`, e); } }
  // one task at a time (its deps stood in by bare stubs), so a task's own field failure is named by its id
  const stub = (id: string) => ({ id, title: "stub", stream: "s", owner: "o", deps: [] as string[] });
  for (const t of g.tasks) {
    const deps = Array.isArray(t.deps) ? t.deps.filter((d) => d !== t.id) : [];
    try { syncCommands({ milestones: [], tasks: [...new Set(deps)].map(stub).concat({ ...t, deps }) }); } catch (e) { why(String(t.id), e); }
  }
  if (out.length === 0) { try { syncCommands(g); } catch (e) { why("<graph>", e); } }
  return out;
}
