// Collectors for `fw watch`: read-only, stdlib only. They turn spools, transcripts and the machine into the
// obs.health snapshot (lean/Fw/Wire/Obs.lean). No health decision is made here: states and alerts come from fwcore.
// Scoping rules that ARE here (which agents get into the snapshot): see SCOPE below.
// Privacy: only names, counts, ids and times are read out of the files; payload text is never kept.
import { execFile } from "node:child_process";
import { ghCharged, realEnv, type Env } from "@fw/gh-budget";
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, statfsSync, writeFileSync } from "node:fs";
import { homedir, loadavg } from "node:os";
import { basename, dirname, join } from "node:path";

export interface SpoolEvent {
  agent_id: string | null; agent_type: string | null; hook_event_name: string;
  tool_name: string | null; tool_use_id: string | null; duration_ms: number | null;
  is_error: boolean | null; verb: string | null; ts: number;
}
export interface Tokens { in: number; out: number; cacheRead: number; cacheWrite: number }
/** Agent kinds on the wire (Fw.Obs.Health.Kind; the lead is not an agent row here, it is `Snapshot.lead`). */
export type Kind = "teammate" | "subagent" | "workflow";
export interface TranscriptInfo {
  name: string | null; task: string | null; type: string | null; model: string | null; teammate: boolean;
  workflowPhase: boolean; toolUseId: string | null; agentCalls: string[];
  finished: boolean; endedTurn: boolean; toolUses: number; toolErrors: number; firstAt: number | null; lastAt: number | null;
  lastTool: string | null; lastToolAt: number | null;
  ctxTokens: number | null; tokens: Tokens; inflight: { tool: string; verb: null; since: number } | null;
  /** ids of the Bash tasks this agent started (`toolUseResult.backgroundTaskId`: run in the background, or moved
   *  there after the 10-min timeout); their shells write to `<session>/tasks/<id>.output` */
  bgTasks: string[];
}
export interface AgentSnap {
  id: string; name: string | null; task: string | null; type: string | null; model: string | null; kind: Kind;
  parent: string | null; startedAt: number; lastAt: number; stoppedAt: number | null; tools: number; errors: number;
  errTail: number; inflight: { tool: string; verb: string | null; since: number } | null;
  lastTool: string | null; lastToolAt: number | null; idleAt: number | null; workflowDone: boolean; transcriptOnly: boolean;
  ctxTokens: number | null; tokens: Tokens;
}
/** The lead session's facts (spool/main.jsonl): its last tool event and its last Notification. */
export interface LeadSnap { lastToolAt: number | null; noteAt: number | null }
/** A process tree this Claude session started through its Bash tool: root shell pid, the first non-shell program's
 *  name (executable basename only, never arguments), start time, every descendant pid, and the id of the agent whose
 *  Bash call started it (absent or null: the lead session, or not known) */
export interface Proc { pid: number; name: string; startedAt: number; pids: number[]; agent?: string | null }
export interface SystemSnap {
  load1: number; memPressure: "normal" | "warn" | "critical"; diskFreeGB: number;
  simLock: { holder: string | null; since: number | null };
  docker: { id: string; name: string; startedAt: number }[]; worktrees: number; consolePids: number[];
  ci: { id?: number; workflow: string; branch: string; status: string; conclusion: string | null; startedAt: number; endedAt?: number | null }[];
  /** floor of the 1-min load average (fwcore compares it with loadMax) */
  loadFloor?: number;
  /** process trees this Claude session started through its Bash tool: root shell pid, the first non-shell program's
   *  name (executable basename only, never arguments), start time, and every descendant pid */
  procs?: Proc[];
  /** pids that are services, not session work: this `fw watch` process and console-api (a tree holding one is exempt) */
  services?: number[];
  /** pids the lead declared as intended long-runners (`fw watch --keep`, .fw-console/keep.json), still running */
  keep?: number[];
  /** collectors that failed this time and whose value was carried forward from the previous check
   *  ("ci", "docker", "procs", "plan") */
  stale: string[];
}
export interface Snapshot {
  now: number; params: Record<string, number>; agents: AgentSnap[]; lead: LeadSnap; system: SystemSnap;
  /** time of the previous check (null: first check); fwcore raises agent.gone and ci.finished once against it */
  prevAt?: number | null;
  /** task ids on the critical path (GET /api/plan .criticalPath); their agents' and ci/<task> runs' alerts rank first */
  critical?: string[];
}

// SCOPE (collection only, not health decisions): an agent with no SubagentStop and no activity for 24 h is
// treated as ended (its hooks never fired Stop); ended agents are dropped from the snapshot 1 h after they ended.
// A failed gh/docker collector carries the previous check's value forward only if that check is <= 1 h old.
export const SCOPE = { ghostMs: 24 * 3600_000, keepDoneMs: 3600_000, carryMs: 3600_000 };

