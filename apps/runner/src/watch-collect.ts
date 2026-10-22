// Collectors for `fw watch`: read-only, stdlib only. They turn spools, transcripts and the machine into the
// obs.health snapshot (lean/Fw/Wire/Obs.lean). No health decision is made here: states and alerts come from fwcore.
// Scoping rules that ARE here (which agents get into the snapshot): see SCOPE below.
// Privacy: only names, counts, ids and times are read out of the files; payload text is never kept.
import { execFile } from "node:child_process";
import { ghCharged, realEnv, type Env } from "@fw/gh-budget";
import { appendFileSync, closeSync, existsSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, statSync, statfsSync, writeFileSync } from "node:fs";
import { homedir, loadavg, totalmem } from "node:os";
import { basename, dirname, join } from "node:path";
import { GhClock, phasedEnv } from "./run-phases.ts";
import { collectGh, type GhFetch, type GhSnap } from "./watch-gh.ts";
import { collectSvcs, type Svc } from "./watch-svc.ts";
import { foldFile, sweepCache } from "./watch-cache.ts";
import { BG_TEXT, finishInfo, finishSignals, foldText, initFold, parseNotifications, waitingNote } from "./watch-fold.ts";
import { parseWaits } from "./slot-queue.ts";
export { parseNotifications, waitingNote };

export interface SpoolEvent {
  agent_id: string | null; agent_type: string | null; hook_event_name: string;
  tool_name: string | null; tool_use_id: string | null; duration_ms: number | null;
  is_error: boolean | null; verb: string | null; ts: number;
  /** the Claude session whose hook wrote the line (absent in old lines) */
  session_pid?: number | null;
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
  /** the pid of the Claude session whose hooks wrote the agent's spool (null: none recorded); Lean `deadSession` */
  sessionPid?: number | null;
}
/** The lead session's facts (spool/main.jsonl): its last tool event and its last Notification. */
export interface LeadSnap { lastToolAt: number | null; noteAt: number | null }
/** A process tree this Claude session started through its Bash tool: root shell pid, the first non-shell program's
 *  name (executable basename only, never arguments), start time, every descendant pid, and the id of the agent whose
 *  Bash call started it (absent or null: the lead session, or not known) */
