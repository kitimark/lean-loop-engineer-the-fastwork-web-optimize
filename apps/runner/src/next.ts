import { execFile } from "node:child_process";
import { closeSync, existsSync, fstatSync, openSync, readFileSync, readSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { lockFacts, lockFile } from "../hooks/land-guard.mjs";
import { queuedBranches } from "./land-queue.ts";
import { heldPass, repoIdOf, wtIdOf, type ReapPass } from "./reap.ts";
import { fwcoreCall } from "./run.ts";
import {
  exe, findTranscripts, leadFileOf, markerOf, metaMtime, parsePs, readLeadNotes, startFromAge, readMeta, readsStdin, withLeadNotes,
  type LeadNote, type Paths, type Proc, type SigFacts, type SigProcKind, type Snapshot, type TranscriptSignals,
} from "./watch-collect.ts";
import { finishSignals, foldText, initFold, type FoldState } from "./watch-fold.ts";
import { tailer } from "./watch-mem.ts";

// ---- the facts (wire shape of AgentFacts) ----
/** Per transcript, the signal fold and the last handback time of the lines read so far; a pass reads only the lines appended since
 *  (spec: Fw.Obs.Fold `feed_append`), and forgets the transcripts it did not ask for. */
const transcriptTail = tailer<{ st: FoldState; hb: number | null }>(() => ({ st: initFold(true), hb: null }), (t, text) => {
  const hb = handbackAtOf(text);
  return { st: foldText(t.st, text), hb: hb === null ? t.hb : Math.max(t.hb ?? 0, hb) };
});
/** The transcript signal fold and handback time of a file, read by cursor. */
export const readTranscript = transcriptTail.read;
export interface WatchFact { kind: "task" | "agent"; id: string }
export type ChildFact = {
  pid: number; start?: number; chain: number[]; startedAt: number; watchedAt: number | null; producerExited: boolean; watch?: WatchFact;
} & ({ kind: "sleepLoop" | "build" | "other" | "stdinWait" } | { kind: "ciWait"; run: number; timeoutMin: number });
export interface HeldFact { pid: number; start: number; wt: string | null }
export interface AgentFacts {
  id: string; task: string; state: string; session: number; handbackAt: number | null;
  branch: {
    name: string; ahead: number; landed: boolean; queued: boolean; mergesClean: boolean; deps: string[];
    /** a land commit with this task's `Task:` trailer is on main (inc-watch-unlanded-after-land) */
    onMain: boolean;
    /** the branch named by the live land lock, null when none (inc-watch-alert-during-land) */
    landLock: string | null;
    /** the branch is a pending entry of the land queue (`fw land --queue`, task land-queue): `locked` in the Lean facts */
    landQueued: boolean;
  } | null;
  handoff: boolean;
  worktree: { lockPid: number | null; lockAlive: boolean; id: string | null } | null;
  ctxTokens: number; children: ChildFact[];
  ci: { id: number; workflow: string; branch: string; status: string; conclusion: string | null; startedAt: number; endedAt: number | null } | null;
  board: { id: string; done: boolean; agent: string | null } | null;
  signals?: SigFacts;
  reapHeld: HeldFact[];
}
export interface NextAction { action: string; [k: string]: unknown }
export interface NextReply {
  agents?: { id: string; actions: NextAction[]; signal?: { state: string; ids: string[] }; handbackAt?: number | null; keep?: boolean }[];
}

// ---- classification of one process tree (pure) ----
/** `waitrun.sh <run> [timeoutMin]` (default 10 min) or `fw ci wait <run> [--timeout <min>]` in a command line. */
const CI_WAIT = /waitrun\.sh\s+(\d+)(?:\s+(\d+))?|\bci\s+wait\s+(\d+)(?:.*?--timeout\s+(\d+))?/;
/** An open poll loop: `until … ; do sleep N` or `while … ; do … sleep`, as a command word (also inside a shell
 *  wrapper's `-c` or `eval '…'`; its condition may hold pipes, as in `until grep -q x f | head -1; do`; a
 *  `… | while read` consumer is not such a loop). */
const SLEEP_LOOP = /(?<!\|\s*)(?<![\w.\/-])(?:until|while)\b[^]*?;\s*do\b[^]*?\bsleep\b/;
const BUILD = /\b(?:lake|vitest|tsc|jest|cargo|xcodebuild|make)\b|\b(?:pnpm|npm|yarn|node)\b.*\b(?:test|build|run)\b/;
export interface Classified { kind: ChildFact["kind"]; run?: number; timeoutMin?: number; watchedFile: string | null }
/** `rootCmd`: the tree's root shell command line; `treeCmds`: the commands of its descendants. */
export function classifyTree(rootCmd: string, treeCmds: string[] = []): Classified {
  const w = CI_WAIT.exec(rootCmd);
  if (w) return { kind: "ciWait", run: Number(w[1] ?? w[3]), timeoutMin: Number(w[2] ?? w[4] ?? 10), watchedFile: null };
  if (SLEEP_LOOP.test(rootCmd)) return { kind: "sleepLoop", watchedFile: watchedFileOf(rootCmd) };
  if ([rootCmd, ...treeCmds].some((c) => BUILD.test(c))) return { kind: "build", watchedFile: null };
  return { kind: "other", watchedFile: null };
}
/** The file an `until … <file>; do` loop looks at: the last absolute path in the clause before `; do`. */
export function watchedFileOf(cmd: string): string | null {
  const m = /\b(?:until|while)\b([^]*?);\s*do\b/.exec(cmd);
  if (!m) return null;
  const toks = m[1]!.split(/\s+/).map((t) => t.replace(/^['"]+|['"]+$/g, "")).filter((t) => /^(?:\/|~\/)\S*$/.test(t) && t !== "/dev/null");
  const f = toks[toks.length - 1];
  return f ? (f.startsWith("~/") ? join(homedir(), f.slice(2)) : f) : null;
}
/** The end marker a finished Bash task leaves as the last line of its output file: `[exited with code N]` or
 *  `[killed]`. */
export const producerExitedLine = (lastLine: string) => markerOf(lastLine) !== null;
/** What a background task's command does, for Fw.Obs.Signals: reads stdin forever, is a sleep loop, or other. */
export function procKindOf(cmd: string): SigProcKind {
  return readsStdin(cmd) ? "stdin" : SLEEP_LOOP.test(cmd) ? "sleepLoop" : "other";
}

// ---- worktrees (pure) ----
export interface Worktree { path: string; branch: string | null; lockPid: number | null }
/** `git worktree list --porcelain`: path, branch short name, and the pid in `locked claude agent agent-<id> (pid N …)`. */
export function parseWorktrees(out: string | null): Worktree[] {
  const res: Worktree[] = [];
  for (const block of (out ?? "").split(/\n\n+/)) {
    let path = "", branch: string | null = null, lockPid: number | null = null;
    for (const line of block.split("\n")) {
      if (line.startsWith("worktree ")) path = line.slice(9);
      else if (line.startsWith("branch ")) branch = line.slice(7).replace(/^refs\/heads\//, "");
      else if (line.startsWith("locked")) lockPid = Number(/\(pid (\d+)/.exec(line)?.[1]) || null;
    }
    if (path) res.push({ path, branch, lockPid });
  }
  return res;
}
/** The worktree of an agent: its directory is `agent-<id>`, or its branch is named after the agent. */
export function worktreeOf(wts: Worktree[], id: string, name: string | null): Worktree | null {
  return wts.find((w) => basename(w.path) === `agent-${id}`)
    ?? (name ? wts.find((w) => w.branch !== null && [name, `wt-${name}`, `worktree-${name}`].includes(w.branch)) : undefined) ?? null;
}

// ---- the builder (pure): raw observations -> AgentFacts ----
export interface FileObs { mtimeMs: number; lastLine: string }
export interface RawAgent {
  id: string; name: string | null; task: string | null; state: string; ctxTokens: number | null; handbackAt: number | null;
  worktree: Worktree | null; ahead: number | null; landed: boolean | null;
  /** a land commit with the task's `Task:` trailer is on main (null/absent: not checked) */
  onMain?: boolean | null;
  /** `git merge-tree --write-tree main <branch>` exited 0 (null: not checked: no unlanded branch) */
  mergesClean: boolean | null;
  /** unlanded branches of other agents that the branch contains (git ancestry), by branch name */
  branchDeps: string[];
  handoff: boolean;
  /** the agent's branch from its meta (`worktreeBranch`); absent: the worktree list's branch */
  branch?: string | null;
  signals?: SigFacts | null;
  wtId?: string | null;
}
export interface RawCi { id: number; workflow: string; branch: string; status: string; conclusion: string | null; startedAt: number; endedAt: number | null }
export interface RawPs { pid: number; ppid: number; ageMs: number; comm: string }
export interface Raw {
  now: number; session: number; agents: RawAgent[];
  /** the session's Bash process trees (Snapshot.system.procs), `agent` = owner */
  procs: Proc[]; ps: RawPs[];
  alive: (pid: number) => boolean; file: (path: string) => FileObs | null;
  /** the branch named by the live land lock (null: no lock, a dead holder, or no branch in it) */
  landLock?: string | null;
  /** the branches of the pending entries of the land queue (`.fw-console/land-queue.jsonl`) */
  landQueue?: string[];
  queuedText: string; ci: RawCi[]; board: Map<string, { id: string; done: boolean; agent: string | null; deps?: string[] }>;
  reapHeld?: HeldFact[];
  starts?: Map<number, number>;
}
const hasWord = (text: string, w: string) => text.split(/[^A-Za-z0-9._/-]+/).includes(w);

/** ppid, then its ppid, ... up to 1 (cycle-safe). */
export function chainOf(ps: RawPs[], pid: number): number[] {
  const by = new Map(ps.map((r) => [r.pid, r]));
  const chain: number[] = [];
  for (let c = by.get(pid)?.ppid; c !== undefined && chain.length < 64 && !chain.includes(c); c = by.get(c)?.ppid) {
    chain.push(c);
    if (c <= 1) break;
  }
  return chain;
}

/** What a watched file belongs to: `agent-<id>.jsonl` is an agent's transcript; `<id>.output` is the output of a
 *  known agent or else of a background task (null: neither). */
export function watchOf(file: string, agentIds: Set<string>): WatchFact | null {
  const a = /(?:^|\/)agent-([A-Za-z0-9]+)\.jsonl$/.exec(file);
  if (a) return { kind: "agent", id: a[1]! };
  const o = /(?:^|\/)([A-Za-z0-9]+)\.output$/.exec(file);
  return o ? { kind: agentIds.has(o[1]!) ? "agent" : "task", id: o[1]! } : null;
}

export function childrenOf(raw: Raw, agentId: string): ChildFact[] {
  const by = new Map(raw.ps.map((r) => [r.pid, r]));
  const agentIds = new Set(raw.agents.map((a) => a.id));
  // a Bash background process the agent's signals match to a stdin-reading command
  const stdin = new Set((raw.agents.find((a) => a.id === agentId)?.signals?.procs ?? []).filter((q) => q.kind === "stdin").map((q) => q.pid));
  const out: ChildFact[] = [];
  for (const q of raw.procs) {
    if (q.agent !== agentId) continue;
    const root = by.get(q.pid);
    if (!root) continue; // already ended
    const cl = classifyTree(root.comm, q.pids.map((p) => by.get(p)?.comm ?? ""));
    const f = cl.watchedFile ? raw.file(cl.watchedFile) : null;
    const w = cl.watchedFile ? watchOf(cl.watchedFile, agentIds) : null;
    const st = raw.starts?.get(q.pid);
    const base = { pid: q.pid, ...(st === undefined ? {} : { start: st }), chain: chainOf(raw.ps, q.pid), startedAt: startFromAge(raw.now, root.ageMs),
      watchedAt: f ? Math.floor(f.mtimeMs) : null, producerExited: f ? producerExitedLine(f.lastLine) : false, ...(w ? { watch: w } : {}) };
    const kind = cl.kind !== "ciWait" && stdin.has(q.pid) ? "stdinWait" : cl.kind;
    out.push(kind === "ciWait" ? { ...base, kind: "ciWait", run: cl.run!, timeoutMin: cl.timeoutMin! } : { ...base, kind });
  }
  return out;
}

// ---- signal facts (pure given the observations) ----
/** The text a live process's command line must contain to be the process of a Bash command: its first non-empty
 *  line up to the first quote (the shell wrapper re-quotes the command), at least 6 characters (null: too short). */
export function commandNeedle(cmd: string): string | null {
  const line = cmd.split("\n").map((l) => l.trim()).find((l) => l !== "") ?? "";
  const s = line.split(/['"]/)[0]!.trim();
  return s.length >= 6 ? s : null;
}
/** The process of a Bash command under the session: the topmost process whose command line holds the command's
 *  needle and whose ancestors include `session` (0: any) (null: none alive). */
export function procOfCommand(ps: RawPs[], session: number, cmd: string): number | null {
  const needle = commandNeedle(cmd);
  if (!needle) return null;
  const rows = ps.filter((r) => r.comm.includes(needle) && (session === 0 || chainOf(ps, r.pid).includes(session)));
  const pids = new Set(rows.map((r) => r.pid));
  return rows.find((r) => !pids.has(r.ppid))?.pid ?? null;
}
/** An agent's signal facts: its transcript's signals plus the lead's notes, the end marker of each pending id's
 *  output file (time: the file's mtime), the live process of each pending Bash id (matched by command text) and
 *  the meta.finished time (recorded only; the rule never reads it). */
export function signalFactsOf(ts: TranscriptSignals, notes: LeadNote[], file: (path: string) => FileObs | null,
  ps: RawPs[], session: number, metaFinishedAt: number | null): SigFacts {
  const f = withLeadNotes(ts.facts, notes);
  const ends = [...f.ends];
  const ended = new Set(ends.map((e) => e.id));
  for (const l of f.launched) {
    const out = ts.outputs.get(l.id);
    const o = !ended.has(l.id) && out ? file(out) : null;
    const mk = o ? markerOf(o.lastLine) : null;
    if (o && mk) { ends.push({ id: l.id, time: Math.floor(o.mtimeMs), ...mk }); ended.add(l.id); }
  }
  const procs: SigFacts["procs"] = [];
  for (const l of f.launched) {
    const cmd = ts.commands.get(l.id);
    const pid = !ended.has(l.id) && cmd ? procOfCommand(ps, session, cmd) : null;
    if (pid !== null && cmd) procs.push({ id: l.id, pid, kind: procKindOf(cmd) });
  }
  return { ...f, ends, procs, metaFinished: metaFinishedAt === null ? [] : [Math.floor(metaFinishedAt)] };
}

const rowOf = (r: { id: string; done: boolean; agent: string | null } | undefined) => r ? { id: r.id, done: r.done, agent: r.agent } : null;

export function buildFacts(raw: Raw): AgentFacts[] {
  return raw.agents.map((a) => {
    const task = a.name ?? a.task ?? a.id;
    const w = a.worktree;
    const ci = raw.ci.filter((r) => r.branch === `ci/${task}`).sort((x, y) => y.startedAt - x.startedAt)[0] ?? null;
    const br = a.branch ?? w?.branch ?? null;
    return {
      id: task, task, state: a.state, session: raw.session, handbackAt: a.handbackAt,
      // the branch may be gone from git after `fw land` (ahead/landed null): a land commit on main still makes it a fact
      branch: br && ((a.ahead !== null && a.landed !== null) || a.onMain)
        ? {
          name: br, ahead: a.ahead ?? 0, landed: a.landed ?? false, queued: hasWord(raw.queuedText, br),
          mergesClean: a.mergesClean ?? true, onMain: a.onMain === true, landLock: raw.landLock ?? null, landQueued: (raw.landQueue ?? []).includes(br),
          deps: [...a.branchDeps, ...(raw.board.get(task)?.deps ?? []).filter((d) => raw.board.get(d)?.done === false)],
        } : null,
      worktree: w ? { lockPid: w.lockPid, lockAlive: w.lockPid !== null && raw.alive(w.lockPid), id: a.wtId ?? null } : null,
      ctxTokens: a.ctxTokens ?? 0, children: childrenOf(raw, a.id),
      ci: ci && { ...ci },
      board: a.name ? rowOf(raw.board.get(a.name)) : null,
      handoff: a.handoff,
      ...(a.signals ? { signals: a.signals } : {}),
      reapHeld: raw.reapHeld ?? [],
    };
  });
}

// ---- output (pure) ----
/** `NEXT <agent> <action> k=v ...`, one line per action; agents with no action print nothing. */
export function formatNext(reply: NextReply): string[] {
  const lines: string[] = [];
  for (const a of reply.agents ?? []) for (const x of a.actions) {
    const { action, ...args } = x;
    if (action === "none") continue; // fwcore's "nothing to do" marker
    lines.push(["NEXT", a.id, action, ...Object.entries(args).map(([k, v]) => `${k}=${v}`)].join(" "));
  }
  return lines;
}
/** `NEXT investigate step=<tool/step>` for each slow step of fwcore's `obs.slow` (the lead turns it into an
 *  investigate + improve + prove task). */
export const slowNextLines = (slow: string[]): string[] => slow.map((s) => `NEXT investigate step=${s}`);
export const slowAlerts = (slow: string[], details: string[] = []): { code: string; subject: string; detail: string }[] =>
  slow.map((s, i) => ({ code: "timing.slow", subject: s, detail: (details[i] ? details[i] + "; " : "latest sample is slow (Fw.Obs.Timing verdict); ") + "NEXT investigate step=" + s }));

export function nextAlerts(reply: NextReply): { code: string; subject: string; detail: string }[] {
  const out: { code: string; subject: string; detail: string }[] = [];
  for (const a of reply.agents ?? []) for (const x of a.actions) {
    if (x.action === "land" || x.action === "routeIntegrator")
      out.push({ code: "agent.unlanded", subject: a.id, detail: `${x.action} branch=${x.branch}: handed back, branch not on main` });
  }
  return out;
}

// ---- observation (I/O) ----
const exec = (cmd: string, args: string[], cwd?: string, timeout = Number(process.env.FW_EXEC_TIMEOUT_MS) || 5000): Promise<string | null> =>
  new Promise((res) => {
    try { execFile(cmd, args, { cwd, timeout, maxBuffer: 8_000_000 }, (err, out) => res(err ? null : String(out))); } catch { res(null); }
  });

/** Time of the last SubagentHandback tool call in a transcript (null: none). */
export function handbackAtOf(jsonl: string): number | null {
  let at: number | null = null;
  for (const line of jsonl.split("\n")) {
    if (!line.includes("SubagentHandback")) continue;
    try {
      const o = JSON.parse(line);
      const t = Date.parse(o.timestamp);
      if (o.type === "assistant" && Array.isArray(o.message?.content) && Number.isFinite(t)
        && o.message.content.some((c: any) => c?.type === "tool_use" && typeof c.name === "string" && c.name.endsWith("SubagentHandback"))) at = Math.max(at ?? 0, t);
    } catch { /* partial line */ }
  }
  return at;
}

export function statFile(path: string): FileObs | null {
  try {
    const fd = openSync(path, "r");
    try {
      const st = fstatSync(fd), n = Math.min(st.size, 2048);
      const buf = Buffer.alloc(n);
      readSync(fd, buf, 0, n, st.size - n);
      const lines = buf.toString("utf8").split("\n").filter((l) => l.trim());
      return { mtimeMs: st.mtimeMs, lastLine: lines[lines.length - 1] ?? "" };
    } finally { closeSync(fd); }
  } catch { return null; }
}
export function pidAlive(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; }
}
/** Every process with its full command line (unlike the snapshot's `comm`-only table). */
export async function psCommands(): Promise<RawPs[]> {
  return parsePs(await exec("ps", ["-A", "-o", "pid=,ppid=,etime=,command="]));
}

/** The claude process of this session: the lock pid of the agents' worktrees, else the nearest `claude` ancestor. */
export function sessionPid(ps: RawPs[], self: number, lockPids: number[]): number {
  const by = new Map(ps.map((r) => [r.pid, r]));
  for (const p of lockPids) if (by.has(p) && exe(by.get(p)!.comm) === "claude") return p;
  let cur = by.get(self);
  for (let i = 0; cur && i < 64; i++, cur = by.get(cur.ppid)) if (exe(cur.comm) === "claude") return cur.pid;
  return lockPids[0] ?? 0;
}

const INTEGRATOR_LIST = "docs/team/handoffs/integrate-ports.md";

/** (commits ahead of main, ancestor of main) of a branch; [null, null] when git cannot say. Cached per collection. */
async function branchState(p: Paths, branch: string, cache: Map<string, [number | null, boolean | null]>): Promise<[number | null, boolean | null]> {
  const hit = cache.get(branch);
  if (hit) return hit;
  const n = await exec("git", ["rev-list", "--count", `main..${branch}`], p.root);
  const anc = (await exec("git", ["merge-base", "--is-ancestor", branch, "main"], p.root)) !== null;
  const r: [number | null, boolean | null] = n !== null ? [Number(n.trim()), anc] : [null, null];
  cache.set(branch, r);
  return r;
}

/** Whether a land commit for `task` is on main: a commit whose message has the line `Task: <task>` (what `fw land`
 *  writes). Read from main's history, never from the branch's existence (`fw land` deletes the branch). */
export async function landCommitOnMain(p: Paths, task: string): Promise<boolean> {
  const esc = task.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const out = await exec("git", ["log", "main", "-n", "1", "--format=%H", "--extended-regexp", `--grep=^Task: ${esc}$`], p.root);
  return out !== null && out.trim() !== "";
}

/** The branch named by the live land lock (`<git common dir>/fw-land.lock`); null: no lock, holder dead, unreadable. */
export function liveLandLockBranch(root: string): string | null {
  try {
    const f = lockFacts(lockFile(root));
    return f.lock && f.alive && typeof f.lock.branch === "string" ? f.lock.branch : null;
  } catch { return null; }
}

export function reapHeldFacts(pass: ReapPass | null): HeldFact[] {
  return pass === null ? [] : pass.held.map((h) => ({ pid: h.pid, start: h.start, wt: h.wt }));
}

export async function collectRaw(p: Paths, main: string, snap: Snapshot, health: { agents: { id: string; state: string }[] }, plan: unknown, reap: ReapPass | null = null): Promise<Raw> {
  const [wtOut, ps] = await Promise.all([exec("git", ["worktree", "list", "--porcelain"], p.root), psCommands()]);
  const wts = parseWorktrees(wtOut);
  const states = new Map(health.agents.map((a) => [a.id, a.state]));
  const tfs = findTranscripts(p);
  const agents: RawAgent[] = [];
  const seenTf = new Set<string>();
  const cache = new Map<string, [number | null, boolean | null]>();
  const session = sessionPid(ps, process.pid, wts.flatMap((w) => (w.lockPid ? [w.lockPid] : [])));
  const repo = repoIdOf(main);
  for (const a of snap.agents) {
    const state = states.get(a.id);
    if (!state) continue;
    const tf = tfs.get(a.id);
    const meta = tf ? readMeta(tf) : null;
    const metaBranch = typeof meta?.worktreeBranch === "string" && meta.worktreeBranch !== "" ? meta.worktreeBranch : null;
    const wt = (metaBranch ? wts.find((w) => w.branch === metaBranch) : undefined) ?? worktreeOf(wts, a.id, a.name);
    let ahead: number | null = null, landed: boolean | null = null;
    let mergesClean: boolean | null = null;
    const branchDeps: string[] = [];
    const branch = metaBranch ?? wt?.branch ?? null;
    let onMain: boolean | null = null;
    if (branch) {
      [ahead, landed] = await branchState(p, branch, cache);
      if (landed !== true) onMain = await landCommitOnMain(p, a.name ?? a.task ?? a.id);
      if (ahead !== null && ahead > 0 && landed === false) {
        mergesClean = (await exec("git", ["merge-tree", "--write-tree", "main", branch], p.root)) !== null;
        for (const o of wts) {
          if (!o.branch || o.branch === branch || o.branch === "main") continue;
          const [oa, ol] = await branchState(p, o.branch, cache);
          if (oa === null || oa === 0 || ol !== false) continue;
          if ((await exec("git", ["merge-base", "--is-ancestor", o.branch, branch], p.root)) !== null) branchDeps.push(o.branch);
        }
      }
    }
    const nm = a.name ?? a.task ?? a.id;
    const handoff = [p.root, main, ...(wt ? [wt.path] : [])].some((r) => existsSync(join(r, "docs/team/handoffs", `${nm}.md`)));
    let handbackAt: number | null = null, signals: SigFacts | null = null;
    if (tf) {
      try {
        const t = transcriptTail.read(tf);
        seenTf.add(tf);
        handbackAt = t.hb;
        const mt = meta?.finished === true ? metaMtime(tf) : null;
        signals = signalFactsOf(finishSignals(a.id, t.st), readLeadNotes(p, leadFileOf(tf)), statFile, ps, session, mt);
      } catch { /* unreadable */ }
    }
    agents.push({ id: a.id, name: a.name, task: a.task, state, ctxTokens: a.ctxTokens, handbackAt, worktree: wt, ahead, landed, onMain, mergesClean,
      branchDeps, handoff, branch, signals, wtId: wt && repo ? wtIdOf(wt.path, repo) : null });
  }
  transcriptTail.prune(seenTf);
  const board = new Map<string, { id: string; done: boolean; agent: string | null; deps?: string[] }>();
  const tasks = (plan as { tasks?: unknown } | null)?.tasks;
  for (const t of Array.isArray(tasks) ? (tasks as any[]) : []) {
    if (typeof t?.id === "string") board.set(t.id, {
      id: t.id, done: t.state === "done", agent: typeof t.agent === "string" ? t.agent : null,
      deps: Array.isArray(t.deps) ? t.deps.filter((d: unknown): d is string => typeof d === "string") : [],
    });
  }
  let queuedText = "";
  for (const root of [p.root, main]) {
    const f = join(root, INTEGRATOR_LIST);
    if (existsSync(f)) { try { queuedText = readFileSync(f, "utf8"); break; } catch { /* next */ } }
  }
  const ci: RawCi[] = (snap.system.ci as (Snapshot["system"]["ci"][number] & { id?: number })[])
    .filter((r) => typeof r.id === "number")
    .map((r) => ({ id: r.id!, workflow: r.workflow, branch: r.branch, status: r.status, conclusion: r.conclusion, startedAt: r.startedAt, endedAt: r.endedAt ?? null }));
  return {
    now: snap.now, session, agents,
    procs: snap.system.procs ?? [], ps, alive: pidAlive, file: statFile, queuedText, ci, board,
    landLock: liveLandLockBranch(p.root),
    landQueue: [...new Set([...queuedBranches(join(main, ".fw-console")), ...queuedBranches(p.consoleDir)])],
    reapHeld: reapHeldFacts(reap), starts: reap?.starts,
  };
}

/** The plan (GET /api/plan) for the board facts; null when console-api is not reachable. */
export async function fetchPlan(p: Paths, env: NodeJS.ProcessEnv = process.env): Promise<unknown> {
  let base = env.FW_API ?? null;
  if (!base) { try { base = `http://127.0.0.1:${JSON.parse(readFileSync(join(p.consoleDir, "api.json"), "utf8")).port}`; } catch { return null; } }
  try { const r = await fetch(`${base}/api/plan`, { signal: AbortSignal.timeout(3000) }); return r.ok ? await r.json() : null; } catch { return null; }
}

export async function collectFacts(p: Paths, main: string, snap: Snapshot, health: { agents: { id: string; state: string }[] }, reap: ReapPass | null = heldPass(main)): Promise<AgentFacts[]> {
  return buildFacts(await collectRaw(p, main, snap, health, await fetchPlan(p), reap));
}