export const DEFAULT_PARAMS = {
  idleMin: 10, stallMin: 20, toolHangMin: 30, errStreak: 3, ctxResumeMax: 250000, ctxWarn: 200000,
  diskMinGB: 20, agentCap: 10, simLockMaxMin: 30, worktreesMax: 20, wfQuietMin: 30,
  goneAfterMin: 120, ciSlowMin: 20, toolSlowMin: 15, procMaxMin: 20, loadMax: 150,
};

const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);
const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

export function parseSpool(text: string): SpoolEvent[] {
  const out: SpoolEvent[] = [];
  for (const line of text.split("\n")) {
    if (!line) continue;
    try {
      const o = JSON.parse(line);
      if (o && typeof o.hook_event_name === "string" && typeof o.ts === "number") out.push(o as SpoolEvent);
    } catch { /* a torn last line is skipped */ }
  }
  return out;
}

export interface SpoolSummary {
  agentType: string | null; startedAt: number | null; lastAt: number | null; stoppedAt: number | null;
  tools: number; errors: number; errTail: number;
  /** the newest finished tool call (PostToolUse/PostToolUseFailure): its tool name and time */
  lastTool: string | null; lastToolAt: number | null;
  /** the newest TeammateIdle (only teammates fire it) */
  idleAt: number | null;
}
export function summarizeSpool(events: SpoolEvent[]): SpoolSummary {
  const s: SpoolSummary = { agentType: null, startedAt: null, lastAt: null, stoppedAt: null, tools: 0, errors: 0, errTail: 0, lastTool: null, lastToolAt: null, idleAt: null };
  let lastActive = -1;
  for (const e of events) {
    s.agentType ||= str(e.agent_type);
    if (s.startedAt === null || e.ts < s.startedAt) s.startedAt = e.ts;
    if (s.lastAt === null || e.ts > s.lastAt) s.lastAt = e.ts;
    const h = e.hook_event_name;
    if (h === "SubagentStart") lastActive = Math.max(lastActive, e.ts);
    if (h === "SubagentStop") s.stoppedAt = Math.max(s.stoppedAt ?? 0, e.ts);
    if (h === "TeammateIdle") s.idleAt = Math.max(s.idleAt ?? 0, e.ts);
    if (h === "PostToolUse" || h === "PostToolUseFailure") {
      s.tools++;
      const bad = h === "PostToolUseFailure" || e.is_error === true;
      if (bad) s.errors++;
      s.errTail = bad ? s.errTail + 1 : 0;
      lastActive = Math.max(lastActive, e.ts);
      if (s.lastToolAt === null || e.ts >= s.lastToolAt) { s.lastToolAt = e.ts; s.lastTool = str(e.tool_name); }
    }
  }
  // a Start or a tool call after the last Stop means it was resumed
  if (s.stoppedAt !== null && lastActive > s.stoppedAt) s.stoppedAt = null;
  // a teammate fires SubagentStop at the end of each turn and then TeammateIdle: that is a pause, not an exit
  // (fwcore then sees idleAt newer than lastToolAt: parked)
  if (s.stoppedAt !== null && s.idleAt !== null && s.idleAt >= s.stoppedAt) s.stoppedAt = null;
  return s;
}

/** The lead session's facts from spool/main.jsonl (events with no agent_id): the newest tool event and the newest
 *  Notification. A Notification there has no agent_id, so it cannot be tied to an agent (fwcore: team.permissionWait). */
export function summarizeLead(events: SpoolEvent[]): LeadSnap {
  const l: LeadSnap = { lastToolAt: null, noteAt: null };
  for (const e of events) {
    if (e.agent_id) continue;
    const h = e.hook_event_name;
    if (h === "PostToolUse" || h === "PostToolUseFailure") l.lastToolAt = Math.max(l.lastToolAt ?? 0, e.ts);
    if (h === "Notification") l.noteAt = Math.max(l.noteAt ?? 0, e.ts);
  }
  return l;
}