export interface Proc { pid: number; name: string; startedAt: number; pids: number[]; agent?: string | null }
/** A feedback event as the `fwcore obs.health` wire reads it (Lean `Fw.Wire.Obs.fbEvOf`): `ref` is the comment id of a post, or the id a reply answers. */
export interface FeedbackEv { kind: "post" | "reply"; flag: string; ref: string; text: string; ts: number }
export interface SystemSnap {
  load1: number; memPressure: "normal" | "warn" | "critical"; diskFreeGB: number;
  simLock: { holder: string | null; since: number | null };
  docker: { id: string; name: string; startedAt: number }[]; worktrees: number; consolePids: number[];
  ci: { id?: number; workflow: string; branch: string; status: string; conclusion: string | null; startedAt: number; endedAt?: number | null; headSha?: string }[];
  /** floor of the 1-min load average (fwcore compares it with loadMax) */
  loadFloor?: number;
  /** `lake` processes running (the local builders), live heavy-lock holders (scripts/heavy-lock.mjs) and whether the
   *  previous check raised sys.contended (the hysteresis bit, Lean `Fw.Obs.LoadInfo`) */
  load?: { builders: number; heavyJobs: number; prevContended: boolean };
  /** process trees this Claude session started through its Bash tool: root shell pid, the first non-shell program's
   *  name (executable basename only, never arguments), start time, and every descendant pid */
  procs?: Proc[];
  /** pids that are services, not session work: this `fw watch` process and console-api (a tree holding one is exempt) */
  services?: number[];
  /** pids the lead declared as intended long-runners (`fw watch --keep`, .fw-console/keep.json), still running */
  keep?: number[];
  /** the running code (console-api, its fwcore child, the fwcore binary on disk): per input group whether the range
   *  base..main touches it (fwcore raises svc.stale), or why the base is unknown (svc.unknown); see watch-svc.ts */
  svcs?: Svc[];
  /** every pid of the process table read this time (absent when `ps` failed: no agent is judged by it); Lean `deadSession` */
  alivePids?: number[];
  /** the accepted `review.feedback` and `review.feedback.reply` events of the log, oldest first (`collectFeedback`); fwcore folds them into
   *  threads and raises `review.feedback` for a flag with an open comment (Lean `Fw.Obs.FeedbackAlert`) */
  feedback?: FeedbackEv[];
  /** GitHub Actions, Pages and Webhooks states and the open incidents (watch-gh.ts); fwcore raises sys.ghDegraded */
  gh?: GhSnap;
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
// treated as ended (its hooks never fired Stop); ended agents are dropped from the snapshot 1 h after they ended,
// unless their worktree directory still exists or their transcript shows a background id launched within 24 h
// with no end (retention is Fw.Obs.Next.keepB; this pre-filter only skips agents that rule would also drop: no
// worktree and no pending id, hence no open branch/child/CI/respawn/signal is observable for them). meta.finished
// is never used for retention.
// A failed gh/docker collector carries the previous check's value forward only if that check is <= 1 h old.
export const SCOPE = { ghostMs: 24 * 3600_000, keepDoneMs: 3600_000, carryMs: 3600_000 };

/** The agent's worktree directory (`<main>/.claude/worktrees/agent-<id>`) still exists: a cheap observation, no decision. */
export const hasWorktree = (p: Paths, id: string): boolean => existsSync(join(p.root, ".claude", "worktrees", `agent-${id}`));

export const DEFAULT_PARAMS = {
  idleMin: 10, stallMin: 20, toolHangMin: 30, errStreak: 3, ctxResumeMax: 250000, ctxWarn: 200000,
  diskMinGB: 20, agentCap: 10, simLockMaxMin: 30, worktreesMax: 20, wfQuietMin: 30,
  goneAfterMin: 120, ciSlowMin: 20, toolSlowMin: 15, procMaxMin: 20, loadMax: 150,
};
// ciSlowBy (per-workflow ci.slow limits) is not sent: fwcore's default applies (Fw.Obs.Health.Params.ciSlowBy)

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
  /** the session pid of the newest line that has one */
  sessionPid?: number | null;
}
export function summarizeSpool(events: SpoolEvent[]): SpoolSummary {
  let lastStart = -1;
  const s: SpoolSummary = { agentType: null, startedAt: null, lastAt: null, stoppedAt: null, tools: 0, errors: 0, errTail: 0, lastTool: null, lastToolAt: null, idleAt: null, sessionPid: null };
  let pidAt = -1;
  for (const e of events) {
    if (typeof e.session_pid === "number" && e.ts >= pidAt) { pidAt = e.ts; s.sessionPid = e.session_pid; }
    s.agentType ||= str(e.agent_type);
    if (s.startedAt === null || e.ts < s.startedAt) s.startedAt = e.ts;
    if (s.lastAt === null || e.ts > s.lastAt) s.lastAt = e.ts;
    const h = e.hook_event_name;
    if (h === "SubagentStart") lastStart = Math.max(lastStart, e.ts);
    if (h === "SubagentStop") s.stoppedAt = Math.max(s.stoppedAt ?? 0, e.ts);
    if (h === "TeammateIdle") s.idleAt = Math.max(s.idleAt ?? 0, e.ts);
    if (h === "PostToolUse" || h === "PostToolUseFailure") {
      s.tools++;
      const bad = h === "PostToolUseFailure" || e.is_error === true;
      if (bad) s.errors++;
      s.errTail = bad ? s.errTail + 1 : 0;
      if (s.lastToolAt === null || e.ts >= s.lastToolAt) { s.lastToolAt = e.ts; s.lastTool = str(e.tool_name); }
    }
  }
  // resumed iff a SubagentStart is newer than the newest Stop; a tool call is not a resume (Lean `Fw.Ops.Obs.stoppedAtOf`,
  // golden: packages/contracts/golden/ops/ops.obs.jsonl, the `resume` cases)
  if (s.stoppedAt !== null && lastStart > s.stoppedAt) s.stoppedAt = null;
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

/** Summarize one subagent transcript (+ meta). Only usage numbers, model, tool names/ids and times are kept; the fold is
 *  in watch-fold.ts. `metaAt`: the mtime of the meta file (see `finishInfo`). */
export function summarizeTranscript(jsonl: string, meta: Record<string, unknown> | null, metaAt: number | null = null): TranscriptInfo {
  return finishInfo(foldText(initFold(false), jsonl), meta, metaAt);
}

// ---- transcript signals: the facts of Fw.Obs.Signals (the state itself is fwcore's `obs.signals`) ----
/** How an end of a background id was seen (Fw.Obs.Signals.How). */
export type SigEnd = { id: string; time: number; how: "notified" | "killed" } | { id: string; time: number; how: "exited"; code: number };
export type SigProcKind = "stdin" | "sleepLoop" | "other";
/** Wire shape of Fw.Obs.Signals.Facts (times in ms). */
export interface SigFacts {
  agent: string; launched: { id: string; time: number }[]; ends: SigEnd[]; bounds: { time: number; start: boolean }[];
  handbacks: number[]; notices: { time: number; finished: boolean }[]; procs: { id: string; pid: number; kind: SigProcKind }[];
  metaFinished: number[];
}
/** Signals read from one transcript, plus what the collector needs to finish them: the command text of each Bash
 *  background id (kept in memory to classify its live process, never written out), the output file of each id,
 *  whether a tool call is still open, and the time of the last record. */
export interface TranscriptSignals { facts: SigFacts; commands: Map<string, string>; outputs: Map<string, string>; openCall: boolean; lastAt: number | null }

/** One `<task-notification>`: task id, status, summary, output file. */
export interface TaskNote { id: string; status: string; summary: string; outputFile: string | null }
/** The signal facts of one agent's transcript: background ids launched (Bash `backgroundTaskId`, the text form of a
 *  workflow agent's Bash result matched by tool_use_id, async child agents), their end notifications, the turn
 *  boundaries (START: first record and every user record with a top-level `origin`; END: `end_turn` and every
 *  `toolEndsTurn` result) and the handbacks (an accepted `SubagentHandback` / `StructuredOutput` result). */
export function signalsOf(agent: string, jsonl: string): TranscriptSignals {
  return finishSignals(agent, foldText(initFold(true), jsonl));
}

/** The end marker a finished Bash task leaves as the last line of its output file: `[exited with code N]` or
 *  `[killed]` (null: none). */
export function markerOf(lastLine: string): { how: "exited"; code: number } | { how: "killed" } | null {
  const s = lastLine.trim();
  const m = /^\[exited with code (-?\d+)\]$/.exec(s);
  if (m) return { how: "exited", code: Number(m[1]) };
  return s === "[killed]" ? { how: "killed" } : null;
}

/** One lead-queue notification: the time it was enqueued, its task id, and whether it is the 'waiting on its own
 *  background work' notice (else it is an end; for an agent id also its 'finished' notice). */
export interface LeadNote { time: number; id: string; waiting: boolean; killed: boolean }
/** The task notifications the lead's session file enqueues (`queue-operation` / `enqueue`). */
export function leadNotesOf(text: string): LeadNote[] {
  const out: LeadNote[] = [];
  for (const line of text.split("\n")) {
    if (!line.includes("queue-operation") || !line.includes("task-notification")) continue;
    let o: any;
    try { o = JSON.parse(line); } catch { continue; }
    if (o.type !== "queue-operation" || o.operation !== "enqueue" || typeof o.content !== "string") continue;
    const t = Date.parse(o.timestamp);
    if (!Number.isFinite(t)) continue;
    for (const n of parseNotifications(o.content)) out.push({ time: Math.floor(t), id: n.id, waiting: waitingNote(n), killed: n.status === "killed" });
  }
  return out;
}

/** The lead's notes, read incrementally: the lead file only grows, so the bytes read before are cached in
 *  `.fw-console/lead-notes.json` with their offset (a shorter or different file starts over). */
export function readLeadNotes(p: Paths, leadFile: string | null): LeadNote[] {
  if (!leadFile) return [];
  const cacheFile = join(p.consoleDir, "lead-notes.json");
  let cache: { file: string; offset: number; notes: LeadNote[] } = { file: leadFile, offset: 0, notes: [] };
  try {
    const c = JSON.parse(readFileSync(cacheFile, "utf8"));
    if (c?.file === leadFile && typeof c.offset === "number" && Array.isArray(c.notes)) cache = c;
  } catch { /* none yet */ }
  let size = 0;
  try { size = statSync(leadFile).size; } catch { return cache.notes; }
  if (size < cache.offset) cache = { file: leadFile, offset: 0, notes: [] };
  if (size > cache.offset) {
    const fd = openSync(leadFile, "r");
    try {
      const buf = Buffer.alloc(Math.min(size - cache.offset, 64_000_000));
      const n = readSync(fd, buf, 0, buf.length, cache.offset);
      const text = buf.subarray(0, n).toString("utf8");
      const cut = text.lastIndexOf("\n");
      if (cut >= 0) {
        cache.notes.push(...leadNotesOf(text.slice(0, cut)));
        cache.offset += Buffer.byteLength(text.slice(0, cut + 1));
      }
    } finally { closeSync(fd); }
    try { mkdirSync(p.consoleDir, { recursive: true }); writeFileSync(cacheFile, JSON.stringify(cache)); } catch { /* read-only: recompute next time */ }
  }
  return cache.notes;
}

/** The lead's session file for a transcript `<project>/<session>/subagents/[workflows/<wf>/]agent-<id>.jsonl`:
 *  `<project>/<session>.jsonl` (null: none). */
export function leadFileOf(transcript: string): string | null {
  let d = dirname(transcript);
  while (basename(d) !== "subagents" && d !== dirname(d)) d = dirname(d);
  const f = `${dirname(d)}.jsonl`;
  return existsSync(f) ? f : null;
}

/** Add the lead's notes to an agent's facts: notifications about its own id are its notices; those about an id it
 *  launched are ends of that id. */
export function withLeadNotes(f: SigFacts, notes: LeadNote[]): SigFacts {
  const mine = new Set(f.launched.map((l) => l.id));
  const ends = [...f.ends], notices = [...f.notices];
  for (const n of notes) {
    if (n.id === f.agent) notices.push({ time: n.time, finished: !n.waiting });
    else if (mine.has(n.id) && !n.waiting) ends.push({ id: n.id, time: n.time, how: n.killed ? "killed" : "notified" });
  }
  return { ...f, ends, notices };
}

/** A shell command that waits on stdin forever when nothing feeds it: a simple `cat`, `tee` or `read` command with no
 *  file operand and no input redirection that does not follow a pipe (port-nav's `cat > /tmp/x.lean`). */
export function readsStdin(cmd: string): boolean {
  for (const part of cmd.split(/;|&&|\|\||\n/)) {
    const seg = part.trim();
    if (!seg || seg.includes("|") || seg.includes("<")) continue;
    const toks = seg.split(/\s+/);
    const w = toks[0];
    if (w !== "cat" && w !== "tee" && w !== "read") continue;
    const rest: string[] = [];
    for (let i = 1; i < toks.length; i++) {
      const x = toks[i]!;
      if (/^\d*>>?&?$/.test(x)) { i++; continue; } // a redirection, then its target
      if (/^\d*>>?/.test(x)) continue; // a redirection with its target attached
      rest.push(x);
    }
    if (w === "read" || w === "tee" || rest.every((x) => x.startsWith("-"))) return true;
  }
  return false;
}

// ---- file discovery ----
export interface Paths {
  root: string; consoleDir: string; home: string; projectsDir: string;
  /** where the transcript fold states are saved (default `<consoleDir>/watch-cache`) */
  cacheDir?: string;
}
export const cacheDirOf = (p: Paths): string => p.cacheDir ?? join(p.consoleDir, "watch-cache");
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

export function readMeta(jsonlFile: string): Record<string, unknown> | null {
  try { return JSON.parse(readFileSync(jsonlFile.replace(/\.jsonl$/, ".meta.json"), "utf8")); } catch { return null; }
}
const trCache = new Map<string, { size: number; mtimeMs: number; metaAt: number | null; tr: TranscriptInfo; sig: SigFacts }>();
let swept = false;
/** A transcript's summary and signal facts, parsed again only when the transcript or its meta changed (a long `fw
 *  watch` re-reads the ghost window every check). A changed transcript is folded from its saved state over the appended
 *  bytes when `p` is given (watch-cache.ts), else read whole. */
export function readTranscript(tf: string, id: string, p?: Paths): { tr: TranscriptInfo; sig: SigFacts } | null {
  try {
    const st = statSync(tf), metaAt = metaMtime(tf);
    const hit = trCache.get(tf);
    if (hit && hit.size === st.size && hit.mtimeMs === st.mtimeMs && hit.metaAt === metaAt) return hit;
    const dir = p ? cacheDirOf(p) : null;
    if (dir && !swept) { swept = true; sweepCache(dir, Date.now()); }
    const { state } = foldFile(tf, st.size, st.ino, dir);
    const e = { size: st.size, mtimeMs: st.mtimeMs, metaAt, tr: finishInfo(state, readMeta(tf), metaAt), sig: finishSignals(id, state).facts };
    trCache.set(tf, e);
    return e;
  } catch { return null; }
}
/** The mtime of a transcript's meta file (null: none). */
export function metaMtime(jsonlFile: string): number | null {
  try { return statSync(jsonlFile.replace(/\.jsonl$/, ".meta.json")).mtimeMs; } catch { return null; }
}
/** The background ids an agent launched within `ms` before `now` whose end its own transcript does not show (a
 *  superset of the pending ids of Fw.Obs.Signals: the lead's notes and output markers are not read here). */
export function pendingBg(s: SigFacts, now: number, ms: number): string[] {
  const ended = new Set(s.ends.map((e) => e.id));
  return s.launched.filter((l) => !ended.has(l.id) && now - l.time <= ms).map((l) => l.id);
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

interface SpoolMemo { size: number; mtimeMs: number; sum: SpoolSummary }
/** Per spool directory: each spool file's summary by (size, mtime), a memo of the pure `summarizeSpool(parseSpool(text))`
 *  (kept only for the files of the last pass). */
const spoolMemo = new Map<string, Map<string, SpoolMemo>>();

/** `owners`, when given, is filled with Bash task id -> agent id for every agent kept in the snapshot. */
export function collectAgents(p: Paths, now: number, owners?: Map<string, string>): AgentSnap[] {
  const spoolDir = join(p.consoleDir, "spool");
  const spools = new Map<string, SpoolSummary>();
  let files: string[] = [];
  try { files = readdirSync(spoolDir); } catch { /* no spool yet */ }
  const memo = spoolMemo.get(spoolDir) ?? new Map<string, SpoolMemo>(), seen = new Map<string, SpoolMemo>();
  for (const f of files) {
    if (!f.endsWith(".jsonl") || f === "main.jsonl") continue;
    try {
      const file = join(spoolDir, f), st = statSync(file), hit = memo.get(f);
      const e = hit && hit.size === st.size && hit.mtimeMs === st.mtimeMs ? hit
        : { size: st.size, mtimeMs: st.mtimeMs, sum: summarizeSpool(parseSpool(readFileSync(file, "utf8"))) };
      seen.set(f, e);
      spools.set(f.slice(0, -6), e.sum);
    } catch { /* unreadable */ }
  }
  spoolMemo.set(spoolDir, seen);
  const transcripts = findTranscripts(p);
  const ids = new Set([...spools.keys(), ...transcripts.keys()]);
  const kept: { id: string; sp: SpoolSummary | null; tf: string | undefined; tr: TranscriptInfo | null; pending: string[]; closed: boolean }[] = [];
  for (const id of ids) {
    const sp = spools.get(id) ?? null;
    const tf = transcripts.get(id);
    // cheap pre-filter before reading a big transcript: skip agents not written within the ghost window (an ended
    // agent with a worktree is always read). Not from meta.finished: it is stale on a resumed agent and is set while
    // the agent still holds background work (a held agent writes nothing for hours).
    let tmtime = 0;
    if (tf) { try { tmtime = statSync(tf).mtimeMs; } catch { /* gone */ } }
    const lastGuess = Math.max(sp?.lastAt ?? 0, tmtime);
    if (now - lastGuess > SCOPE.ghostMs && !(sp?.stoppedAt != null && hasWorktree(p, id))) continue;
    let tr: TranscriptInfo | null = null, pending: string[] = [], closed = false;
    if (tf) {
      const r = readTranscript(tf, id, p);
      if (r) {
        tr = r.tr;
        pending = pendingBg(withLeadNotes(r.sig, readLeadNotes(p, leadFileOf(tf))), now, SCOPE.ghostMs);
        closed = r.sig.bounds.at(-1)?.start === false; // the last turn ended (end_turn or a turn-ending tool result)
      }
    }
    kept.push({ id, sp, tf, tr, pending, closed });
  }
  // parent link: a child's meta.toolUseId is the id of the Agent call in its parent's transcript (none: the lead)
  const owner = new Map<string, string>();
  for (const k of kept) for (const c of k.tr?.agentCalls ?? []) owner.set(c, k.id);
  if (owners) for (const k of kept) for (const t of k.tr?.bgTasks ?? []) owners.set(t, k.id);
  const wfCache = new Map<string, boolean>();
  const out: AgentSnap[] = [];
  for (const { id, sp, tf, tr, pending, closed } of kept) {
    const lastAt = Math.max(sp?.lastAt ?? 0, tr?.lastAt ?? 0);
    if (lastAt === 0) continue;
    // an ended agent (spool Stop; no spool: its last turn ended) leaves after keepDoneMs unless it has a worktree or
    // still holds background ids
    const ended = sp ? sp.stoppedAt !== null : !!tr?.endedTurn || closed;
    if (ended && now - lastAt > SCOPE.keepDoneMs && !hasWorktree(p, id) && pending.length === 0) continue;
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
      sessionPid: sp?.sessionPid ?? null,
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

/** How long a watch pass waits for the shared gh-budget lock before it skips its gh call (TS stand-in for Lean `RunSplit.watchLockWaitMs`). */
export const WATCH_LOCK_WAIT_MS = 3000;

/** Wraps a Runner so every `gh` call is booked with the request budget (`ghCharged`, fwcore decides). Other programs pass
 *  through. A wait or stop from the budget, a gh failure, or an unavailable budget (no fwcore) is a failed call (`null`):
 *  the caller carries the previous value forward. The collector never blocks on the budget. `getEnv` is lazy and cached. */
export function chargedRunner(base: Runner, getEnv: () => Env): Runner {
  return async (cmd, args, timeout, cwd, anyExit) => {
    if (cmd !== "gh") return base(cmd, args, timeout, cwd, anyExit);
    try {
      watchGh.start();
      const res = await ghCharged(getEnv(), args, { cost: args.includes("--workflow") ? 2 : 3, timeoutMs: timeout, lockWaitMs: WATCH_LOCK_WAIT_MS }).finally(() => watchGh.end());
      return res.ran && res.code === 0 ? res.stdout : null;
    } catch { return null; }
  };
}
let sysEnv: { cwd: string; env: Env } | null = null;
/** The parts (lock, backoff, call) of the gh calls of the current `fw watch` pass; `watch.ts` writes them as sub-spans of `watch pass`. */
export const watchGh = new GhClock();
const systemEnv = (cwd: string): Env => (sysEnv?.cwd === cwd ? sysEnv.env : (sysEnv = { cwd, env: phasedEnv(realEnv(cwd), (e) => watchGh.on(e)) }).env);

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
      headSha: typeof r.headSha === "string" ? r.headSha : "", // the set of a run: fwcore groups by (workflow, branch, headSha)
    }));
  } catch { return []; }
}

