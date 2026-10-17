// Workflow runs as agent events (task workflow-claim; Lean `Fw.Plan.Workflow`). Claude Code writes
// `<session>/workflows/scripts/<meta.name>-<runId>.js` when a Workflow run starts and `<session>/workflows/<runId>.json`
// when it ends. A run named like a task gives `agent.spawn` (then `agent.stop` once the run file exists), keyed by the run
// id. Only file names are read, never script text.
// TS STAND-IN: `runsOf`/`wfEvents` mirror Lean `scriptRun`/`runFileId`/`wfEvents`; checked against
// packages/contracts/golden/plan/workflow.jsonl (test/workflow-claim.test.ts). Replace by an fwcore op when one exists.
import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const RUN_ID = /^wf_[0-9a-f]{8}-[0-9a-f]{3}$/;

/** Lean `scriptRun`: `<name>-<runId>.js` with a non-empty name; the run id is the fixed-width tail. */
export function scriptRun(f: string): { name: string; run: string } | null {
  const m = /^(.+)-(wf_[0-9a-f]{8}-[0-9a-f]{3})\.js$/s.exec(f);
  return m && RUN_ID.test(m[2]!) ? { name: m[1]!, run: m[2]! } : null;
}

/** Lean `runFileId`: `<runId>.json`. */
export function runFileId(f: string): string | null {
  return f.endsWith(".json") && RUN_ID.test(f.slice(0, -5)) ? f.slice(0, -5) : null;
}

export type WfEvent = { key: string; type: "agent.spawn" | "agent.stop"; agent: string };

/** Lean `wfEvents`: events of the runs in `scripts` named like a task in `ids`; each (run, name) pair once. */
export function wfEvents(ids: readonly string[], scripts: readonly string[], runFiles: readonly string[]): WfEvent[] {
  const ended = new Set(runFiles.map(runFileId).filter((r): r is string => r !== null));
  const seen = new Set<string>();
  const out: WfEvent[] = [];
  for (const f of scripts) {
    const w = scriptRun(f);
    if (!w || seen.has(`${w.run}\u0000${w.name}`)) continue;
    seen.add(`${w.run}\u0000${w.name}`);
    if (!ids.includes(w.name)) continue;
    out.push({ key: `wf:${w.run}`, type: "agent.spawn", agent: w.name });
    if (ended.has(w.run)) out.push({ key: `wf-end:${w.run}`, type: "agent.stop", agent: w.name });
  }
  return out;
}

/** The `workflows/` dirs to watch: `FW_WORKFLOWS_DIR` (colon separated) or every session of this checkout under
 *  `~/.claude/projects/<slug>/` (the slug is the root path with every non-alphanumeric turned into `-`). */
export function workflowDirs(root: string, env: NodeJS.ProcessEnv = process.env, home = homedir()): string[] {
  if (env.FW_WORKFLOWS_DIR) return env.FW_WORKFLOWS_DIR.split(":").filter(Boolean);
  const proj = join(home, ".claude", "projects", root.replace(/[^A-Za-z0-9]/g, "-"));
  try {
    return readdirSync(proj, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => join(proj, d.name, "workflows"))
      .filter((d) => existsSync(d));
  } catch { return []; }
}

/** The events of one `workflows/` dir (an unreadable dir gives none). */
export function scanWorkflows(dir: string, ids: readonly string[]): WfEvent[] {
  const ls = (d: string): string[] => { try { return readdirSync(d); } catch { return []; } };
  return wfEvents(ids, ls(join(dir, "scripts")), ls(dir));
}