/** Summarize one subagent transcript (+ meta). Only usage numbers, model, tool names/ids and times are kept. */
export function summarizeTranscript(jsonl: string, meta: Record<string, unknown> | null): TranscriptInfo {
  const info: TranscriptInfo = {
    name: str(meta?.name), task: str(meta?.description), type: str(meta?.agentType), model: null,
    teammate: (str(meta?.taskKind) ?? "").includes("teammate"), workflowPhase: meta?.workflowPhase != null,
    toolUseId: str(meta?.toolUseId), agentCalls: [], bgTasks: [],
    finished: meta?.finished === true, endedTurn: false, toolUses: 0, toolErrors: 0,
    firstAt: null, lastAt: null, lastTool: null, lastToolAt: null, ctxTokens: null,
    tokens: { in: 0, out: 0, cacheRead: 0, cacheWrite: 0 }, inflight: null,
  };
  const usageById = new Map<string, Record<string, unknown>>();
  const open = new Map<string, { tool: string; at: number }>();
  let lastUsage: Record<string, unknown> | null = null;
  let endedTurn = false;
  let structDone = false; // a workflow agent ends by calling StructuredOutput
  let n = 0;
  for (const line of jsonl.split("\n")) {
    if (!line) continue;
    let o: any;
    try { o = JSON.parse(line); } catch { continue; }
    const at = typeof o.timestamp === "string" ? Date.parse(o.timestamp) : NaN;
    if (Number.isFinite(at)) { info.firstAt ??= at; info.lastAt = Math.max(info.lastAt ?? 0, at); }
    const m = o.message;
    const bg = str(o.toolUseResult?.backgroundTaskId);
    if (bg) info.bgTasks.push(bg);
    if (o.type === "assistant" && m) {
      if (typeof m.model === "string" && m.model !== "<synthetic>") info.model = m.model;
      if (m.usage && typeof m.usage === "object") {
        usageById.set(typeof m.id === "string" ? m.id : `#${n++}`, m.usage); // streamed copies share the id
        lastUsage = m.usage;
      }
    }
    if ((o.type === "assistant" || o.type === "user") && Array.isArray(m?.content)) {
      let hasUse = false;
      for (const c of m.content) {
        if (c?.type === "tool_use" && typeof c.id === "string") {
          hasUse = true; info.toolUses++;
          const tool = String(c.name ?? "?"), t = Number.isFinite(at) ? at : 0;
          open.set(c.id, { tool, at: t });
          if (info.lastToolAt === null || t >= info.lastToolAt) { info.lastTool = tool; info.lastToolAt = t; }
          if (o.type === "assistant" && (tool === "Agent" || tool === "Task")) info.agentCalls.push(c.id); // a child's meta.toolUseId
        }
        else if (c?.type === "tool_result" && typeof c.tool_use_id === "string") { if (open.get(c.tool_use_id)?.tool === "StructuredOutput") structDone = true; open.delete(c.tool_use_id); if (c.is_error === true) info.toolErrors++; }
      }
      endedTurn = o.type === "assistant" && !hasUse && m.content.some((c: any) => c?.type === "text");
    }
  }
  for (const u of usageById.values()) {
    info.tokens.in += num(u.input_tokens); info.tokens.out += num(u.output_tokens);
    info.tokens.cacheRead += num(u.cache_read_input_tokens); info.tokens.cacheWrite += num(u.cache_creation_input_tokens);
  }
  if (lastUsage) info.ctxTokens = num(lastUsage.input_tokens) + num(lastUsage.cache_read_input_tokens) + num(lastUsage.cache_creation_input_tokens);
  info.endedTurn = (endedTurn || structDone) && open.size === 0;
  let last: { tool: string; at: number } | null = null;
  for (const v of open.values()) if (!last || v.at >= last.at) last = v;
  if (last) info.inflight = { tool: last.tool, verb: null, since: last.at };
  return info;
}

// ---- file discovery ----
export interface Paths { root: string; consoleDir: string; home: string; projectsDir: string }
export function pathsFor(root: string, env: NodeJS.ProcessEnv = process.env, home = homedir()): Paths {
  return { root, consoleDir: env.FW_CONSOLE_DIR ?? join(root, ".fw-console"), home, projectsDir: env.FW_PROJECTS_DIR ?? join(home, ".claude", "projects") };
}

/** agent id -> newest transcript file (jsonl) among the project's session dirs (and worktree-named project dirs). */
export function findTranscripts(p: Paths): Map<string, string> {
  const found = new Map<string, { file: string; mtime: number }>();
  const prefix = p.root.replace(/[^A-Za-z0-9]/g, "-");
  let projects: string[] = [];
  try { projects = readdirSync(p.projectsDir).filter((d) => d === prefix || d.startsWith(prefix + "-")); } catch { return new Map(); }
  const addDir = (dir: string) => {
    let names: string[];
    try { names = readdirSync(dir); } catch { return; }
    for (const f of names) {
      const m = /^agent-(.+)\.jsonl$/.exec(f);
      if (!m) continue;
      const file = join(dir, f);
      let mtime = 0;
      try { mtime = statSync(file).mtimeMs; } catch { continue; }
      const prev = found.get(m[1]!);
      if (!prev || mtime > prev.mtime) found.set(m[1]!, { file, mtime });
    }
  };
  for (const pr of projects) {
    const pdir = join(p.projectsDir, pr);
    let sessions: string[] = [];
    try { sessions = readdirSync(pdir); } catch { continue; }
    for (const s of sessions) {
      const sub = join(pdir, s, "subagents");
      if (!existsSync(sub)) continue;
      addDir(sub);
      const wf = join(sub, "workflows");
      let wfs: string[] = [];
      try { wfs = readdirSync(wf); } catch { /* none */ }
      for (const w of wfs) addDir(join(wf, w));
    }
  }
  return new Map([...found].map(([k, v]) => [k, v.file]));
}