/** One `ps -A -o pid=,ppid=,etime=,comm=` row: the age comes from etime, so no locale-dependent date is parsed. */
export interface PsRow { pid: number; ppid: number; ageMs: number; comm: string }
/** The `lake` processes in the process table (the local builders). */
export const countBuilders = (rows: PsRow[]): number => rows.filter((r) => exe(r.comm) === "lake").length;
/** The live holders of the heavy-job lock (scripts/heavy-lock.mjs, `<git dir>/fw-heavy/holders/<pid>.json`): the same
 *  rule as Lean `Fw.Sched.Heavy.prune` (a holder counts only when its pid AND start time match a running process; a reused
 *  pid has another start), over the `ps lstart` rows `starts`. */
export function countHeavy(root: string, starts: StartRow[]): number {
  try {
    const dir = join(root, ".git", "fw-heavy", "holders");
    let n = 0;
    for (const f of readdirSync(dir)) {
      try {
        const h = JSON.parse(readFileSync(join(dir, f), "utf8")) as { pid?: unknown; start?: unknown };
        if (starts.some((r) => r.pid === h.pid && r.start === h.start)) n++;
      } catch { /* a half-written or foreign file is not a holder */ }
    }
    return n;
  } catch { return 0; }
}
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

/** One declared long-runner in `.fw-console/keep.json` (written by `fw watch --keep <pid>`): its pid, its absolute start
 *  time (seconds since the epoch, from `ps lstart`) and the lead's note. Entries without `start` (the older
 *  `startedAt` format) are dropped. */
