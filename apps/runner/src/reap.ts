// fw reap (tasks orphan-guard, reap-auto-stop): lists (--list) or stops (--stop) the leftover processes Lean selects
// (ops.lspReap / ops.reapPlan / ops.reapKill / ops.reapVerify / ops.reapIdle, lean/Fw/Ops/Reap.lean, goldens
// packages/contracts/golden/ops/{lspreap,reap,reap-idle}.jsonl). This file gathers facts, sends the signals Lean names and
// prints; every decision (who, group or pid, who survives the grace, who is KILLed, which CPU baselines to keep) is Lean's.
import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, readlinkSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { consoleDirOf } from "./lib.ts";
import { fwcoreCall } from "./run.ts";
import { simctlShutdown } from "./slot.ts";

export const REAP_USAGE = "usage: fw reap --list   (prints the processes Lean selects: pid, group flag, kind, reason, MB of an idle lean-lsp-mcp stack; stores CPU baselines in reap-idle.json; signals none)\n       fw reap --stop   (TERM the selected, wait the grace, KILL the unchanged survivors, verify; prints what stopped)";

export type ReapRow = {
  pid: number; ppid: number; pgid: number; start: number; cwd: number | null; kind: string; wt?: string | null; inRepo?: boolean;
  cpu?: number | null;
};
export type LoopFact = { pid: number; start: number; awaits: string; callLive: boolean };
export type Waiter = { pid: number; start: number; wt: string; writes: string };
export type Selected = { pid: number; start: number; kind: string; group: boolean; reason: string };
export type Target = { pid: number; start: number; group: boolean };
export type Call = (req: Record<string, unknown>) => Record<string, unknown>;
/** A CPU baseline (ops.reapIdle): identity, the second it was set, the CPU time then (centiseconds). */
export type Base = { pid: number; start: number; since: number; cpu: number };
/** A worktree lock: the worktree id and the pid its reason names (null: none named). */
export type Lock = { id: string; holder: number | null };
export type Facts = {
  rows: ReapRow[]; live: number[]; mcps: { pid: number; cwd: number | null; wt?: string | null }[]; keep: { pid: number; at: number }[];
  liveIds?: string[]; protect?: number[];
  now?: number; bases?: Base[]; locks?: Lock[];
  loops?: LoopFact[]; waiters?: Waiter[]; simIdleSince?: number | null; simAcquired?: number | null; simHolders?: number;
  ownSims?: { pid: number; start: number }[];
  idleFile?: string;
};

/** A serena process (the MCP server, its Python, its language servers under `~/.serena`): never selected, nor anything
 *  below it. */
export const isSerena = (args: string): boolean => /(^|[\s/])serena(\s|$)/.test(args) || /\/\.serena\//.test(args);