function readMeta(jsonlFile: string): Record<string, unknown> | null {
  try { return JSON.parse(readFileSync(jsonlFile.replace(/\.jsonl$/, ".meta.json"), "utf8")); } catch { return null; }
}

/** Kind from the transcript meta and path: `taskKind` *teammate* -> teammate; under `subagents/workflows/` or with a
 *  `workflowPhase` -> workflow; else subagent. */
export function kindOf(tr: TranscriptInfo | null, file: string | undefined): Kind {
  if (tr?.teammate) return "teammate";
  if (tr?.workflowPhase || (file && basename(dirname(dirname(file))) === "workflows")) return "workflow";
  return "subagent";
}

/** A workflow agent's run file `<session>/workflows/<wf>.json` (the transcript is
 *  `<session>/subagents/workflows/<wf>/agent-<id>.jsonl`): true when it exists with a status other than running. */
export function workflowFinished(file: string, cache = new Map<string, boolean>()): boolean {
  const wf = basename(dirname(file));
  const runFile = join(dirname(dirname(dirname(dirname(file)))), "workflows", `${wf}.json`);
  const hit = cache.get(runFile);
  if (hit !== undefined) return hit;
  let done = false;
  try {
    const st = str(JSON.parse(readFileSync(runFile, "utf8"))?.status);
    done = st !== null && st !== "running" && st !== "pending";
  } catch { /* no run file yet: still running */ }
  cache.set(runFile, done);
  return done;
}

/** `owners`, when given, is filled with Bash task id -> agent id for every agent kept in the snapshot. */
export function collectAgents(p: Paths, now: number, owners?: Map<string, string>): AgentSnap[] {
  const spoolDir = join(p.consoleDir, "spool");
  const spools = new Map<string, SpoolSummary>();
  let files: string[] = [];
  try { files = readdirSync(spoolDir); } catch { /* no spool yet */ }
  for (const f of files) {
    if (!f.endsWith(".jsonl") || f === "main.jsonl") continue;
    try { spools.set(f.slice(0, -6), summarizeSpool(parseSpool(readFileSync(join(spoolDir, f), "utf8")))); } catch { /* unreadable */ }
  }
  const transcripts = findTranscripts(p);
  const ids = new Set([...spools.keys(), ...transcripts.keys()]);
  const kept: { id: string; sp: SpoolSummary | null; tf: string | undefined; tr: TranscriptInfo | null }[] = [];
  for (const id of ids) {
    const sp = spools.get(id) ?? null;
    const tf = transcripts.get(id);
    // cheap pre-filter before reading a big transcript: skip agents that clearly ended long ago
    let tmtime = 0;
    if (tf) { try { tmtime = statSync(tf).mtimeMs; } catch { /* gone */ } }
    const meta = tf ? readMeta(tf) : null;
    const lastGuess = Math.max(sp?.lastAt ?? 0, tmtime);
    const endedGuess = sp?.stoppedAt ?? (meta?.finished === true ? tmtime : null);
    if (endedGuess !== null && now - endedGuess > SCOPE.keepDoneMs) continue;
    if (endedGuess === null && now - lastGuess > SCOPE.ghostMs) continue;
    let tr: TranscriptInfo | null = null;
    if (tf) { try { tr = summarizeTranscript(readFileSync(tf, "utf8"), meta); } catch { /* unreadable */ } }
    kept.push({ id, sp, tf, tr });
  }
  // parent link: a child's meta.toolUseId is the id of the Agent call in its parent's transcript (none: the lead)
  const owner = new Map<string, string>();
  for (const k of kept) for (const c of k.tr?.agentCalls ?? []) owner.set(c, k.id);
  if (owners) for (const k of kept) for (const t of k.tr?.bgTasks ?? []) owners.set(t, k.id);
  const wfCache = new Map<string, boolean>();
  const out: AgentSnap[] = [];
  for (const { id, sp, tf, tr } of kept) {
    const lastAt = Math.max(sp?.lastAt ?? 0, tr?.lastAt ?? 0);
    if (lastAt === 0) continue;
    if (!sp && tr?.endedTurn && now - lastAt > SCOPE.keepDoneMs) continue;
    let stoppedAt = sp?.stoppedAt ?? null;
    // transcript-only agents (no spool) that ended their turn on text or StructuredOutput have exited
    if (stoppedAt === null && (tr?.finished || (!sp && tr?.endedTurn))) stoppedAt = tr.lastAt ?? lastAt;
    const kind = kindOf(tr, tf);
    const toolUseId = tr?.toolUseId ?? null;
    out.push({
      id, name: tr?.name ?? null, task: tr?.task ?? null, type: tr?.type ?? sp?.agentType ?? null, model: tr?.model ?? null,
      kind, parent: (toolUseId && owner.get(toolUseId)) || null,
      startedAt: Math.min(...[sp?.startedAt, tr?.firstAt].filter((x): x is number => typeof x === "number")),
      lastAt, stoppedAt, tools: sp?.tools ?? tr?.toolUses ?? 0, errors: sp?.errors ?? tr?.toolErrors ?? 0, errTail: sp?.errTail ?? 0,
      inflight: stoppedAt === null ? tr?.inflight ?? null : null,
      lastTool: sp ? sp.lastTool : tr?.lastTool ?? null, lastToolAt: sp ? sp.lastToolAt : tr?.lastToolAt ?? null,
      idleAt: sp?.idleAt ?? null,
      workflowDone: kind === "workflow" && !!tf && workflowFinished(tf, wfCache), transcriptOnly: !sp,
      ctxTokens: tr?.ctxTokens ?? null, tokens: tr?.tokens ?? { in: 0, out: 0, cacheRead: 0, cacheWrite: 0 },
    });
  }
  out.sort((a, b) => a.id.localeCompare(b.id));
  return out;
}