export interface KeepEntry { pid: number; start: number; note: string | null }
export function readKeep(p: Paths): KeepEntry[] {
  try {
    const j = JSON.parse(readFileSync(join(p.consoleDir, "keep.json"), "utf8"));
    return (Array.isArray(j) ? j : []).filter((e): e is KeepEntry =>
      Number.isInteger(e?.pid) && Number.isInteger(e?.start)).map((e) => ({ pid: e.pid, start: e.start, note: str(e.note) }));
  } catch { return []; }
}
export function writeKeep(p: Paths, entries: KeepEntry[]): void {
  mkdirSync(p.consoleDir, { recursive: true });
  writeFileSync(join(p.consoleDir, "keep.json"), JSON.stringify(entries, null, 1) + "\n");
}

/** A process with its absolute start time (seconds since the epoch) and command line. */
export interface StartRow { pid: number; start: number; args: string }
/** `ps` with a fixed locale and zone, so `lstart` reads the same for a process at every check. */
export const PS_START = ["LC_ALL=C", "TZ=UTC", "ps", "-A", "-o", "pid=,lstart=,args="];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** `env PS_START` output (`pid Www Mmm d hh:mm:ss yyyy args`, UTC) -> rows; malformed lines are skipped. */
export function parseStartRows(out: string | null): StartRow[] {
  const rows: StartRow[] = [];
  for (const line of (out ?? "").split("\n")) {
    const m = /^\s*(\d+)\s+[A-Z][a-z]{2}\s+([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\d{4})(?:\s+(.*?))?\s*$/.exec(line);
    const mon = m ? MONTHS.indexOf(m[2]!) : -1;
    if (!m || mon < 0) continue;
    const ms = Date.UTC(Number(m[7]), mon, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
    rows.push({ pid: Number(m[1]), start: Math.floor(ms / 1000), args: m[8] ?? "" });
  }
  return rows;
}
/** fwcore `ops.watchKeep` (Fw.Ops.WatchDiff): `live` = indices of the entries whose pid and start match a row, `keep` =
 *  exempt pids (live entries and allowlisted command lines). */
export type KeepDecide = (entries: { pid: number; start: number }[], rows: StartRow[]) => Promise<{ live: number[]; keep: number[] }>;

/** The previous check's system part, if it is recent enough to carry forward (SCOPE.carryMs). */
export interface Prev { at: number; system: SystemSnap; critical?: string[]; ghDegraded?: boolean; contended?: boolean }

/** `owners`: Bash task id -> agent id (from `collectAgents`); trees whose task id is not in it have no owner. */
/** `keepOf`: fwcore's keep decision; null leaves `keep` empty. A failed `ps` or decision keeps the previous value
 *  (stale `keep`). */
export async function collectSystem(p: Paths, prev: Prev | null = null, now = Date.now(), exec: Runner = chargedRunner(run, () => systemEnv(p.root)),
  owners: Map<string, string> = new Map(), keepOf: KeepDecide | null = null): Promise<SystemSnap> {
  const [mem, wt, dock, ci, ps, psStart] = await Promise.all([
    exec("sysctl", ["-n", "kern.memorystatus_vm_pressure_level"], 2000),
    exec("git", ["worktree", "list", "--porcelain"], 3000, p.root),
    exec("docker", ["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.CreatedAt}}"], 3000),
    exec("gh", ["run", "list", "--limit", "20", "--json", "databaseId,workflowName,headBranch,status,conclusion,createdAt,updatedAt,headSha"], 10000, p.root),
    exec("ps", ["-A", "-o", "pid=,ppid=,etime=,comm="], 3000),
    exec("env", PS_START, 3000),
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
  let keep: number[] = [];
  if (ps === null) { stale.push("procs"); procs = old?.procs ?? []; keep = old?.keep ?? []; }
  else {
    // lsof exits 1 when a listed pid has ended meanwhile (anyExit keeps the others); on a timeout the owners come
    // from the previous check (keepNames)
    const lsof = procs.length ? await exec("lsof", ["-a", "-d", "1", "-Fpn", "-p", procs.map((q) => q.pid).join(",")], 3000, undefined, true) : "";
    procs = keepNames(ownProcs(procs, parseTaskIds(text(lsof)), owners), prev?.system.procs ?? []);
    if (keepOf) {
      const entries = readKeep(p);
      const scope = new Set([...procs.flatMap((q) => [q.pid, ...q.pids]), ...entries.map((e) => e.pid)]);
      try {
        if (psStart === null) throw new Error("ps lstart failed");
        keep = (await keepOf(entries, parseStartRows(text(psStart)).filter((r) => scope.has(r.pid)))).keep;
      } catch { stale.push("keep"); keep = old?.keep ?? []; }
    }
  }
  const consolePids = collectConsolePids(p);
  const svcs = await collectSvcs(p, exec); // never fails as a whole: a service it cannot judge is reported unknown
  let disk = 0;
  try { const s = statfsSync(p.root); disk = Math.floor((Number(s.bavail) * Number(s.bsize)) / 1e9); } catch { /* unknown -> 0 raises sys.diskLow */ }
  return {
    load1: Math.round(loadavg()[0]! * 100) / 100, loadFloor: Math.floor(loadavg()[0]!),
    load: { builders: countBuilders(rows), heavyJobs: countHeavy(p.root, parseStartRows(text(psStart))), prevContended: prev?.contended === true }, memPressure: parseMemLevel(text(mem)),
    diskFreeGB: disk, simLock: collectSimLock(p.root), docker, worktrees: parseWorktreeCount(text(wt)),
    consolePids, ci: ciRuns, procs, services: [process.pid, ...consolePids], keep, svcs, stale, feedback: collectFeedback(p),
    ...(ps === null || rows.length === 0 ? {} : { alivePids: rows.map((r) => r.pid) }),
  };
}

/** The feedback events of the console log (`<consoleDir>/events.jsonl`, written only by console-api), oldest first, in the wire shape.
 *  Only I/O: the log may hold events the reducer refused to act on; fwcore's fold (the reducer's rule) decides which count. An unreadable
 *  log gives no events. */
export function collectFeedback(p: Paths): FeedbackEv[] {
  let raw: string;
  try { raw = readFileSync(join(p.consoleDir, "events.jsonl"), "utf8"); } catch { return []; }
  const out: FeedbackEv[] = [];
  for (const line of raw.split("\n")) {
    if (!line.includes('"review.feedback')) continue;
    let e: Record<string, unknown>;
    try { e = JSON.parse(line); } catch { continue; }
    const post = e.type === "review.feedback", reply = e.type === "review.feedback.reply";
    const ref = post ? e.id : e.to;
    if (!(post || reply) || typeof e.flag !== "string" || typeof ref !== "string" || typeof e.text !== "string" || !Number.isInteger(e.ts) || (e.ts as number) < 0) continue;
    out.push({ kind: post ? "post" : "reply", flag: e.flag, ref, text: e.text, ts: e.ts as number });
  }
  return out;
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
  get: PlanFetch = getJson, keepOf: KeepDecide | null = null, ghGet?: GhFetch): Promise<Snapshot> {
  const owners = new Map<string, string>();
  const agents = collectAgents(p, now, owners);
  const [system, crit, gh] = await Promise.all([collectSystem(p, prev, now, undefined, owners, keepOf), collectCritical(p, process.env, get),
    collectGh(prev?.ghDegraded === true, ghGet)]);
  system.gh = gh;
  ensureSampler(p);
  const { critical, stale } = carryCritical(crit, prev, now);
  if (stale) system.stale.push("plan");
  return { now, params, agents, lead: collectLead(p), system, prevAt: prev?.at ?? null, critical };
}

// ---- timing samples (timing-alert): the spans of .fw-console/timings.jsonl as the samples of `obs.slow` ----
/** A `Fw.Obs.Timing.Sample` on the wire. */
export interface TimingSample { tool: string; step: string; durMs: number; host: "local" | "ci"; load: number; runKind?: string; exit?: number; skipped?: true; waitMs?: number; waits?: { why: string; ms: number }[] }
/** Spans in time order -> samples (the last `cap` ones: a bound on the input size, not a threshold; the verdict is Lean's).
 *  Lines that do not parse or lack a field are skipped. `load` is the floor of the 1-min load average; an optional span `kind` (the dispatch input digest) is the run kind of the history. */
export function parseSamples(text: string, cap = 3000): TimingSample[] {
  const rows: { at: number; s: TimingSample }[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    try {
      const o = JSON.parse(line);
      if (typeof o.tool !== "string" || typeof o.step !== "string" || !Number.isFinite(o.durMs) || o.durMs < 0 || (o.host !== "local" && o.host !== "ci")) continue;
      rows.push({ at: Number.isFinite(o.startMs) ? o.startMs : 0, s: { tool: o.tool, step: o.step, durMs: Math.round(o.durMs), host: o.host, load: Number.isFinite(o.load) ? Math.floor(Math.max(0, o.load)) : 0, ...(typeof o.kind === "string" && o.kind !== "" ? { runKind: o.kind } : {}), ...(Number.isInteger(o.exit) ? { exit: o.exit } : {}), ...(o.skipped === true ? { skipped: true as const } : {}), ...queueOf(o.queue) } });
    } catch { /* partial line */ }
  }
  return rows.sort((a, b) => a.at - b.at).slice(-cap).map((r) => r.s);
}
function queueOf(q: unknown): { waitMs?: number; waits?: { why: string; ms: number }[] } {
  const o = q as { waitMs?: unknown; waits?: unknown } | null | undefined;
  if (o === null || typeof o !== "object" || typeof o.waitMs !== "number" || !(o.waitMs > 0)) return {};
  return { waitMs: Math.round(o.waitMs), waits: parseWaits(o.waits) };
}
/** The samples of the console's timings file (empty when there is none). */
export function readSamples(p: Paths): TimingSample[] {
  try { return parseSamples(readFileSync(join(p.consoleDir, "timings.jsonl"), "utf8")); } catch { return []; }
}

// ---- resource baseline (task sup-baseline): a 20 s per-kind footprint sampler ----
// TS STAND-IN: `argv0Base`, `roleOf`, `kindAt`, `kindsOf`, `resVerdict` and `trippedBy` mirror Fw.Obs.Health.Res (lean/Fw/Obs/Health.lean, proved there);
// test/watch-collect-sup.test.ts replays packages/contracts/golden/obs/sup-health.jsonl against them. The rest is I/O glue.
export type ProcKind = "leanBuild" | "leanServe" | "fwcore" | "node" | "pnpm" | "chromium" | "simulator" | "webkit" | "system" | "other";
export const PROC_KINDS: readonly ProcKind[] = ["leanBuild", "leanServe", "fwcore", "node", "pnpm", "chromium", "simulator", "webkit", "system", "other"];
/** `Fw.Obs.Health.Res.ProcKind.heavy`: our builds, browsers, Simulator device and Safari; never the language server or a system service. */
export const HEAVY_KINDS: ReadonlySet<ProcKind> = new Set<ProcKind>(["leanBuild", "chromium", "simulator", "webkit"]);
/** `Fw.Obs.Health.Res.Role`: a plain kind (its own name) or what the program name says before ancestry and arguments are read. */
export type Role = ProcKind | "leanTool" | "simRoot" | "safari" | "safariDriver" | "webkitHelper";
/** `Fw.Obs.Health.Res.kindTable`: executable basename to role. */
export const KIND_TABLE: ReadonlyMap<string, Role> = new Map<string, Role>([
  ["lean", "leanTool"], ["lake", "leanTool"], ["fwcore", "fwcore"], ["fwtest", "fwcore"], ["node", "node"], ["pnpm", "pnpm"],
  ["Chromium", "chromium"], ["Chromium Helper", "chromium"], ["Chromium Helper (Renderer)", "chromium"], ["Chromium Helper (GPU)", "chromium"],
  ["chrome-headless-shell", "chromium"], ["headless_shell", "chromium"], ["chrome_crashpad_handler", "chromium"],
  ["launchd_sim", "simRoot"], ["com.apple.CoreSimulator.CoreSimulatorService", "system"],
  ["Safari", "safari"], ["safaridriver", "safariDriver"],
  ["com.apple.WebKit.WebContent", "webkitHelper"], ["com.apple.WebKit.Networking", "webkitHelper"], ["com.apple.WebKit.GPU", "webkitHelper"]]);
/** `Fw.Obs.Health.Res.Proc` (named ProcRow here, `Proc` is the watcher's own); `args` is read only for `lake`, `lean` and `launchd_sim` (empty otherwise). */
export interface ProcRow { pid: number; ppid: number; comm: string; args: string }
/** `Fw.Obs.Health.Res.Device`. */
export interface Device { udid: string; name: string }
/** `Fw.Obs.Health.Res.argv0Base`: the part after the last `/`, else the first word of a retitled process. */
export const argv0Base = (comm: string): string => (comm.includes("/") ? (comm.split("/").at(-1) ?? comm) : (comm.split(" ")[0] ?? comm));
/** `Fw.Obs.Health.Res.roleOf`. */
export const roleOf = (p: ProcRow): Role | undefined => KIND_TABLE.get(argv0Base(p.comm));
const hasSub = (s: string, sub: string): boolean => sub !== "" && s.split(sub).length > 1;
const firstArg = (args: string): string => args.split(" ").slice(1)[0] ?? "";
const serveVerb = (args: string): boolean => ["serve", "--server", "--worker"].includes(firstArg(args));
const isOurSimRoot = (devs: readonly Device[], p: ProcRow): boolean => roleOf(p) === "simRoot" && devs.some((d) => d.name.startsWith("fw-") && hasSub(p.args, d.udid));
const isServeRoot = (p: ProcRow): boolean => roleOf(p) === "leanTool" && serveVerb(p.args);
const isDriver = (p: ProcRow): boolean => roleOf(p) === "safariDriver";
const isSafari = (p: ProcRow): boolean => roleOf(p) === "safari";
/** `Fw.Obs.Health.Res.kindAt`: the kind of a process from its own name and arguments and its ancestors (parent first). */
export function kindAt(devs: readonly Device[], p: ProcRow, anc: readonly ProcRow[]): ProcKind {
  const chain = [p, ...anc];
  if (chain.some((q) => isOurSimRoot(devs, q))) return "simulator";
  const r = roleOf(p);
  switch (r) {
    case undefined: case "simRoot": case "safariDriver": return "other";
    case "leanTool": return chain.some(isServeRoot) ? "leanServe" : "leanBuild";
    case "safari": return anc.some(isDriver) ? "webkit" : "other";
    case "webkitHelper": return anc.some(isSafari) && anc.some(isDriver) ? "webkit" : "system";
    default: return r;
  }
}
/** `Fw.Obs.Health.Res.ancestors`: the ancestors of `p`, parent first, by at most `n` steps (a parent loop stops). */
function ancestorsOf(byPid: ReadonlyMap<number, ProcRow>, p: ProcRow, n: number): ProcRow[] {
  const out: ProcRow[] = [];
  let cur = p;
  for (let i = 0; i < n; i++) {
    const q = byPid.get(cur.ppid);
    if (!q || q.pid === cur.pid) break;
    out.push(q);
    cur = q;
  }
  return out;
}
/** `Fw.Obs.Health.Res.kindsOf`: the kind of each running process, in order. */
export function kindsOf(devs: readonly Device[], ps: readonly ProcRow[]): ProcKind[] {
  const byPid = new Map<number, ProcRow>();
  for (const p of ps) if (!byPid.has(p.pid)) byPid.set(p.pid, p);
  return ps.map((p) => kindAt(devs, p, ancestorsOf(byPid, p, ps.length)));
}

/** `Fw.Obs.Health.Res.Params` (first guesses, revised after the first day of data; `swapPct` is flagged: swap is dynamic on macOS). */
export interface ResParams { swapPct: number; cmprsPct: number; freePct: number; quietCenti: number }
export const RES_PARAMS: ResParams = { swapPct: 90, cmprsPct: 50, freePct: 15, quietCenti: 200 };
/** `Fw.Obs.Health.Res.Obs`: `procs` lists the kinds present, loads in hundredths, memory in MB, free memory in percent. */
export interface ResObs { procs: ProcKind[]; loadCenti: number; swapUsedMB: number; swapTotalMB: number; compressorMB: number; ramMB: number; freePct: number }
export type ResVerdict = "quiet" | "busy" | "pressured";
/** `Fw.Obs.Health.Res.swapHigh`, `cmprsHigh`, `freeLow`: which pressure condition holds. */
export function trippedBy(p: ResParams, o: ResObs): { swap: boolean; cmprs: boolean; free: boolean } {
  return {
    swap: o.swapTotalMB > 0 && p.swapPct * o.swapTotalMB <= 100 * o.swapUsedMB,
    cmprs: o.ramMB > 0 && p.cmprsPct * o.ramMB <= 100 * o.compressorMB,
    free: o.freePct <= p.freePct,
  };
}
/** `Fw.Obs.Health.Res.verdict`: `pressured` on swap, compressor or free memory, else `busy` on a heavy process or load, else `quiet`. */
export function resVerdict(p: ResParams, o: ResObs): ResVerdict {
  const t = trippedBy(p, o);
  if (t.swap || t.cmprs || t.free) return "pressured";
  return o.procs.some((k) => HEAVY_KINDS.has(k)) || p.quietCenti <= o.loadCenti ? "busy" : "quiet";
}

const UNIT_MB: Record<string, number> = { B: 1 / 1048576, K: 1 / 1024, M: 1, G: 1024, T: 1048576 };
/** `top` size ("1245M", "907K", "14G", "0B") in MB; a trailing `+`/`-` (changed since the last sample) is ignored; null when malformed. */
export function parseSize(s: string): number | null {
  const m = /^(\d+(?:\.\d+)?)([BKMGT])[+-]?$/.exec(s);
  return m ? Number(m[1]) * UNIT_MB[m[2]!]! : null;
}
export interface TopRow { pid: number; memMB: number; cmprsMB: number }
/** `top -l 1 -stats pid,mem,cmprs`: MEM and CMPRS per process. MEM is phys_footprint (top libtop.c:1631@1e3b6ca), which already contains the
 *  task's compressed internal memory (xnu osfmk/kern/task.c:1226-1233@f6217f8); CMPRS is that compressed part (task.c:6050), shown on its own. */
export function parseTop(out: string | null): { rows: TopRow[]; compressorMB: number | null } {
  const rows: TopRow[] = [];
  let compressorMB: number | null = null;
  for (const line of (out ?? "").split("\n")) {
    const c = /^PhysMem:.*?(\S+) compressor/.exec(line);
    if (c) compressorMB = parseSize(c[1]!);
    const m = /^\s*(\d+)\s+(\S+)\s+(\S+)\s*$/.exec(line);
    const mem = m ? parseSize(m[2]!) : null;
    const cm = m ? parseSize(m[3]!) : null;
    if (m && mem !== null && cm !== null) rows.push({ pid: Number(m[1]), memMB: mem, cmprsMB: cm });
  }
  return { rows, compressorMB };
}
/** `ps -A -o pid=,ppid=,comm=` as processes (no arguments yet). */
export function parseProcs(out: string | null): ProcRow[] {
  const ps: ProcRow[] = [];
  for (const line of (out ?? "").split("\n")) {
    const m = /^\s*(\d+)\s+(\d+)\s+(.+?)\s*$/.exec(line);
    if (m) ps.push({ pid: Number(m[1]), ppid: Number(m[2]), comm: m[3]!, args: "" });
  }
  return ps;
}
/** `ps -o pid=,command= -p <pids>` as pid to command line. */
export function parseArgs(out: string | null): Map<number, string> {
  const by = new Map<number, string>();
  for (const line of (out ?? "").split("\n")) {
    const m = /^\s*(\d+)\s+(.+?)\s*$/.exec(line);
    if (m) by.set(Number(m[1]), m[2]!);
  }
  return by;
}
/** The processes whose command line the classifier reads: `lake`, `lean` and `launchd_sim`. */
export const wantsArgs = (p: ProcRow): boolean => { const r = roleOf(p); return r === "leanTool" || r === "simRoot"; };
const UDID = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/;
/** The Simulator device id in a `launchd_sim` command line, or null. */
export const udidOf = (p: ProcRow): string | null => (roleOf(p) === "simRoot" ? (UDID.exec(p.args)?.[0] ?? null) : null);
/** `sysctl -n vm.swapusage` ("total = 6144.00M  used = 5201.62M  free = 942.38M ..."): used and total in MB. */
export function parseSwap(out: string | null): { usedMB: number; totalMB: number } | null {
  const t = /total = ([\d.]+)M/.exec(out ?? "");
  const u = /used = ([\d.]+)M/.exec(out ?? "");
  return t && u ? { usedMB: Math.floor(Number(u[1])), totalMB: Math.floor(Number(t[1])) } : null;
}
/** `memory_pressure -Q`: the system-wide free memory in percent (the pressure input of the verdict, as scripts/heavy-lock.mjs observes it). */
export function parseFreePct(out: string | null): number | null {
  const m = /free percentage:\s*(\d+)%/.exec(out ?? "");
  return m ? Number(m[1]) : null;
}

export interface KindUse { n: number; memMB: number; cmprsMB: number }
/** The footprint of a kind: the `top` MEM column (phys_footprint, compressed memory included). Pages shared between processes are counted once
 *  per process. */
export const footMB = (u: KindUse): number => u.memMB;
/** One line of `<consoleDir>/sup-samples.jsonl`. `verdict` is null when a reading is missing (named in `partial`). */
export interface SupSample {
  ts: number; verdict: ResVerdict | null; loadCenti: number; ramMB: number; swapUsedMB: number | null; swapTotalMB: number | null;
  compressorMB: number | null; freePct: number | null; kinds: Record<ProcKind, KindUse>; costMs: number; partial: string[];
}
/** Per-kind count and footprint: every `top` row is given the kind of its pid (a pid `ps` no longer lists is `other`). */
export function reduceKinds(rows: TopRow[], kindOfPid: ReadonlyMap<number, ProcKind>): Record<ProcKind, KindUse> {
  const acc = Object.fromEntries(PROC_KINDS.map((k) => [k, { n: 0, memMB: 0, cmprsMB: 0 }])) as Record<ProcKind, KindUse>;
  for (const r of rows) {
    const u = acc[kindOfPid.get(r.pid) ?? "other"];
    u.n++; u.memMB += r.memMB; u.cmprsMB += r.cmprsMB;
  }
  for (const k of PROC_KINDS) { acc[k].memMB = Math.round(acc[k].memMB); acc[k].cmprsMB = Math.round(acc[k].cmprsMB); }
  return acc;
}
/** The readings of one sample (null: the command failed). `args` is the `ps -p` output for `wantsArgs` processes, `deviceNames` the name of each Simulator device id found. */
export interface SupReadings { top: string | null; ps: string | null; args: string | null; swap: string | null; free: string | null; deviceNames: Record<string, string | null> }
/** The processes with their command lines merged in, and the Simulator devices read for them. */
export function joinProcs(ps: ProcRow[], argsOut: string | null, deviceNames: Record<string, string | null>): { procs: ProcRow[]; devices: Device[]; missing: string[] } {
  const args = parseArgs(argsOut);
  const procs = ps.map((p) => (wantsArgs(p) ? { ...p, args: args.get(p.pid) ?? "" } : p));
  const missing: string[] = [];
  if (argsOut === null && ps.some(wantsArgs)) missing.push("args");
  const devices: Device[] = [];
  for (const u of new Set(procs.map(udidOf).filter((x): x is string => x !== null))) {
    const name = deviceNames[u];
    if (typeof name === "string") devices.push({ udid: u, name }); else missing.push("device");
  }
  return { procs, devices, missing: [...new Set(missing)] };
}
/** One sample from the readings, the 1-min load and the RAM size in MB. */
export function buildSample(ts: number, outs: SupReadings, load1: number, ramMB: number, costMs: number, p: ResParams = RES_PARAMS): SupSample {
  const top = parseTop(outs.top);
  const swap = parseSwap(outs.swap);
  const freePct = parseFreePct(outs.free);
  const joined = joinProcs(parseProcs(outs.ps), outs.args, outs.deviceNames);
  const partial: string[] = [];
  if (top.rows.length === 0) partial.push("top");
  if (top.compressorMB === null) partial.push("compressor");
  if (outs.ps === null) partial.push("ps");
  partial.push(...joined.missing);
  if (swap === null) partial.push("swap");
  if (freePct === null) partial.push("free");
  const kindOfPid = new Map<number, ProcKind>();
  kindsOf(joined.devices, joined.procs).forEach((k, i) => kindOfPid.set(joined.procs[i]!.pid, k));
  const kinds = reduceKinds(top.rows, kindOfPid);
  const loadCenti = Math.floor(Math.max(0, load1) * 100);
  const compressorMB = top.compressorMB === null ? null : Math.round(top.compressorMB);
  const verdict = partial.length === 0
    ? resVerdict(p, { procs: PROC_KINDS.filter((k) => kinds[k].n > 0), loadCenti, swapUsedMB: swap!.usedMB, swapTotalMB: swap!.totalMB, compressorMB: compressorMB!, ramMB, freePct: freePct! })
    : null;
  return { ts, verdict, loadCenti, ramMB, swapUsedMB: swap?.usedMB ?? null, swapTotalMB: swap?.totalMB ?? null, compressorMB, freePct, kinds, costMs, partial };
}

export const SUP_FILE = "sup-samples.jsonl";
export const SUP_EVERY_MS = 20_000;
/** Takes one sample and appends it to `<consoleDir>/sup-samples.jsonl`, unless the file is younger than `minAgeMs` (another
 *  watcher sampled): returns the sample, or null when skipped. Never throws. A command line is read only for `lake`, `lean` and `launchd_sim`
 *  and a Simulator device name only for the ids found there (from the device's `device.plist`, no CoreSimulator call); none is stored. */
export async function sampleOnce(p: Paths, exec: Runner = run, now = Date.now(), minAgeMs = 15_000, load1 = loadavg()[0]!, ramMB = Math.floor(totalmem() / 1048576)): Promise<SupSample | null> {
  const file = join(p.consoleDir, SUP_FILE);
  try { if (now - statSync(file).mtimeMs < minAgeMs) return null; } catch { /* no file yet */ }
  const t0 = Date.now();
  const [top, ps, swap, free] = await Promise.all([
    exec("top", ["-l", "1", "-stats", "pid,mem,cmprs"], 20_000), exec("ps", ["-A", "-o", "pid=,ppid=,comm="], 5000),
    exec("sysctl", ["-n", "vm.swapusage"], 3000), exec("memory_pressure", ["-Q"], 10_000)]);
  const procs = parseProcs(text(ps));
  const want = procs.filter(wantsArgs).map((q) => q.pid);
  const args = want.length > 0 ? text(await exec("ps", ["-o", "pid=,command=", "-p", want.join(",")], 5000)) : "";
  const withArgs = joinProcs(procs, args, {}).procs;
  const deviceNames: Record<string, string | null> = {};
  await Promise.all([...new Set(withArgs.map(udidOf).filter((x): x is string => x !== null))].map(async (u) => {
    const plist = join(p.home, "Library", "Developer", "CoreSimulator", "Devices", u, "device.plist");
    deviceNames[u] = text(await exec("plutil", ["-extract", "name", "raw", "-o", "-", plist], 3000))?.trim() ?? null;
  }));
  const sample = buildSample(now, { top: text(top), ps: text(ps), args, swap: text(swap), free: text(free), deviceNames }, load1, ramMB, Date.now() - t0);
  try {
    mkdirSync(p.consoleDir, { recursive: true });
    appendFileSync(file, `${JSON.stringify(sample)}\n`);
  } catch { return null; }
  return sample;
}
const samplers = new Map<string, NodeJS.Timeout>();
/** Starts the 20 s sampler for this console directory once per process (idempotent); the timer is unref'd, so a one-shot caller exits
 *  before the first tick and takes no sample. FW_SUP_SAMPLER=off disables it. */
export function ensureSampler(p: Paths, exec: Runner = run, everyMs = SUP_EVERY_MS): void {
  if (process.env.FW_SUP_SAMPLER === "off" || samplers.has(p.consoleDir)) return;
  let busy = false;
  const t = setInterval(() => {
    if (busy) return;
    busy = true;
    sampleOnce(p, exec).catch(() => null).finally(() => { busy = false; });
  }, everyMs);
  t.unref();
  samplers.set(p.consoleDir, t);
}
export function stopSamplers(): void {
  for (const t of samplers.values()) clearInterval(t);
  samplers.clear();
}