export function classify(args: string): "serena" | "lspServe" | "console" | "tool" | "untilLoop" | "simDevice" | "other" {
  const w = args.trim().split(/\s+/);
  const base = w[0]?.split("/").pop() ?? "";
  if (isSerena(args)) return "serena";
  if (["zsh", "bash", "sh"].includes(base) && awaitedPath(args) !== null) return "untilLoop";
  if (base === "launchd_sim" && simUdidOf(args) !== null) return "simDevice";
  if (base === "lake" && w[1] === "serve") return "lspServe";
  if (/(^|\/)node$/.test(w[0] ?? "") && w.some((x) => /apps\/console-api\/src\/main\.ts$/.test(x))) return "console";
  if (["lean", "lake", "fwcore", "node", "esbuild"].includes(base)) return "tool";
  if (/\/ms-playwright\//.test(args.split(" --")[0] ?? "")) return "tool";
  return "other";
}

export function awaitedPath(args: string): string | null {
  const m = /\buntil\s+\[\s+-[sfe]\s+["']?([^\s"'\]]+)["']?\s+\]/.exec(args);
  return m ? m[1]! : null;
}

export function simUdidOf(args: string): string | null {
  const m = /CoreSimulator\/Devices\/([0-9A-Fa-f-]{36})\//.exec(args);
  return m ? m[1]!.toUpperCase() : null;
}

export const isCiWait = (args: string): boolean => /(^|[\s/])fw(\.mjs|\.ts)?\s+ci\s+wait(\s|$)/.test(args) || /\bfw\b.*\bci\s+wait(\s|$)/.test(args);

export function parseLsofOut(out: string): Map<number, string> {
  const m = new Map<number, string>();
  let pid = -1;
  for (const l of out.split("\n")) {
    if (l.startsWith("p")) pid = Number(l.slice(1));
    else if (l.startsWith("n/") && !l.startsWith("n/dev/") && pid >= 0 && !m.has(pid)) m.set(pid, l.slice(1));
  }
  return m;
}

export function ownSimUdids(): Set<string> | null {
  const r = spawnSync("xcrun", ["simctl", "list", "devices", "-j"], { encoding: "utf8", maxBuffer: 1 << 26, timeout: 10_000 });
  if (r.error || r.status !== 0) return null;
  try {
    const j = JSON.parse(r.stdout) as { devices?: Record<string, { udid: string; name: string }[]> };
    return new Set(Object.values(j.devices ?? {}).flat().filter((d) => d.name.startsWith("fw-")).map((d) => d.udid.toUpperCase()));
  } catch { return null; }
}

export function simSlotFacts(dir: string, now: number): { simIdleSince: number | null; simAcquired: number | null; simHolders: number } {
  try {
    const st = JSON.parse(readFileSync(join(dir, "state.json"), "utf8")) as { simIdleSince?: number; simAcquired?: number; holders?: { kind: string; till: number }[] };
    return {
      simIdleSince: st.simIdleSince ? st.simIdleSince : null, simAcquired: st.simAcquired ? st.simAcquired : null,
      simHolders: (st.holders ?? []).filter((h) => h.kind === "sim" && now < h.till).length,
    };
  } catch { return { simIdleSince: null, simAcquired: null, simHolders: 0 }; }
}

export function canonPath(p: string): string {
  try { return join(realpathSync(dirname(p)), basename(p)); } catch { return p; }
}

export const isMcp = (args: string): boolean => /(^|[\s/])lean-lsp-mcp(\s|$)/.test(args);

const secs = (ms: number) => Math.floor(ms / 1000);

type Ps = { pid: number; ppid: number; pgid: number; start: number; args: string };

/** `ps` rows (LC_ALL=C start times: "Tue Oct 20 02:59:44 2026"), with an optional `stat` column before them (a zombie row
 *  is dropped: it is already dead); a line that does not parse is skipped. */
export function parsePs(out: string): Ps[] {
  const rows: Ps[] = [];
  for (const l of out.split("\n")) {
    const m = /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(?:(?!(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s)(\S+)\s+)?(\S+\s+\S+\s+\d+\s+\d+:\d+:\d+\s+\d+)\s+(.*)$/.exec(l);
    if (!m) continue;
    if (m[4]?.startsWith("Z")) continue;
    const ms = Date.parse(m[5]!);
    if (Number.isFinite(ms)) rows.push({ pid: +m[1]!, ppid: +m[2]!, pgid: +m[3]!, start: secs(ms), args: m[6]! });
  }
  return rows;
}

export type Cwd = { ino: number; path: string };

/** `lsof -Fpni` output to pid -> cwd (inode and path). */
export function parseLsof(out: string): Map<number, Cwd> {
  const m = new Map<number, Cwd>();
  let pid = -1, ino = -1, path = "";
  const flush = () => { if (pid >= 0 && ino >= 0) m.set(pid, { ino, path }); };
  for (const l of out.split("\n")) {
    if (l.startsWith("p")) { flush(); pid = Number(l.slice(1)); ino = -1; path = ""; }
    else if (l.startsWith("i") && pid >= 0) ino = Number(l.slice(1));
    else if (l.startsWith("n") && pid >= 0) path = l.slice(1);
  }
  flush();
  return m;
}

/** The cwd (inode and path) of each pid: `/proc` on Linux, `lsof` elsewhere; `null` when the tool fails. A pid that is
 *  gone or unreadable has no entry. */
export function readCwds(pids: number[]): Map<number, Cwd> | null {
  const out = new Map<number, Cwd>();
  if (pids.length === 0) return out;
  if (existsSync("/proc/self/cwd")) {
    for (const p of pids) {
      try {
        out.set(p, { ino: statSync(`/proc/${p}/cwd`).ino, path: readlinkSync(`/proc/${p}/cwd`).replace(/ \(deleted\)$/, "") });
      } catch { /* gone, or not ours to read */ }
    }
    return out;
  }
  for (let i = 0; i < pids.length; i += 400) {
    const l = spawnSync("lsof", ["-a", "-d", "cwd", "-Fpni", "-p", pids.slice(i, i + 400).join(",")], { encoding: "utf8", maxBuffer: 1 << 26 });
    if (l.error || (l.status !== 0 && l.status !== 1)) return null; // 1: some pid already gone
    for (const [k, v] of parseLsof(l.stdout ?? "")) out.set(k, v);
  }
  return out;
}

/** The inode of each live checkout's root directory. */
export function liveRoots(dirs: string[]): number[] {
  const out: number[] = [];
  for (const d of dirs) { try { out.push(statSync(d).ino); } catch { /* removed meanwhile */ } }
  return [...new Set(out)];
}

/** Whether `c` is a directory inside a live checkout: its path is under the checkout and `stat` of that path gives the
 *  inode the cwd read reports (a removed directory, or a path reused by a new one, fails the inode test). */
export function insideLive(c: Cwd, dirs: string[]): boolean {
  if (!dirs.some((d) => c.path === d || c.path.startsWith(d.endsWith("/") ? d : d + "/"))) return false;
  try { return statSync(c.path).ino === c.ino; } catch { return false; }
}

/** A directory's identity: device and inode. */
export type Ident = { dev: number; ino: number };
/** This repo, by identity: its root directory and its `.claude/worktrees` directory (`null` when it does not exist). */
export type RepoId = { root: Ident; wts: Ident | null };

const identOf = (p: string): Ident | null => { try { const st = statSync(p); return { dev: st.dev, ino: st.ino }; } catch { return null; } };
const sameIdent = (a: Ident, b: Ident) => a.dev === b.dev && a.ino === b.ino;

/** The identity of the repo whose main checkout is `base`; `null` when the root cannot be read. */
export function repoIdOf(base: string): RepoId | null {
  const root = identOf(base);
  return root === null ? null : { root, wts: identOf(join(base, ".claude", "worktrees")) };
}

/** Whether a cwd path lies inside THIS repo, decided by identity and never by comparing path strings: some ancestor of the
 *  path (an ancestor that no longer exists is skipped) is the repo root by (dev, inode); `wt` is the name of the directory
 *  right below the ancestor that is this repo's `.claude/worktrees` directory by (dev, inode). A path of another repo, even
 *  one at a path this repo once had, matches neither. */
export function membership(path: string, id: RepoId): { inRepo: boolean; wt: string | null } {
  let cur = path, child: string | null = null, wt: string | null = null;
  for (let n = 0; n < 4096; n++) {
    const here = identOf(cur);
    if (here !== null && id.wts !== null && sameIdent(here, id.wts)) wt = child;
    if (here !== null && sameIdent(here, id.root)) return { inRepo: true, wt };
    const up = dirname(cur);
    if (up === cur) break;
    child = basename(cur);
    cur = up;
  }
  return { inRepo: false, wt: null };
}

/** The worktree id `.claude/worktrees/<id>` that `path` lies in, by identity, or `null`. */
export const wtIdOf = (path: string, id: RepoId): string | null => membership(path, id).wt;

/** The ids of the worktrees under `base/.claude/worktrees` that are live: registered with git, or present on disk with a
 *  `.git` entry (a checkout being made or not yet pruned counts as live: the conservative side). */
export function liveWtIds(base: string, dirs: string[], repo: RepoId): string[] {
  const ids = new Set<string>();
  for (const d of dirs) { const id = wtIdOf(d, repo); if (id) ids.add(id); }
  const root = join(base, ".claude", "worktrees");
  try {
    for (const e of readdirSync(root)) if (existsSync(join(root, e, ".git"))) ids.add(e);
  } catch { /* no worktrees directory */ }
  return [...ids];
}

/** The console directory of the checkout this code runs from: the real console is recorded there whatever `top` is, so a stop
 *  run against another repo still protects it. `null` when git cannot say. */
export function selfConsoleDir(): string | null {
  try { return consoleDirOf({}, dirname(fileURLToPath(import.meta.url))); } catch { return null; }
}

/** The recorded consoles: pid and the second `startedAt` of api.json in the main checkout's `.fw-console` and in
 *  `FW_CONSOLE_DIR` when set. A missing or broken file records none. */
export function recordedConsoles(top: string, env: Record<string, string | undefined> = process.env): { pid: number; at: number }[] {
  const out: { pid: number; at: number }[] = [];
  const dirs = [consoleDirOf({}, top), selfConsoleDir(), ...(env.FW_CONSOLE_DIR ? [env.FW_CONSOLE_DIR] : [])].filter((d): d is string => d !== null);
  for (const d of dirs) {
    try {
      const j = JSON.parse(readFileSync(join(d, "api.json"), "utf8")) as { pid?: unknown; startedAt?: unknown };
      if (typeof j.pid === "number" && typeof j.startedAt === "number") out.push({ pid: j.pid, at: secs(j.startedAt) });
    } catch { /* none recorded */ }
  }
  return out;
}

/** `git worktree list --porcelain` of `top`; `null` when git fails. */
export function worktreeList(top: string): string | null {
  const r = spawnSync("git", ["worktree", "list", "--porcelain"], { cwd: top, encoding: "utf8" });
  return r.status === 0 ? r.stdout : null;
}

/** The worktree directories of a porcelain list that exist (the main checkout first). */
export const dirsOf = (porcelain: string): string[] =>
  porcelain.split("\n").filter((l) => l.startsWith("worktree ")).map((l) => l.slice(9)).filter((d) => existsSync(d));

/** Live checkout directories: the worktree list of `top` that exist (the main checkout first); `null` when git fails. */
export function liveDirs(top: string): string[] | null {
  const p = worktreeList(top);
  return p === null ? null : dirsOf(p);
}

/** The locked worktrees of a porcelain list: the id (by `idOf` of the worktree path; a path with no id is skipped) and the
 *  pid the lock reason names (`(pid P ...`), `null` when it names none. */
export function parseLocks(porcelain: string, idOf: (path: string) => string | null): Lock[] {
  const out: Lock[] = [];
  let path: string | null = null;
  for (const l of porcelain.split("\n")) {
    if (l.startsWith("worktree ")) path = l.slice(9);
    else if (path !== null && (l === "locked" || l.startsWith("locked "))) {
      const id = idOf(path);
      const m = /\(pid (\d+)/.exec(l);
      if (id !== null) out.push({ id, holder: m ? +m[1]! : null });
    }
  }
  return out;
}

/** A `ps` `time` value (`[dd-][hh:]mm:ss[.cc]`) in centiseconds; `null` when it does not parse. */
export function parseCpuTime(s: string): number | null {
  const m = /^(?:(\d+)-)?(\d+(?::\d+){0,2})(?:\.(\d{1,2}))?$/.exec(s.trim());
  if (!m) return null;
  const secs = m[2]!.split(":").reduce((a, x) => a * 60 + Number(x), 0) + Number(m[1] ?? 0) * 86400;
  return secs * 100 + Number((m[3] ?? "0").padEnd(2, "0"));
}

/** CPU time per pid in centiseconds (`ps -axo pid=,time=`); `null` when `ps` fails. */
export function cpuTable(): Map<number, number> | null {
  const r = spawnSync("ps", ["-axo", "pid=,time="], { encoding: "utf8", env: { ...process.env, LC_ALL: "C" }, maxBuffer: 1 << 26 });
  if (r.status !== 0) return null;
  const m = new Map<number, number>();
  for (const l of r.stdout.split("\n")) {
    const x = /^\s*(\d+)\s+(\S+)\s*$/.exec(l);
    const c = x ? parseCpuTime(x[2]!) : null;
    if (x && c !== null) m.set(+x[1]!, c);
  }
  return m;
}

/** The baselines stored by the previous run; none when the file is missing or broken. */
export function loadBases(file: string): Base[] {
  try {
    const j = JSON.parse(readFileSync(file, "utf8")) as { bases?: unknown };
    return Array.isArray(j.bases) ? (j.bases as Base[]).filter((b) => [b.pid, b.start, b.since, b.cpu].every(Number.isInteger)) : [];
  } catch { return []; }
}

const PS_ARGS = ["-axo", "pid=,ppid=,pgid=,stat=,lstart=,args="];
const psEnv = { ...process.env, LC_ALL: "C" };

/** The whole process table: every row, kind from the argv, no cwd. `null` when `ps` fails. */
export function psRows(): { ps: Ps[]; rows: ReapRow[] } | null {
  const ps = spawnSync("ps", PS_ARGS, { encoding: "utf8", env: psEnv, maxBuffer: 1 << 26 });
  if (ps.status !== 0) return null;
  const all = parsePs(ps.stdout);
  return { ps: all, rows: all.map((p) => ({ pid: p.pid, ppid: p.ppid, pgid: p.pgid, start: p.start, cwd: null, kind: classify(p.args) })) };
}

/** The pids of this process and its ancestors: the stopper must never stop itself or the shell above it. */
export function selfChain(all: Ps[], me = process.pid): number[] {
  const by = new Map(all.map((p) => [p.pid, p]));
  const out: number[] = [];
  for (let p = me, n = 0; p > 1 && n < 64 && !out.includes(p); n++) { out.push(p); const r = by.get(p); if (!r) break; p = r.ppid; }
  return out;
}

/** The facts of one run; `null` when `ps`, the cwd read or git fails (the caller prints that, not a wrong list). Rows are the
 *  whole process table (Lean walks the parent chains through them); the live inodes are this repo's checkout roots plus the
 *  cwd inode of every candidate that sits inside one (nested Lean projects).
 *  Branch D's facts: the CPU time of every row (unread when the second `ps` fails), each lean-lsp-mcp's worktree id, the
 *  worktree locks, `now` and the baselines of `reap-idle.json` in the console directory.
 *  Accepted limit: inodes are not paired with st_dev; a collision across devices can only add a live inode (a kept row). */
export function gather(top: string, env: Record<string, string | undefined> = process.env): Facts | null {
  const t = psRows();
  const porcelain = worktreeList(top);
  if (t === null || porcelain === null) return null;
  const dirs = dirsOf(porcelain);
  if (dirs.length === 0) return null;
  const base = dirs[0]!;
  const repo = repoIdOf(base);
  if (repo === null) return null;
  const cpu = cpuTable();
  const own = t.rows.some((r) => r.kind === "simDevice") ? ownSimUdids() : null;
  const argsOf = new Map(t.ps.map((p) => [p.pid, p.args]));
  const ownSims = t.rows.filter((r) => r.kind === "simDevice" && own?.has(simUdidOf(argsOf.get(r.pid) ?? "") ?? "")).map((r) => ({ pid: r.pid, start: r.start }));
  const cand = t.rows.filter((r) => r.kind !== "other" && r.kind !== "serena");
  const mcpPs = t.ps.filter((p) => isMcp(p.args));
  const waitPs = t.ps.filter((p) => isCiWait(p.args));
  const cwd = readCwds([...cand, ...mcpPs, ...waitPs].map((p) => p.pid));
  if (cwd === null) return null;
  const live = new Set(liveRoots(dirs));
  const liveIds = liveWtIds(base, dirs, repo);
  const where = new Map<number, { inRepo: boolean; wt: string | null }>();
  for (const [pid, c] of cwd) where.set(pid, membership(c.path, repo));
  // a directory under <main>/.claude/worktrees/<id> is inside a live checkout only when <id> is live (the main checkout contains them all)
  const isLive = (pid: number, c: Cwd) => { const id = where.get(pid)?.wt ?? null; return (id === null || liveIds.includes(id)) && insideLive(c, dirs); };
  for (const [pid, c] of cwd) if (isLive(pid, c)) live.add(c.ino);
  const idleFile = join(consoleDirOf(env, top), "reap-idle.json");
  const out = waitPs.length ? spawnSync("lsof", ["-a", "-d", "1,2", "-Fpn", "-p", waitPs.map((p) => p.pid).join(",")], { encoding: "utf8", maxBuffer: 1 << 24 }) : null;
  const writes = parseLsofOut(out?.stdout ?? "");
  const waiters: Waiter[] = [];
  for (const p of waitPs) {
    const wt = where.get(p.pid)?.wt ?? null, w = writes.get(p.pid);
    if (wt !== null && w !== undefined) waiters.push({ pid: p.pid, start: p.start, wt, writes: canonPath(w) });
  }
  const loops: LoopFact[] = [];
  for (const r of cand) {
    const a = r.kind === "untilLoop" ? awaitedPath(argsOf.get(r.pid) ?? "") : null;
    if (a !== null) loops.push({ pid: r.pid, start: r.start, awaits: canonPath(a), callLive: r.ppid > 1 });
  }
  const now = secs(Date.now());
  const sim = simSlotFacts(env.FW_SLOT_DIR ?? join(consoleDirOf(env, top), "slot"), now);
  return {
    rows: t.rows.map((r) => {
      const c = cwd.get(r.pid);
      const m = where.get(r.pid);
      const used = { cpu: cpu?.get(r.pid) ?? null };
      return r.kind === "other" || r.kind === "serena" ? { ...r, ...used } : { ...r, cwd: c?.ino ?? null, wt: m?.wt ?? null, inRepo: m?.inRepo ?? false, ...used };
    }),
    live: [...live],
    mcps: mcpPs.map((p) => ({ pid: p.pid, cwd: cwd.get(p.pid)?.ino ?? null, wt: where.get(p.pid)?.wt ?? null })),
    keep: recordedConsoles(top),
    liveIds,
    protect: selfChain(t.ps),
    now,
    loops, waiters, ownSims, ...sim,
    bases: loadBases(idleFile),
    locks: parseLocks(porcelain, (p) => wtIdOf(p, repo)),
    idleFile,
  };
}

const request = (op: string, f: Facts) => ({
  op, rows: f.rows, live: f.live, mcps: f.mcps, keep: f.keep, liveIds: f.liveIds ?? [], protect: f.protect ?? [],
  now: f.now ?? 0, bases: f.bases ?? [], locks: f.locks ?? [], loops: f.loops ?? [], waiters: f.waiters ?? [], simIdleSince: f.simIdleSince ?? null,
  simAcquired: f.simAcquired ?? null, ownSims: f.ownSims ?? [], simHolders: f.simHolders ?? 0,
});

export function heldLoops(f: Facts, call: Call): { pid: number; start: number; subject: string; reason: string }[] {
  const held = (call({ ...request("ops.reapHeld", f) }) as { held: Selected[] }).held;
  return held.map((h) => ({ pid: h.pid, start: h.start, subject: f.rows.find((r) => r.pid === h.pid)?.wt ?? `pid-${h.pid}`, reason: h.reason }));
}

export function saveIdle(f: Facts, call: Call): void {
  if (!f.idleFile) return;
  try {
    const bases = (call(request("ops.reapIdle", f)) as { bases: Base[] }).bases;
    mkdirSync(dirname(f.idleFile), { recursive: true });
    writeFileSync(f.idleFile, JSON.stringify({ at: f.now ?? 0, bases }) + "\n");
  } catch { /* advisory state */ }
}

/** Lean's list for these facts; the baselines for the next run are stored on the way. */
export function select(f: Facts, call: Call): Selected[] {
  const sel = (call(request("ops.lspReap", f)) as { selected: Selected[] }).selected;
  saveIdle(f, call);
  return sel;
}

const mb = (kb: number) => (kb / 1024).toFixed(1);

/** One printed line per selected process; with `rssKb`, a selected process of an idle lean-lsp-mcp stack also shows its RSS. */
export function render(sel: Selected[], rssKb?: Map<number, number>): string[] {
  return sel.map((s) => {
    const kb = s.kind === "mcpIdle" ? rssKb?.get(s.pid) : undefined;
    return `${s.pid} ${s.group ? "group" : "pid"} ${s.kind}: ${s.reason}${kb === undefined ? "" : ` (${mb(kb)} MB)`}`;
  });
}

/** The total line of the idle lean-lsp-mcp rows, none when there are none. */
export function idleTotal(sel: Selected[], rssKb: Map<number, number>): string[] {
  const idle = sel.filter((s) => s.kind === "mcpIdle");
  if (idle.length === 0) return [];
  return [`mcpIdle: ${idle.length} process(es), ${mb(idle.reduce((a, s) => a + (rssKb.get(s.pid) ?? 0), 0))} MB RSS`];
}

/** The advisory line when the list cannot be made (a failure must not look like "nothing leftover"). */
export const COULD_NOT_LIST = "leftover processes: could not list (pnpm -s fw reap --list)";

/** The lines the land report adds after a worktree removal: leftover processes, or nothing. Never throws. */
export function reapLines(top: string, call: Call = fwcoreCall(top), gatherFn: (top: string) => Facts | null = gather): string[] {
  try {
    const f = gatherFn(top);
    if (f === null) return [COULD_NOT_LIST];
    const sel = select(f, call);
    return sel.length ? [`leftover processes (not stopped; pnpm -s fw reap --list): ${sel.length}`, ...render(sel).map((l) => `  ${l}`)] : [];
  } catch {
    return [COULD_NOT_LIST];
  }
}

// ---- the stop ------------------------------------------------------------------------------------------------------------

/** The side effects of a stop, injectable. */
export type Io = {
  signal: (t: Target, sig: "SIGTERM" | "SIGKILL") => void;
  sleep: (ms: number) => void;
  table: () => ReapRow[] | null;
  rss: (pids: number[]) => Map<number, number>;
  simStop?: (t: Target) => void;
};

export const sleepSync = (ms: number) => { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); };

/** RSS in KiB per pid (`ps -o rss=`); pids that are gone are absent. */
export function rssOf(pids: number[]): Map<number, number> {
  const m = new Map<number, number>();
  if (pids.length === 0) return m;
  const r = spawnSync("ps", ["-o", "pid=,rss=", "-p", pids.join(",")], { encoding: "utf8" });
  for (const l of (r.stdout ?? "").split("\n")) { const x = /^\s*(\d+)\s+(\d+)/.exec(l); if (x) m.set(+x[1]!, +x[2]!); }
  return m;
}

/** The real side effects: `kill(2)` to the pid or, for a group target, to its process group. ESRCH (already gone) is fine. */
export const realIo: Io = {
  signal: (t, sig) => { try { process.kill(t.group ? -t.pid : t.pid, sig); } catch { /* gone, or not ours */ } },
  sleep: sleepSync,
  table: () => psRows()?.rows ?? null,
  rss: rssOf,
  simStop: (t) => {
    const r = spawnSync("ps", ["-o", "command=", "-p", String(t.pid)], { encoding: "utf8" });
    const u = r.status === 0 ? simUdidOf(r.stdout) : null;
    if (u !== null) simctlShutdown(u);
  },
};

export type StopResult = {
  selected: Selected[]; termed: Target[]; killed: Target[]; left: Target[]; freedKb: number;
  /** signals the scope guard refused (a pid outside the scope, pid <= 1, or a group with a member outside the scope) */
  refused: Target[];
  /** per kind: the pids that are gone and their RSS (KiB) */
  byKind: { kind: string; pids: number[]; freedKb: number }[];
};

const EMPTY: StopResult = { selected: [], termed: [], killed: [], left: [], freedKb: 0, refused: [], byKind: [] };

/** Stop what Lean selects, following its script: read (done by `gatherFn`), read again and let Lean re-check each identity
 *  (`ops.reapTerm`), TERM, wait the grace (leaving early once Lean's verify finds none left), read again, KILL Lean's survivors
 *  of unchanged (pid, start), wait, verify. Every signal first passes Lean's `ops.reapGuard` against `scope`, the pids this run
 *  may signal: production passes none and the scope is the pids Lean selected; a test passes only the pids it started. A
 *  signal outside the scope is refused and listed in `refused`. `null` when the facts cannot be read. */
export function stopSelected(top: string, call: Call, io: Io = realIo, gatherFn: (top: string) => Facts | null = gather,
  scope?: number[]): StopResult | null {
  const f = gatherFn(top);
  if (f === null) return null;
  const plan = call(request("ops.reapPlan", f)) as { selected: Selected[]; targets: Target[]; graceMs: number; killWaitMs: number };
  saveIdle(f, call);
  if (plan.targets.length === 0) return { ...EMPTY };
  const planned = plan.targets;
  const allowed = scope ?? plan.selected.map((s) => s.pid);
  const refused: Target[] = [];
  const isSim = (t: Target) => plan.selected.some((s) => s.pid === t.pid && s.start === t.start && s.kind === "simBooted");
  const send = (t: Target, sig: "SIGTERM" | "SIGKILL", table: ReapRow[]): boolean => {
    const ok = (call({ op: "ops.reapGuard", scope: allowed, rows: table, target: t }) as { allowed: boolean }).allowed;
    if (!ok) { refused.push(t); return false; }
    if (isSim(t)) {
      if (sig === "SIGKILL" || io.simStop === undefined) return false;
      io.simStop(t);
      return true;
    }
    io.signal(t, sig);
    return true;
  };
  const rss0 = io.rss(planned.map((t) => t.pid));
  const pre = io.table();
  if (pre === null) return null;
  const toTerm = (call({ op: "ops.reapTerm", planned, rows: pre }) as { term: Target[] }).term;
  const termed = toTerm.filter((t) => send(t, "SIGTERM", pre));
  const left = (): Target[] | null => {
    const rows = io.table();
    return rows === null ? null : (call({ op: "ops.reapVerify", planned, rows }) as { left: Target[] }).left;
  };
  for (let waited = 0; waited < plan.graceMs; waited += 100) {
    io.sleep(100);
    if (left()?.length === 0) break;
  }
  const fresh = io.table();
  let killed: Target[] = [];
  if (fresh !== null) {
    const toKill = (call({ op: "ops.reapKill", planned, rows: fresh }) as { kill: Target[] }).kill;
    killed = toKill.filter((t) => send(t, "SIGKILL", fresh));
    for (let waited = 0; killed.length > 0 && waited < plan.killWaitMs; waited += 100) {
      io.sleep(100);
      if (left()?.length === 0) break;
    }
  }
  const still = left() ?? planned;
  const gone = planned.filter((t) => !still.some((s) => s.pid === t.pid && s.start === t.start));
  const kindOf = (pid: number) => plan.selected.find((s) => s.pid === pid)?.kind ?? "unknown";
  const byKind = new Map<string, { pids: number[]; freedKb: number }>();
  for (const t of gone) {
    const k = kindOf(t.pid);
    const e = byKind.get(k) ?? { pids: [], freedKb: 0 };
    e.pids.push(t.pid); e.freedKb += rss0.get(t.pid) ?? 0;
    byKind.set(k, e);
  }
  const freedKb = [...byKind.values()].reduce((a, e) => a + e.freedKb, 0);
  return { selected: plan.selected, termed, killed, left: still, freedKb, refused, byKind: [...byKind].map(([kind, e]) => ({ kind, ...e })) };
}

/** Append one `reap.stopped` record per kind to `.fw-console/reap.jsonl` of the console directory (a derived-fact log like
 *  health.jsonl: the runner writes it, the console reads it; it is not the event log). Best effort. */
export function recordStopped(top: string, r: StopResult, now: number = Date.now(), env: Record<string, string | undefined> = process.env): void {
  if (r.byKind.length === 0) return;
  try {
    const p = join(consoleDirOf(env, top), "reap.jsonl");
    mkdirSync(dirname(p), { recursive: true });
    for (const k of r.byKind) appendFileSync(p, JSON.stringify({ type: "reap.stopped", at: now, kind: k.kind, pids: k.pids, freedKb: k.freedKb }) + "\n");
  } catch { /* the log is advisory */ }
}

/** One printed line per stopped kind, plus the survivors. */
export function renderStop(r: StopResult): string[] {
  const out = r.byKind.map((k) => `stopped ${k.kind}: ${k.pids.length} process(es) [${k.pids.join(",")}], freed ${(k.freedKb / 1024).toFixed(1)} MiB RSS`);
  if (r.killed.length) out.push(`killed after the grace: ${r.killed.map((t) => t.pid).join(",")}`);
  if (r.refused.length) out.push(`signal refused (outside the scope): ${r.refused.map((t) => t.pid).join(",")}`);
  if (r.left.length) out.push(`still running after KILL: ${r.left.map((t) => t.pid).join(",")}`);
  return out;
}

/** The lines the land report adds after a worktree removal: stop the leftovers gracefully and say what happened. Never throws. */
export function reapStopLines(top: string, call: Call = fwcoreCall(top), io: Io = realIo, gatherFn: (top: string) => Facts | null = gather,
  scope?: number[]): string[] {
  try {
    const r = stopSelected(top, call, io, gatherFn, scope);
    if (r === null) return [COULD_NOT_LIST];
    recordStopped(top, r);
    return r.selected.length === 0 ? [] : [`leftover processes stopped: ${r.byKind.reduce((a, k) => a + k.pids.length, 0)} of ${r.selected.length}`, ...renderStop(r).map((l) => `  ${l}`)];
  } catch {
    return [COULD_NOT_LIST];
  }
}

/** `fw reap --list` or `--stop`: print Lean's list, or stop it and print the result; exit 0 (1: facts unreadable, 2: a
 *  selected process survived KILL). */
export function reapCli(argv: string[], top: string, call: Call, print: (s: string) => void = console.log,
  gatherFn: (top: string) => Facts | null = gather, io: Io = realIo, scope?: number[]): number {
  if (argv.length !== 1 || (argv[0] !== "--list" && argv[0] !== "--stop")) throw new ReapUsage(REAP_USAGE);
  if (argv[0] === "--stop") {
    const r = stopSelected(top, call, io, gatherFn, scope);
    if (r === null) { print("reap: could not read the process table or the worktree list"); return 1; }
    recordStopped(top, r);
    if (r.selected.length === 0) { print("reap: nothing leftover"); return 0; }
    for (const l of render(r.selected)) print(l);
    for (const l of renderStop(r)) print(l);
    return r.left.length ? 2 : 0;
  }
  const f = gatherFn(top);
  if (f === null) { print("reap: could not read the process table or the worktree list"); return 1; }
  const sel = select(f, call);
  const rss = io.rss(sel.filter((s) => s.kind === "mcpIdle").map((s) => s.pid));
  for (const l of render(sel, rss)) print(l);
  for (const l of idleTotal(sel, rss)) print(l);
  if (sel.length === 0) print("reap: nothing leftover");
  return 0;
}

/** One watch tick: stop what Lean selects and return the lines to print (`REAP stopped <kind> ...`), recording each kind in
 *  `reap.jsonl`. `FW_WATCH_REAP=0` turns it off. Never throws: a failed read or stop is a quiet tick. */
export function reapTick(top: string, env: Record<string, string | undefined> = process.env, io: Io = realIo,
  gatherFn: (top: string) => Facts | null = gather, call: () => Call = () => fwcoreCall(top), scope?: number[]): string[] {
  if (env.FW_WATCH_REAP === "0") return [];
  try {
    const r = stopSelected(top, call(), io, gatherFn, scope);
    if (r === null || r.byKind.length === 0) return [];
    recordStopped(top, r, Date.now(), env);
    return r.byKind.map((k) => `REAP stopped ${k.kind} ${k.pids.length} process(es) [${k.pids.join(",")}] freed ${(k.freedKb / 1024).toFixed(1)} MiB${r.left.length ? `; still running: ${r.left.map((t) => t.pid).join(",")}` : ""}`);
  } catch {
    return [];
  }
}

export class ReapUsage extends Error {}