export function collectLead(p: Paths): LeadSnap {
  try { return summarizeLead(parseSpool(readFileSync(join(p.consoleDir, "spool", "main.jsonl"), "utf8"))); }
  catch { return { lastToolAt: null, noteAt: null }; }
}

// ---- system ----
/** A command's stdout; `null` when it failed or timed out; `"missing"` when the program is not installed.
 * `anyExit`: a nonzero exit status still gives its stdout (lsof exits 1 when one of its pids has ended). */
export type RunOut = string | null | { missing: true };
export type Runner = (cmd: string, args: string[], timeout: number, cwd?: string, anyExit?: boolean) => Promise<RunOut>;
const run: Runner = (cmd, args, timeout, cwd, anyExit = false) =>
  new Promise((resolve) => {
    try {
      execFile(cmd, args, { timeout, cwd, maxBuffer: 4_000_000, env: { ...process.env, GH_PROMPT_DISABLED: "1" } },
        (err, stdout) => {
          if (!err) return resolve(String(stdout));
          const code = (err as NodeJS.ErrnoException).code as unknown;
          if (code === "ENOENT") return resolve({ missing: true });
          resolve(anyExit && typeof code === "number" && !(err as { killed?: boolean }).killed ? String(stdout) : null);
        });
    } catch { resolve(null); }
  });
const text = (r: RunOut): string | null => (typeof r === "string" ? r : null);

/** Wraps a Runner so every `gh` call is booked with the request budget (`ghCharged`, fwcore decides). Other programs pass
 *  through. A wait or stop from the budget, a gh failure, or an unavailable budget (no fwcore) is a failed call (`null`):
 *  the caller carries the previous value forward. The collector never blocks on the budget. `getEnv` is lazy and cached. */
export function chargedRunner(base: Runner, getEnv: () => Env): Runner {
  return async (cmd, args, timeout, cwd, anyExit) => {
    if (cmd !== "gh") return base(cmd, args, timeout, cwd, anyExit);
    try {
      const res = await ghCharged(getEnv(), args, { cost: args.includes("--workflow") ? 2 : 3 });
      return res.ran && res.code === 0 ? res.stdout : null;
    } catch { return null; }
  };
}
let sysEnv: { cwd: string; env: Env } | null = null;
const systemEnv = (cwd: string): Env => (sysEnv?.cwd === cwd ? sysEnv.env : (sysEnv = { cwd, env: realEnv(cwd) }).env);

