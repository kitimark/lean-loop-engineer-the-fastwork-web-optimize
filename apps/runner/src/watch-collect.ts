// Collectors for `fw watch`: read-only, stdlib only. They turn spools, transcripts and the machine into the
// obs.health snapshot (lean/Fw/Wire/Obs.lean). No health decision is made here: states and alerts come from fwcore.
// Scoping rules that ARE here (which agents get into the snapshot): see SCOPE below.
// Privacy: only names, counts, ids and times are read out of the files; payload text is never kept.
import { execFile } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync, statfsSync } from "node:fs";
import { homedir, loadavg } from "node:os";
import { join } from "node:path";

export interface SpoolEvent {
  agent_id: string | null; agent_type: string | null; hook_event_name: string;
  tool_name: string | null; tool_use_id: string | null; duration_ms: number | null;
  is_error: boolean | null; verb: string | null; ts: number;
}
export interface Tokens { in: number; out: number; cacheRead: number; cacheWrite: number }
export interface TranscriptInfo {
  name: string | null; task: string | null; type: string | null; model: string | null; depth: number | null;
  finished: boolean; endedTurn: boolean; toolUses: number; toolErrors: number; firstAt: number | null; lastAt: number | null;
  ctxTokens: number | null; tokens: Tokens; inflight: { tool: string; verb: null; since: number } | null;
}
export interface AgentSnap {
  id: string; name: string | null; task: string | null; type: string | null; model: string | null; depth: number;
  startedAt: number; lastAt: number; stoppedAt: number | null; tools: number; errors: number; errTail: number;
  inflight: { tool: string; verb: string | null; since: number } | null; waitingPermission: boolean;
  ctxTokens: number | null; tokens: Tokens;
}
export interface SystemSnap {
  load1: number; memPressure: "normal" | "warn" | "critical"; diskFreeGB: number;
  simLock: { holder: string | null; since: number | null };
  docker: { id: string; name: string; startedAt: number }[]; worktrees: number; consolePids: number[];
  ci: { workflow: string; branch: string; status: string; conclusion: string | null; startedAt: number }[];
}
export interface Snapshot { now: number; params: Record<string, number>; agents: AgentSnap[]; system: SystemSnap }

// SCOPE (collection only, not health decisions): an agent with no SubagentStop and no activity for 24 h is
// treated as ended (its hooks never fired Stop); ended agents are dropped from the snapshot 1 h after they ended.
export const SCOPE = { ghostMs: 24 * 3600_000, keepDoneMs: 3600_000 };

export const DEFAULT_PARAMS = {
  idleMin: 10, stallMin: 20, toolHangMin: 30, errStreak: 3, ctxResumeMax: 250000, ctxWarn: 200000,
  diskMinGB: 20, agentCap: 10, simLockMaxMin: 30, worktreesMax: 20,
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
  tools: number; errors: number; errTail: number; waiting: boolean;
}
export function summarizeSpool(events: SpoolEvent[]): SpoolSummary {
  const s: SpoolSummary = { agentType: null, startedAt: null, lastAt: null, stoppedAt: null, tools: 0, errors: 0, errTail: 0, waiting: false };
  let lastTool = -1, lastNote = -1, lastStart = -1;
  for (const e of events) {
    s.agentType ||= str(e.agent_type);
    if (s.startedAt === null || e.ts < s.startedAt) s.startedAt = e.ts;
    if (s.lastAt === null || e.ts > s.lastAt) s.lastAt = e.ts;
    const h = e.hook_event_name;
    if (h === "SubagentStart") lastStart = Math.max(lastStart, e.ts);
    if (h === "SubagentStop") s.stoppedAt = Math.max(s.stoppedAt ?? 0, e.ts);
    if (h === "PostToolUse" || h === "PostToolUseFailure") {
      s.tools++;
      const bad = h === "PostToolUseFailure" || e.is_error === true;
      if (bad) s.errors++;
      s.errTail = bad ? s.errTail + 1 : 0;
      lastTool = Math.max(lastTool, e.ts);
    }
    if (h === "Notification") lastNote = Math.max(lastNote, e.ts);
  }
  // a Start after the last Stop means it was resumed
  if (s.stoppedAt !== null && lastStart > s.stoppedAt) s.stoppedAt = null;
  s.waiting = lastNote >= 0 && lastNote >= lastTool && s.stoppedAt === null;
  return s;
}

