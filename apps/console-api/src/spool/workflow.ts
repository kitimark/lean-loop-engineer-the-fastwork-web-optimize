// Workflow runs as agent events (task workflow-claim; Lean `Fw.Plan.Workflow`). Claude Code writes
// `<session>/workflows/scripts/<meta.name>-<runId>.js` when a Workflow run starts and `<session>/workflows/<runId>.json`
// when it ends. A run named like a task labels its run key `wf:<runId>` with the name and spawns it (then stops it once
// the run file exists). Each agent of `<session>/subagents/workflows/<runId>/journal.jsonl` works on the run's name when
// that is a task id, whatever its label (task-state-truth round 5), and on `<task>` when labelled `<phase>:<task>`, until
// its `result` or `failed` line, through its own agent id (a task name is only a label, never a life key). Only file names and the journal fields type/agentId/label are read, never
// script, result or transcript text.
// TS STAND-IN: `runsOf`/`wfEvents` mirror Lean `scriptRun`/`runFileId`/`wfEvents`; checked against
// packages/contracts/golden/plan/workflow.jsonl (test/workflow-claim.test.ts). Replace by an fwcore op when one exists.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
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

/** Lean `JLine`: one journal line (`started` carries the label; a `result` or `failed` line ends the agent). */
export type JLine = { run: string; id: string; started: boolean; label: string };

/** The `JLine`s of one `journal.jsonl` text; lines that are not JSON or lack the fields are skipped. */
export function parseJournal(run: string, text: string): JLine[] {
  const out: JLine[] = [];
  for (const l of text.split("\n")) {
    let j: unknown;
    try { j = JSON.parse(l); } catch { continue; }
    if (typeof j !== "object" || j === null) continue;
    const o = j as Record<string, unknown>;
    if (typeof o.agentId !== "string" || (o.type !== "started" && o.type !== "result" && o.type !== "failed")) continue;
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

/** Lean `wfAllEvents`: `wfEvents` then the events of the run's agents (`wfAgents`, `WfAgent.tasks`, `WfAgent.cmds`,
 *  `runName`, `aKey`, `agentEvents`). */
export function wfAllEvents(ids: readonly string[], scripts: readonly string[], runFiles: readonly string[], journal: readonly JLine[]): WfEvent[] {
  const ended = new Set(runFiles.map(runFileId).filter((r): r is string => r !== null));
  const out = nameEvents(ids, scripts, runFiles);
  const seen = new Set<string>();
  for (const j of journal) {
    if (!j.started || !RUN_ID.test(j.run)) continue;
    const k = `${j.run}\u0000${j.id}\u0000${j.label}`;
    if (seen.has(k)) continue;
    seen.add(k);
    const rn = scripts.map(scriptRun).find((w) => w !== null && w.run === j.run)?.name ?? null;
    const tasks = [...new Set([rn, labelTask(j.label)].filter((t): t is string => t !== null && ids.includes(t)))];
    if (tasks.length === 0) continue;
    const done = ended.has(j.run) || journal.some((r) => !r.started && r.run === j.run && r.id === j.id);
    for (const t of tasks) out.push({ key: `wfid-label:${j.run}:${j.id}:${t}`, type: "agent.label", agent: j.id, name: t });
    out.push({ key: `wfid:${j.run}:${j.id}`, type: "agent.spawn", agent: j.id });
    if (done) out.push({ key: `wfid-end:${j.run}:${j.id}`, type: "agent.stop", agent: j.id });
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

/** A workflow event as submitted: a spawn or stop carries `at` (ms), the file time of the fact when one was readable. */
export type WfTimed = WfEvent | (Extract<WfEvent, { type: "agent.spawn" | "agent.stop" }> & { at: number });

/** The events of one `workflows/` dir (an unreadable dir gives none), each spawn and stop stamped with the time of its
 *  fact, never the read time: a run spawn at its script's mtime, a run stop at its run file's mtime; an agent spawn at
 *  its `agent-<id>.meta.json` mtime (written when the agent starts), else at the journal's birth time, else its mtime; an
 *  agent stop at the journal's mtime, or the run file's when later. Journal lines carry no time. So a journal first read
 *  after the agent's SubagentStop never gives a spawn later than that stop. */
export function scanWorkflows(dir: string, ids: readonly string[]): WfTimed[] {
  const ls = (d: string): string[] => { try { return readdirSync(d); } catch { return []; } };
  const st = (p: string): { birth: number; mtime: number } | null => {
    try { const s = statSync(p); return { birth: Math.floor(s.birthtimeMs), mtime: Math.floor(s.mtimeMs) }; } catch { return null; }
  };
  const jdir = join(dir, "..", "subagents", "workflows");
  const runs = ls(jdir).filter((r) => RUN_ID.test(r));
  const journal = runs.flatMap((r) => {
    try { return parseJournal(r, readFileSync(join(jdir, r, "journal.jsonl"), "utf8")); } catch { return []; }
  });
  const scripts = ls(join(dir, "scripts"));
  const runFiles = ls(dir);
  const at = new Map<string, number>();
  for (const f of scripts) { const w = scriptRun(f), t = st(join(dir, "scripts", f)); if (w && t) at.set(`wfr:${w.run}`, t.mtime); }
  const runEnd = new Map<string, number>();
  for (const f of runFiles) { const r = runFileId(f), t = st(join(dir, f)); if (r && t) { runEnd.set(r, t.mtime); at.set(`wfr-end:${r}`, t.mtime); } }
  const jt = new Map(runs.map((r) => [r, st(join(jdir, r, "journal.jsonl"))] as const));
  for (const j of journal) {
    const t = jt.get(j.run);
    const meta = st(join(jdir, j.run, `agent-${j.id}.meta.json`));
    const start = meta?.mtime ?? (t && t.birth > 0 && t.birth <= t.mtime ? t.birth : t?.mtime);
    if (start !== undefined) at.set(`wfid:${j.run}:${j.id}`, start);
    const end = Math.max(t?.mtime ?? -1, runEnd.get(j.run) ?? -1);
    if (end >= 0) at.set(`wfid-end:${j.run}:${j.id}`, end);
  }
  return wfAllEvents(ids, scripts, runFiles, journal).map((e) =>
    e.type === "agent.label" || !at.has(e.key) ? e : { ...e, at: at.get(e.key)! });
}
