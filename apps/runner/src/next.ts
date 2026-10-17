// `fw next` / the NEXT lines of `fw watch`: glue for the fwcore op `obs.next` (lean/Fw/Obs/Next.lean, wire in
// lean/Fw/Wire/Obs.lean, golden packages/contracts/golden/obs/next.jsonl). This file only OBSERVES facts (git, ps,
// transcripts, stat, the plan) and PRINTS fwcore's answer. No decision is made here: which action an agent needs,
// whether a loop is orphaned or a branch must be landed is the Lean `next`. The only judgement below is how to read
// a command line into a child kind (what the process is), which is classification of an observation, not a rule.
// Privacy: command lines are read to classify and to find the watched file; none is kept or printed.
import { execFile } from "node:child_process";
import { closeSync, existsSync, fstatSync, openSync, readFileSync, readSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { exe, findTranscripts, parsePs, type Paths, type Proc, type Snapshot } from "./watch-collect.ts";

// ---- the facts (wire shape of AgentFacts) ----
export type ChildFact = {
  pid: number; chain: number[]; startedAt: number; watchedAt: number | null; producerExited: boolean;
} & ({ kind: "sleepLoop" | "build" | "other" } | { kind: "ciWait"; run: number; timeoutMin: number });
export interface AgentFacts {
  id: string; task: string; state: string; session: number; handbackAt: number | null;
  branch: { name: string; ahead: number; landed: boolean; queued: boolean; mergesClean: boolean; deps: string[] } | null;
  /** docs/team/handoffs/<name>.md exists */
  handoff: boolean;
  worktree: { lockPid: number | null; lockAlive: boolean } | null;
  ctxTokens: number; children: ChildFact[];
  ci: { id: number; workflow: string; branch: string; status: string; conclusion: string | null; startedAt: number; endedAt: number | null } | null;
  board: { id: string; done: boolean; agent: string | null } | null;
}
export interface NextAction { action: string; [k: string]: unknown }
export interface NextReply { agents?: { id: string; actions: NextAction[] }[] }

// ---- classification of one process tree (pure) ----
/** `waitrun.sh <run> [timeoutMin]` (default 10 min) or `fw ci wait <run> [--timeout <min>]` in a command line. */
const CI_WAIT = /waitrun\.sh\s+(\d+)(?:\s+(\d+))?|\bci\s+wait\s+(\d+)(?:.*?--timeout\s+(\d+))?/;
/** An open poll loop: `until … ; do sleep N` or `while … ; do … sleep`. */
const SLEEP_LOOP = /\b(?:until|while)\b[^|]*;\s*do\b[^]*\bsleep\b/;
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
/** The exit marker a finished Bash task leaves as the last line of its output file. */
export const producerExitedLine = (lastLine: string) => /^\[exited with code -?\d+\]\s*$/.test(lastLine.trim());

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
  /** `git merge-tree --write-tree main <branch>` exited 0 (null: not checked: no unlanded branch) */
  mergesClean: boolean | null;
  /** unlanded branches of other agents that the branch contains (git ancestry), by branch name */
  branchDeps: string[];
  handoff: boolean;
}
export interface RawCi { id: number; workflow: string; branch: string; status: string; conclusion: string | null; startedAt: number; endedAt: number | null }
export interface RawPs { pid: number; ppid: number; ageMs: number; comm: string }
export interface Raw {
  now: number; session: number; agents: RawAgent[];
  /** the session's Bash process trees (Snapshot.system.procs), `agent` = owner */
  procs: Proc[]; ps: RawPs[];
  alive: (pid: number) => boolean; file: (path: string) => FileObs | null;
  /** text of the integrator's list (a branch name in it means queued) */
  queuedText: string; ci: RawCi[]; board: Map<string, { id: string; done: boolean; agent: string | null; deps?: string[] }>;
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

export function childrenOf(raw: Raw, agentId: string): ChildFact[] {
  const by = new Map(raw.ps.map((r) => [r.pid, r]));
  const out: ChildFact[] = [];
  for (const q of raw.procs) {
    if (q.agent !== agentId) continue;
    const root = by.get(q.pid);
    if (!root) continue; // already ended
    const cl = classifyTree(root.comm, q.pids.map((p) => by.get(p)?.comm ?? ""));
    const f = cl.watchedFile ? raw.file(cl.watchedFile) : null;
    const base = { pid: q.pid, chain: chainOf(raw.ps, q.pid), startedAt: Math.floor(raw.now - root.ageMs),
      watchedAt: f ? Math.floor(f.mtimeMs) : null, producerExited: f ? producerExitedLine(f.lastLine) : false };
    out.push(cl.kind === "ciWait" ? { ...base, kind: "ciWait", run: cl.run!, timeoutMin: cl.timeoutMin! } : { ...base, kind: cl.kind });
  }
  return out;
}

const rowOf = (r: { id: string; done: boolean; agent: string | null } | undefined) => r ? { id: r.id, done: r.done, agent: r.agent } : null;

export function buildFacts(raw: Raw): AgentFacts[] {
  return raw.agents.map((a) => {
    const task = a.name ?? a.task ?? a.id;
    const w = a.worktree;
    const ci = raw.ci.filter((r) => r.branch === `ci/${task}`).sort((x, y) => y.startedAt - x.startedAt)[0] ?? null;
    return {
      id: task, task, state: a.state, session: raw.session, handbackAt: a.handbackAt,
      branch: w?.branch && a.ahead !== null && a.landed !== null
        ? {
          name: w.branch, ahead: a.ahead, landed: a.landed, queued: hasWord(raw.queuedText, w.branch),
          mergesClean: a.mergesClean ?? true,
          // observed dependencies: contained unlanded agent branches, then the task's board dependencies not done
          deps: [...a.branchDeps, ...(raw.board.get(task)?.deps ?? []).filter((d) => raw.board.get(d)?.done === false)],
        } : null,
      worktree: w ? { lockPid: w.lockPid, lockAlive: w.lockPid !== null && raw.alive(w.lockPid) } : null,
      ctxTokens: a.ctxTokens ?? 0, children: childrenOf(raw, a.id),
      ci: ci && { ...ci },
      board: a.name ? rowOf(raw.board.get(a.name)) : null,
      handoff: a.handoff,
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
/** Alerts for `fw watch`: a kill proposal = agent.held, a land/route proposal = agent.unlanded (subject = agent id). */
export function nextAlerts(reply: NextReply): { code: string; subject: string; detail: string }[] {
  const out: { code: string; subject: string; detail: string }[] = [];
  for (const a of reply.agents ?? []) for (const x of a.actions) {
    if (x.action === "killOrphan") out.push({ code: "agent.held", subject: a.id, detail: `killOrphan pid=${x.pid}: its own wait loop keeps it held` });
    else if (x.action === "land" || x.action === "routeIntegrator")
      out.push({ code: "agent.unlanded", subject: a.id, detail: `${x.action} branch=${x.branch}: handed back, branch not on main` });
  }
  return out;
}

// ---- observation (I/O) ----
const exec = (cmd: string, args: string[], cwd?: string, timeout = 5000): Promise<string | null> =>
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
  return parsePs(await exec("ps", ["-A", "-o", "pid=,ppid=,etime=,command="], undefined, 3000));
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

/** Collect every observation for the snapshot's agents. `health` = the obs.health reply for the same snapshot. */
export async function collectRaw(p: Paths, main: string, snap: Snapshot, health: { agents: { id: string; state: string }[] }, plan: unknown): Promise<Raw> {
  const [wtOut, ps] = await Promise.all([exec("git", ["worktree", "list", "--porcelain"], p.root), psCommands()]);
  const wts = parseWorktrees(wtOut);
  const states = new Map(health.agents.map((a) => [a.id, a.state]));
  const tfs = findTranscripts(p);
  const agents: RawAgent[] = [];
  const cache = new Map<string, [number | null, boolean | null]>();
  for (const a of snap.agents) {
    const state = states.get(a.id);
    if (!state) continue;
    const wt = worktreeOf(wts, a.id, a.name);
    let ahead: number | null = null, landed: boolean | null = null;
    let mergesClean: boolean | null = null;
    const branchDeps: string[] = [];
    if (wt?.branch) {
      [ahead, landed] = await branchState(p, wt.branch, cache);
      if (ahead !== null && ahead > 0 && landed === false) {
        mergesClean = (await exec("git", ["merge-tree", "--write-tree", "main", wt.branch], p.root)) !== null;
        for (const o of wts) {
          if (!o.branch || o.branch === wt.branch || o.branch === "main") continue;
          const [oa, ol] = await branchState(p, o.branch, cache);
          if (oa === null || oa === 0 || ol !== false) continue;
          if ((await exec("git", ["merge-base", "--is-ancestor", o.branch, wt.branch], p.root)) !== null) branchDeps.push(o.branch);
        }
      }
    }
    const nm = a.name ?? a.task ?? a.id;
    const handoff = [p.root, main, ...(wt ? [wt.path] : [])].some((r) => existsSync(join(r, "docs/team/handoffs", `${nm}.md`)));
    let handbackAt: number | null = null;
    const tf = tfs.get(a.id);
    if (tf) { try { handbackAt = handbackAtOf(readFileSync(tf, "utf8")); } catch { /* unreadable */ } }
    agents.push({ id: a.id, name: a.name, task: a.task, state, ctxTokens: a.ctxTokens, handbackAt, worktree: wt, ahead, landed, mergesClean, branchDeps, handoff });
  }
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
    now: snap.now, session: sessionPid(ps, process.pid, wts.flatMap((w) => (w.lockPid ? [w.lockPid] : []))), agents,
    procs: snap.system.procs ?? [], ps, alive: pidAlive, file: statFile, queuedText, ci, board,
  };
}

/** The plan (GET /api/plan) for the board facts; null when console-api is not reachable. */
export async function fetchPlan(p: Paths, env: NodeJS.ProcessEnv = process.env): Promise<unknown> {
  let base = env.FW_API ?? null;
  if (!base) { try { base = `http://127.0.0.1:${JSON.parse(readFileSync(join(p.consoleDir, "api.json"), "utf8")).port}`; } catch { return null; } }
  try { const r = await fetch(`${base}/api/plan`, { signal: AbortSignal.timeout(3000) }); return r.ok ? await r.json() : null; } catch { return null; }
}

/** Facts for all agents of a snapshot, ready for the `obs.next` request. */
export async function collectFacts(p: Paths, main: string, snap: Snapshot, health: { agents: { id: string; state: string }[] }): Promise<AgentFacts[]> {
  return buildFacts(await collectRaw(p, main, snap, health, await fetchPlan(p)));
}
