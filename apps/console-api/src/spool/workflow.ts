// Workflow runs as agent events (task workflow-claim; Lean `Fw.Plan.Workflow`). Claude Code writes
// `<session>/workflows/scripts/<meta.name>-<runId>.js` when a Workflow run starts and `<session>/workflows/<runId>.json`
// when it ends. A run named like a task labels its run key `wf:<runId>` with the name and spawns it (then stops it once
// the run file exists). Task workflow-multi-claim: an agent labelled `<phase>:<task>` in
// `<session>/subagents/workflows/<runId>/journal.jsonl` binds `<task>` too, until its `result` line, through its own agent
// id (task-state-truth: a task name is only a label, never a life key). Only file names and the journal fields type/agentId/label are read, never
// script, result or transcript text.
// TS STAND-IN: `runsOf`/`wfEvents` mirror Lean `scriptRun`/`runFileId`/`wfEvents`; checked against
// packages/contracts/golden/plan/workflow.jsonl (test/workflow-claim.test.ts). Replace by an fwcore op when one exists.
import { existsSync, readdirSync, readFileSync } from "node:fs";
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

/** Lean `JLine`: one journal line (`started` carries the label; a `result` line ends the agent). */
export type JLine = { run: string; id: string; started: boolean; label: string };

/** The `JLine`s of one `journal.jsonl` text; lines that are not JSON or lack the fields are skipped. */
export function parseJournal(run: string, text: string): JLine[] {
  const out: JLine[] = [];
  for (const l of text.split("\n")) {
    let j: unknown;
    try { j = JSON.parse(l); } catch { continue; }
    if (typeof j !== "object" || j === null) continue;
    const o = j as Record<string, unknown>;
    if (typeof o.agentId !== "string" || (o.type !== "started" && o.type !== "result")) continue;
    out.push({ run, id: o.agentId, started: o.type === "started", label: o.type === "started" && typeof o.label === "string" ? o.label : "" });
  }
  return out;
}

/** One workflow event: a spawn or stop of a life key, or a label of a life key with a task name (Lean `wfEventJson`). The
 *  life key is a run key `wf:<runId>` or an agent id, never a task name (Lean `wfAllEvents_identity`). */
export type WfEvent =
  | { key: string; type: "agent.spawn" | "agent.stop"; agent: string }
  | { key: string; type: "agent.label"; agent: string; name: string };

/** Lean `runKey`: the life key of a run. */
export function runKey(run: string): string {
  return `wf:${run}`;
}

/** Lean `cmds` + `evKey`: label, spawn and (once ended) stop of life key `life`, labelled `name`; event keys
 *  `<pre>-label:<suf>`, `<pre>:<suf>`, `<pre>-end:<suf>`. */
function lifeEvents(pre: string, suf: string, life: string, name: string, ended: boolean): WfEvent[] {
  const out: WfEvent[] = [
    { key: `${pre}-label:${suf}`, type: "agent.label", agent: life, name },
    { key: `${pre}:${suf}`, type: "agent.spawn", agent: life },
  ];
  if (ended) out.push({ key: `${pre}-end:${suf}`, type: "agent.stop", agent: life });
  return out;
}

/** Lean `wfEvents`: events of the runs in `scripts` named like a task in `ids`; each (run, name) pair once. */
export function wfEvents(ids: readonly string[], scripts: readonly string[], runFiles: readonly string[]): WfEvent[] {
  return [...nameEvents(ids, scripts, runFiles)];
}

/** Lean `labelTask`: the non-empty text after the first `:`. */
export function labelTask(l: string): string | null {
  const i = l.indexOf(":");
  return i >= 0 && i + 1 < l.length ? l.slice(i + 1) : null;
}

/** Lean `wfAllEvents`: `wfEvents` then the events of the labelled agents (`wfAgents`, `WfAgent.cmds`, `agentEvents`). */
export function wfAllEvents(ids: readonly string[], scripts: readonly string[], runFiles: readonly string[], journal: readonly JLine[]): WfEvent[] {
  const ended = new Set(runFiles.map(runFileId).filter((r): r is string => r !== null));
  const out = nameEvents(ids, scripts, runFiles);
  const seen = new Set<string>();
  for (const j of journal) {
    if (!j.started || !RUN_ID.test(j.run)) continue;
    const k = `${j.run}\u0000${j.id}\u0000${j.label}`;
    if (seen.has(k)) continue;
    seen.add(k);
    const t = labelTask(j.label);
    if (t === null || !ids.includes(t)) continue;
    const done = ended.has(j.run) || journal.some((r) => !r.started && r.run === j.run && r.id === j.id);
    out.push(...lifeEvents("wfid", `${j.run}:${j.id}`, j.id, t, done));
  }
  return out;
}

function nameEvents(ids: readonly string[], scripts: readonly string[], runFiles: readonly string[]): WfEvent[] {
  const ended = new Set(runFiles.map(runFileId).filter((r): r is string => r !== null));
  const seen = new Set<string>();
  const out: WfEvent[] = [];
  for (const f of scripts) {
    const w = scriptRun(f);
    if (!w || seen.has(`${w.run}\u0000${w.name}`)) continue;
    seen.add(`${w.run}\u0000${w.name}`);
    if (!ids.includes(w.name)) continue;
    out.push(...lifeEvents("wfr", w.run, runKey(w.run), w.name, ended.has(w.run)));
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
  const jdir = join(dir, "..", "subagents", "workflows");
  const journal = ls(jdir).filter((r) => RUN_ID.test(r)).flatMap((r) => {
    try { return parseJournal(r, readFileSync(join(jdir, r, "journal.jsonl"), "utf8")); } catch { return []; }
  });
  return wfAllEvents(ids, ls(join(dir, "scripts")), ls(dir), journal);
}