/** Summarize one subagent transcript (+ meta). Only usage numbers, model, tool names/ids and times are kept. */
export function summarizeTranscript(jsonl: string, meta: Record<string, unknown> | null): TranscriptInfo {
  const info: TranscriptInfo = {
    name: str(meta?.name), task: str(meta?.description), type: str(meta?.agentType), model: null,
    depth: typeof meta?.spawnDepth === "number" ? meta.spawnDepth : null, finished: meta?.finished === true, endedTurn: false, toolUses: 0, toolErrors: 0,
    firstAt: null, lastAt: null, ctxTokens: null, tokens: { in: 0, out: 0, cacheRead: 0, cacheWrite: 0 }, inflight: null,
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
        if (c?.type === "tool_use" && typeof c.id === "string") { hasUse = true; info.toolUses++; open.set(c.id, { tool: String(c.name ?? "?"), at: Number.isFinite(at) ? at : 0 }); }
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
  const out: AgentSnap[] = [];
  for (const id of ids) {
    const sp = spools.get(id) ?? null;
    const tf = transcripts.get(id);
    // cheap pre-filter before reading a big transcript: skip agents that clearly ended long ago
    let tmtime = 0;
    if (tf) { try { tmtime = statSync(tf).mtimeMs; } catch { /* gone */ } }
    const meta = tf ? readMeta(tf) : null;
    const lastGuess = Math.max(sp?.lastAt ?? 0, tmtime);
    const endedGuess = sp?.stoppedAt ?? (meta?.finished === true ? tmtime : null);
    // (transcript-only agents that ended their turn are dropped after the full parse below)
    if (endedGuess !== null && now - endedGuess > SCOPE.keepDoneMs) continue;
    if (endedGuess === null && now - lastGuess > SCOPE.ghostMs) continue;
    let tr: TranscriptInfo | null = null;
    if (tf) { try { tr = summarizeTranscript(readFileSync(tf, "utf8"), meta); } catch { /* unreadable */ } }
    const lastAt = Math.max(sp?.lastAt ?? 0, tr?.lastAt ?? 0);
    if (lastAt === 0) continue;
    if (!sp && tr?.endedTurn && now - lastAt > SCOPE.keepDoneMs) continue;
    let stoppedAt = sp?.stoppedAt ?? null;
    // transcript-only agents (no spool, e.g. workflow agents) that ended their turn on text are done
    if (stoppedAt === null && (tr?.finished || (!sp && tr?.endedTurn))) stoppedAt = tr.lastAt ?? lastAt;
    out.push({
      id, name: tr?.name ?? null, task: tr?.task ?? null, type: tr?.type ?? sp?.agentType ?? null, model: tr?.model ?? null,
      depth: tr?.depth ?? 1, startedAt: Math.min(...[sp?.startedAt, tr?.firstAt].filter((x): x is number => typeof x === "number")),
      lastAt, stoppedAt, tools: sp?.tools ?? tr?.toolUses ?? 0, errors: sp?.errors ?? tr?.toolErrors ?? 0, errTail: sp?.errTail ?? 0,
      inflight: stoppedAt === null ? tr?.inflight ?? null : null,
      waitingPermission: sp?.waiting ?? false, ctxTokens: tr?.ctxTokens ?? null,
      tokens: tr?.tokens ?? { in: 0, out: 0, cacheRead: 0, cacheWrite: 0 },
    });
  }
  out.sort((a, b) => a.id.localeCompare(b.id));
  return out;
}

// ---- system ----
function run(cmd: string, args: string[], timeout: number, cwd?: string): Promise<string | null> {
  return new Promise((resolve) => {
    try {
      execFile(cmd, args, { timeout, cwd, maxBuffer: 4_000_000, env: { ...process.env, GH_PROMPT_DISABLED: "1" } },
        (err, stdout) => resolve(err ? null : String(stdout)));
    } catch { resolve(null); }
  });
}

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

export async function collectSystem(p: Paths): Promise<SystemSnap> {
  const [mem, wt, dock, ci] = await Promise.all([
    run("sysctl", ["-n", "kern.memorystatus_vm_pressure_level"], 2000),
    run("git", ["worktree", "list", "--porcelain"], 3000, p.root),
    run("docker", ["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.CreatedAt}}"], 3000),
    run("gh", ["run", "list", "--limit", "20", "--json", "workflowName,headBranch,status,conclusion,createdAt"], 10000, p.root),
  ]);
  let disk = 0;
  try { const s = statfsSync(p.root); disk = Math.floor((Number(s.bavail) * Number(s.bsize)) / 1e9); } catch { /* unknown -> 0 raises sys.diskLow */ }
  return {
    load1: Math.round(loadavg()[0]! * 100) / 100, memPressure: parseMemLevel(mem), diskFreeGB: disk,
    simLock: collectSimLock(p.root), docker: parseDocker(dock), worktrees: parseWorktreeCount(wt),
    consolePids: collectConsolePids(p), ci: parseCi(ci),
  };
}

export async function collectSnapshot(p: Paths, now = Date.now(), params: Record<string, number> = DEFAULT_PARAMS): Promise<Snapshot> {
  const [agents, system] = await Promise.all([Promise.resolve(collectAgents(p, now)), collectSystem(p)]);
  return { now, params, agents, system };
}