export function parseMemLevel(out: string | null): "normal" | "warn" | "critical" {
  // kern.memorystatus_vm_pressure_level: 1 normal, 2 warn, 4 critical (xnu sys/kern_memorystatus.h)
  const n = Number((out ?? "").trim());
  return n >= 4 ? "critical" : n === 2 ? "warn" : "normal";
}
export function parseWorktreeCount(out: string | null): number {
  return (out ?? "").split("\n").filter((l) => l.startsWith("worktree ")).length;
}
export function parseDocker(out: string | null): SystemSnap["docker"] {
  const res: SystemSnap["docker"] = [];
  for (const line of (out ?? "").split("\n")) {
    const [id, name, created] = line.split("\t");
    if (!id || !name) continue;
    const m = /^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d) ([+-]\d\d)(\d\d)/.exec(created ?? "");
    const t = m ? Date.parse(`${m[1]}T${m[2]}${m[3]}:${m[4]}`) : NaN;
    res.push({ id, name, startedAt: Number.isFinite(t) ? t : 0 });
  }
  return res;
}
export function parseCi(out: string | null): SystemSnap["ci"] {
  if (!out) return [];
  try {
    const arr = JSON.parse(out) as any[];
    return arr.map((r) => ({
      ...(typeof r.databaseId === "number" ? { id: r.databaseId } : {}), // run id: the `ci` fact of obs.next
      workflow: String(r.workflowName ?? "?"), branch: String(r.headBranch ?? "?"), status: String(r.status ?? "?"),
      conclusion: str(r.conclusion), startedAt: Date.parse(String(r.createdAt)) || 0,
      // a completed run's last update is its end (gh has no endedAt field)
      endedAt: r.status === "completed" ? Date.parse(String(r.updatedAt)) || null : null,
    }));
  } catch { return []; }
}

/** One `ps -A -o pid=,ppid=,etime=,comm=` row: the age comes from etime, so no locale-dependent date is parsed. */
export interface PsRow { pid: number; ppid: number; ageMs: number; comm: string }
/** `[[dd-]hh:]mm:ss` to milliseconds; null when malformed. */
export function parseEtime(s: string): number | null {
  const m = /^(?:(?:(\d+)-)?(\d+):)?(\d+):(\d+)$/.exec(s.trim());
  if (!m) return null;
  const [d, h, mi, se] = [m[1], m[2], m[3], m[4]].map((x) => Number(x ?? 0)) as [number, number, number, number];
  return (((d * 24 + h) * 60 + mi) * 60 + se) * 1000;
}
export function parsePs(out: string | null): PsRow[] {
  const rows: PsRow[] = [];
  for (const line of (out ?? "").split("\n")) {
    const m = /^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.+?)\s*$/.exec(line);
    const age = m ? parseEtime(m[3]!) : null;
    if (m && age !== null) rows.push({ pid: Number(m[1]), ppid: Number(m[2]), ageMs: age, comm: m[4]! });
  }
  return rows;
}
const SHELLS = new Set(["zsh", "bash", "sh", "dash", "fish"]);
/** An executable's basename: a path keeps its spaces ("/Applications/A B.app/.../A B"); a retitled process
 *  ("npm exec x") keeps only its first word, so no argument is ever kept. */
export const exe = (comm: string) => basename(comm.startsWith("/") ? comm : (comm.split(" ")[0] ?? comm));
/** The process trees of this session's Bash tool: find the nearest `claude` ancestor of `self`, take its shell
 *  children as roots, and name each tree by its first non-shell program (breadth first). Empty outside a session. */
export function sessionProcs(rows: PsRow[], self: number, now: number): NonNullable<SystemSnap["procs"]> {
  const by = new Map(rows.map((r) => [r.pid, r]));
  const kids = new Map<number, PsRow[]>();
  for (const r of rows) kids.set(r.ppid, [...(kids.get(r.ppid) ?? []), r]);
  let cur = by.get(self);
  for (let i = 0; cur && exe(cur.comm) !== "claude" && i < 64; i++) cur = by.get(cur.ppid);
  if (!cur || exe(cur.comm) !== "claude") return [];
  const out: NonNullable<SystemSnap["procs"]> = [];
  for (const root of kids.get(cur.pid) ?? []) {
    if (!SHELLS.has(exe(root.comm))) continue; // MCP servers and helpers the app itself started are not Bash work
    const pids: number[] = [];
    let name: string | null = null;
    for (let q = [...(kids.get(root.pid) ?? [])]; q.length > 0;) {
      const r = q.shift()!;
      pids.push(r.pid);
      if (name === null && !SHELLS.has(exe(r.comm))) name = exe(r.comm);
      q.push(...(kids.get(r.pid) ?? []));
    }
    out.push({ pid: root.pid, name: name ?? exe(root.comm), startedAt: Math.floor(now - root.ageMs), pids });
  }
  return out;
}

