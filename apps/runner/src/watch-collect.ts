// Collectors for `fw watch`: read-only, stdlib only. They turn spools, transcripts and the machine into the
// obs.health snapshot (lean/Fw/Wire/Obs.lean). No health decision is made here: states and alerts come from fwcore.
// Scoping rules that ARE here (which agents get into the snapshot): see SCOPE below.
// Privacy: only names, counts, ids and times are read out of the files; payload text is never kept.
import { execFile } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync, statfsSync } from "node:fs";
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
export interface SystemSnap {
  load1: number; memPressure: "normal" | "warn" | "critical"; diskFreeGB: number;
  simLock: { holder: string | null; since: number | null };
  docker: { id: string; name: string; startedAt: number }[]; worktrees: number; consolePids: number[];
  ci: { workflow: string; branch: string; status: string; conclusion: string | null; startedAt: number }[];
  /** collectors that failed this time and whose value was carried forward from the previous check ("ci", "docker") */
  stale: string[];
}
export interface Snapshot { now: number; params: Record<string, number>; agents: AgentSnap[]; lead: LeadSnap; system: SystemSnap }

// SCOPE (collection only, not health decisions): an agent with no SubagentStop and no activity for 24 h is
// treated as ended (its hooks never fired Stop); ended agents are dropped from the snapshot 1 h after they ended.
// A failed gh/docker collector carries the previous check's value forward only if that check is <= 1 h old.
export const SCOPE = { ghostMs: 24 * 3600_000, keepDoneMs: 3600_000, carryMs: 3600_000 };

export const DEFAULT_PARAMS = {
  idleMin: 10, stallMin: 20, toolHangMin: 30, errStreak: 3, ctxResumeMax: 250000, ctxWarn: 200000,
  diskMinGB: 20, agentCap: 10, simLockMaxMin: 30, worktreesMax: 20, wfQuietMin: 30,
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
    toolUseId: str(meta?.toolUseId), agentCalls: [],
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

export function collectAgents(p: Paths, now: number): AgentSnap[] {
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
/** A command's stdout; `null` when it failed or timed out; `"missing"` when the program is not installed. */
export type RunOut = string | null | { missing: true };
export type Runner = (cmd: string, args: string[], timeout: number, cwd?: string) => Promise<RunOut>;
const run: Runner = (cmd, args, timeout, cwd) =>
  new Promise((resolve) => {
    try {
      execFile(cmd, args, { timeout, cwd, maxBuffer: 4_000_000, env: { ...process.env, GH_PROMPT_DISABLED: "1" } },
        (err, stdout) => resolve(err ? ((err as NodeJS.ErrnoException).code === "ENOENT" ? { missing: true } : null) : String(stdout)));
    } catch { resolve(null); }
  });
const text = (r: RunOut): string | null => (typeof r === "string" ? r : null);

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
      workflow: String(r.workflowName ?? "?"), branch: String(r.headBranch ?? "?"), status: String(r.status ?? "?"),
      conclusion: str(r.conclusion), startedAt: Date.parse(String(r.createdAt)) || 0,
    }));
  } catch { return []; }
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

/** The previous check's system part, if it is recent enough to carry forward (SCOPE.carryMs). */
export interface Prev { at: number; system: SystemSnap }

export async function collectSystem(p: Paths, prev: Prev | null = null, now = Date.now(), exec: Runner = run): Promise<SystemSnap> {
  const [mem, wt, dock, ci] = await Promise.all([
    exec("sysctl", ["-n", "kern.memorystatus_vm_pressure_level"], 2000),
    exec("git", ["worktree", "list", "--porcelain"], 3000, p.root),
    exec("docker", ["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.CreatedAt}}"], 3000),
    exec("gh", ["run", "list", "--limit", "20", "--json", "workflowName,headBranch,status,conclusion,createdAt"], 10000, p.root),
  ]);
  // a failed (not missing) gh or docker call keeps the previous value, marked stale, instead of reporting "none":
  // otherwise its alerts would vanish and come back as new
  const old = prev && now - prev.at <= SCOPE.carryMs ? prev.system : null;
  const stale: string[] = [];
  let docker = parseDocker(text(dock));
  if (dock === null) { stale.push("docker"); docker = old?.docker ?? []; }
  let ciRuns = parseCi(text(ci));
  if (ci === null) { stale.push("ci"); ciRuns = old?.ci ?? []; }
  let disk = 0;
  try { const s = statfsSync(p.root); disk = Math.floor((Number(s.bavail) * Number(s.bsize)) / 1e9); } catch { /* unknown -> 0 raises sys.diskLow */ }
  return {
    load1: Math.round(loadavg()[0]! * 100) / 100, memPressure: parseMemLevel(text(mem)), diskFreeGB: disk,
    simLock: collectSimLock(p.root), docker, worktrees: parseWorktreeCount(text(wt)),
    consolePids: collectConsolePids(p), ci: ciRuns, stale,
  };
}

export async function collectSnapshot(p: Paths, now = Date.now(), params: Record<string, number> = DEFAULT_PARAMS, prev: Prev | null = null): Promise<Snapshot> {
  const [agents, system] = await Promise.all([Promise.resolve(collectAgents(p, now)), collectSystem(p, prev, now)]);
  return { now, params, agents, lead: collectLead(p), system };
}