export function collectSimLock(root: string): SystemSnap["simLock"] {
  const dir = join(root, ".local", "locks", "sim");
  try {
    const since = Math.floor(statSync(dir).mtimeMs);
    let holder: string | null = null;
    try { holder = readFileSync(join(dir, "owner"), "utf8").trim() || null; } catch { /* no owner file */ }
    return { holder: holder ?? "unknown", since };
  } catch { return { holder: null, since: null }; }
}

export function collectConsolePids(p: Paths): number[] {
  try { const j = JSON.parse(readFileSync(join(p.consoleDir, "api.json"), "utf8")); return typeof j.pid === "number" ? [j.pid] : []; } catch { return []; }
}

/** A tree keeps the name the previous check gave it (same root pid, start within 2 s), so a polling loop whose
 *  current program alternates (`sleep`, `gh`) keeps one alert subject `name#pid` across checks; it also keeps the
 *  previous owner when this check found none (lsof failed, or the owner's transcript dropped out of scope). */
export function keepNames(now: Proc[], before: Proc[]): Proc[] {
  const by = new Map(before.map((q) => [q.pid, q]));
  return now.map((q) => {
    const b = by.get(q.pid);
    if (!b || Math.abs(b.startedAt - q.startedAt) > 2000) return q;
    const agent = q.agent ?? b.agent ?? null;
    return agent === null ? { ...q, name: b.name } : { ...q, name: b.name, agent };
  });
}

/** `lsof -a -d 1 -Fpn -p <pids>` output -> pid -> Bash task id: Claude Code points a Bash call's stdout at
 *  `<session>/tasks/<id>.output`, and the agent's transcript records that id (`backgroundTaskId`). */
export function parseTaskIds(out: string | null): Map<number, string> {
  const ids = new Map<number, string>();
  let pid: number | null = null;
  for (const line of (out ?? "").split("\n")) {
    if (line.startsWith("p")) pid = Number(line.slice(1)) || null;
    else if (line.startsWith("n") && pid !== null) {
      const m = /\/tasks\/([A-Za-z0-9_-]+)\.output$/.exec(line.slice(1));
      if (m) ids.set(pid, m[1]!);
    }
  }
  return ids;
}

/** Each tree's owner: the agent whose transcript holds the task id of the tree's root shell (none: the lead's task,
 *  or not known). Identity lookup only; whether the owner is live and what that means is fwcore's rule. */
export function ownProcs(procs: Proc[], taskOf: Map<number, string>, owners: Map<string, string>): Proc[] {
  return procs.map((q) => {
    const t = taskOf.get(q.pid);
    const agent = t === undefined ? undefined : owners.get(t);
    return agent === undefined ? q : { ...q, agent };
  });
}

/** One declared long-runner in `.fw-console/keep.json` (written by `fw watch --keep <pid>`): its pid, its start time
 *  (ms, from ps at declaration) and the lead's note. */
export interface KeepEntry { pid: number; startedAt: number; note: string | null }
export function readKeep(p: Paths): KeepEntry[] {
  try {
    const j = JSON.parse(readFileSync(join(p.consoleDir, "keep.json"), "utf8"));
    return (Array.isArray(j) ? j : []).filter((e): e is KeepEntry =>
      typeof e?.pid === "number" && typeof e?.startedAt === "number").map((e) => ({ pid: e.pid, startedAt: e.startedAt, note: str(e.note) }));
  } catch { return []; }
}
export function writeKeep(p: Paths, entries: KeepEntry[]): void {
  mkdirSync(p.consoleDir, { recursive: true });
  writeFileSync(join(p.consoleDir, "keep.json"), JSON.stringify(entries, null, 1) + "\n");
}
/** The declared entries that still name the same process (a ps row with that pid whose start is within 2 s of the
 *  declared start), so a reused pid is never exempt. */
export function liveKeep(entries: KeepEntry[], rows: PsRow[], now: number): KeepEntry[] {
  const by = new Map(rows.map((r) => [r.pid, r]));
  return entries.filter((e) => { const r = by.get(e.pid); return !!r && Math.abs(now - r.ageMs - e.startedAt) <= 2000; });
}

/** The previous check's system part, if it is recent enough to carry forward (SCOPE.carryMs). */
export interface Prev { at: number; system: SystemSnap; critical?: string[] }

/** `owners`: Bash task id -> agent id (from `collectAgents`); trees whose task id is not in it have no owner. */
export async function collectSystem(p: Paths, prev: Prev | null = null, now = Date.now(), exec: Runner = chargedRunner(run, () => systemEnv(p.root)),
  owners: Map<string, string> = new Map()): Promise<SystemSnap> {
  const [mem, wt, dock, ci, ps] = await Promise.all([
    exec("sysctl", ["-n", "kern.memorystatus_vm_pressure_level"], 2000),
    exec("git", ["worktree", "list", "--porcelain"], 3000, p.root),
    exec("docker", ["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.CreatedAt}}"], 3000),
    exec("gh", ["run", "list", "--limit", "20", "--json", "databaseId,workflowName,headBranch,status,conclusion,createdAt,updatedAt"], 10000, p.root),
    exec("ps", ["-A", "-o", "pid=,ppid=,etime=,comm="], 3000),
  ]);
  // a failed (not missing) gh or docker call keeps the previous value, marked stale, instead of reporting "none":
  // otherwise its alerts would vanish and come back as new
  const old = prev && now - prev.at <= SCOPE.carryMs ? prev.system : null;
  const stale: string[] = [];
  let docker = parseDocker(text(dock));
  if (dock === null) { stale.push("docker"); docker = old?.docker ?? []; }
  let ciRuns = parseCi(text(ci));
  if (ci === null) { stale.push("ci"); ciRuns = old?.ci ?? []; }
  const rows = parsePs(text(ps));
  let procs = sessionProcs(rows, process.pid, now);
  let keep = liveKeep(readKeep(p), rows, now).map((e) => e.pid);
  if (ps === null) { stale.push("procs"); procs = old?.procs ?? []; keep = old?.keep ?? []; }
  else {
    // lsof exits 1 when a listed pid has ended meanwhile (anyExit keeps the others); on a timeout the owners come
    // from the previous check (keepNames)
    const lsof = procs.length ? await exec("lsof", ["-a", "-d", "1", "-Fpn", "-p", procs.map((q) => q.pid).join(",")], 3000, undefined, true) : "";
    procs = keepNames(ownProcs(procs, parseTaskIds(text(lsof)), owners), prev?.system.procs ?? []);
  }
  const consolePids = collectConsolePids(p);
  let disk = 0;
  try { const s = statfsSync(p.root); disk = Math.floor((Number(s.bavail) * Number(s.bsize)) / 1e9); } catch { /* unknown -> 0 raises sys.diskLow */ }
  return {
    load1: Math.round(loadavg()[0]! * 100) / 100, loadFloor: Math.floor(loadavg()[0]!), memPressure: parseMemLevel(text(mem)),
    diskFreeGB: disk, simLock: collectSimLock(p.root), docker, worktrees: parseWorktreeCount(text(wt)),
    consolePids, ci: ciRuns, procs, services: [process.pid, ...consolePids], keep, stale,
  };
}

/** The critical path from console-api (GET /api/plan): `string[]`; `null` when the call failed; `[]` when
 *  console-api is not running (no api.json and no FW_API), like a missing program. */
export type PlanFetch = (url: string) => Promise<unknown>;
const getJson: PlanFetch = async (url) => {
  const r = await fetch(url, { signal: AbortSignal.timeout(3000) });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
};
export async function collectCritical(p: Paths, env: NodeJS.ProcessEnv = process.env, get: PlanFetch = getJson): Promise<string[] | null> {
  let base = env.FW_API ?? null;
  if (!base) {
    try { base = `http://127.0.0.1:${JSON.parse(readFileSync(join(p.consoleDir, "api.json"), "utf8")).port}`; } catch { return []; }
  }
  try {
    const cp = ((await get(`${base}/api/plan`)) as { criticalPath?: unknown })?.criticalPath;
    return Array.isArray(cp) ? cp.filter((x): x is string => typeof x === "string") : null;
  } catch { return null; }
}

/** A failed plan call keeps the previous check's critical path (if that check is <= SCOPE.carryMs old), marked stale. */
export function carryCritical(crit: string[] | null, prev: Prev | null, now: number): { critical: string[]; stale: boolean } {
  if (crit !== null) return { critical: crit, stale: false };
  return { critical: (prev && now - prev.at <= SCOPE.carryMs ? prev.critical : undefined) ?? [], stale: true };
}

export async function collectSnapshot(p: Paths, now = Date.now(), params: Record<string, number> = DEFAULT_PARAMS, prev: Prev | null = null,
  get: PlanFetch = getJson): Promise<Snapshot> {
  const owners = new Map<string, string>();
  const agents = collectAgents(p, now, owners);
  const [system, crit] = await Promise.all([collectSystem(p, prev, now, undefined, owners), collectCritical(p, process.env, get)]);
  const { critical, stale } = carryCritical(crit, prev, now);
  if (stale) system.stale.push("plan");
  return { now, params, agents, lead: collectLead(p), system, prevAt: prev?.at ?? null, critical };
}
