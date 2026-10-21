// fw reap (tasks orphan-guard, reap-auto-stop): lists (--list) or stops (--stop) the leftover processes Lean selects
// (ops.lspReap / ops.reapPlan / ops.reapKill / ops.reapVerify, lean/Fw/Ops/Reap.lean, goldens
// packages/contracts/golden/ops/{lspreap,reap}.jsonl). This file gathers facts, sends the signals Lean names and prints;
// every decision (who, group or pid, who survives the grace, who is KILLed) is Lean's.
import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, readlinkSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { consoleDirOf } from "./lib.ts";
import { fwcoreCall } from "./run.ts";

export const REAP_USAGE = "usage: fw reap --list   (prints the processes Lean selects: pid, group flag, kind, reason; signals none)\n       fw reap --stop   (TERM the selected, wait the grace, KILL the unchanged survivors, verify; prints what stopped)";

export type ReapRow = { pid: number; ppid: number; pgid: number; start: number; cwd: number | null; kind: string; wt?: string | null };
export type Selected = { pid: number; start: number; kind: string; group: boolean; reason: string };
export type Target = { pid: number; start: number; group: boolean };
export type Call = (req: Record<string, unknown>) => Record<string, unknown>;
export type Facts = {
  rows: ReapRow[]; live: number[]; mcps: { pid: number; cwd: number | null }[]; keep: { pid: number; at: number }[];
  liveIds?: string[]; protect?: number[];
};

/** The argv kind the Lean op expects: `lspServe` (a `lake serve`), `console` (console-api main), `tool` (lean, lake,
 *  fwcore, node, a playwright browser: selected only through a removed worktree or a dead ancestor, never by this name),
 *  else `other`. */
export function classify(args: string): "lspServe" | "console" | "tool" | "other" {
  const w = args.trim().split(/\s+/);
  const base = w[0]?.split("/").pop() ?? "";
  if (base === "lake" && w[1] === "serve") return "lspServe";
  if (/(^|\/)node$/.test(w[0] ?? "") && w.some((x) => /apps\/console-api\/src\/main\.ts$/.test(x))) return "console";
  if (["lean", "lake", "fwcore", "node", "esbuild"].includes(base)) return "tool";
  if (/\/ms-playwright\//.test(args.split(" --")[0] ?? "")) return "tool";
  return "other";
}

/** A process of the lean-lsp-mcp server (its launcher or the Python it runs): the parents a `lake serve` may have. */
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

/** The worktree id `.claude/worktrees/<id>` of `base` that `path` lies in, or `null`. */
export function wtIdOf(path: string, base: string): string | null {
  const pre = join(base, ".claude", "worktrees") + "/";
  if (!path.startsWith(pre)) return null;
  const id = path.slice(pre.length).split("/")[0];
  return id ? id : null;
}

/** The ids of the worktrees under `base/.claude/worktrees` that are live: registered with git, or present on disk with a
 *  `.git` entry (a checkout being made or not yet pruned counts as live: the conservative side). */
export function liveWtIds(base: string, dirs: string[]): string[] {
  const ids = new Set<string>();
  for (const d of dirs) { const id = wtIdOf(d + "/", base); if (id) ids.add(id); }
  const root = join(base, ".claude", "worktrees");
  try {
    for (const e of readdirSync(root)) if (existsSync(join(root, e, ".git"))) ids.add(e);
  } catch { /* no worktrees directory */ }
  return [...ids];
}

/** The recorded consoles: pid and the second `startedAt` of api.json in the main checkout's `.fw-console` and in
 *  `FW_CONSOLE_DIR` when set. A missing or broken file records none. */
export function recordedConsoles(top: string, env: Record<string, string | undefined> = process.env): { pid: number; at: number }[] {
  const out: { pid: number; at: number }[] = [];
  const dirs = [consoleDirOf({}, top), ...(env.FW_CONSOLE_DIR ? [env.FW_CONSOLE_DIR] : [])];
  for (const d of dirs) {
    try {
      const j = JSON.parse(readFileSync(join(d, "api.json"), "utf8")) as { pid?: unknown; startedAt?: unknown };
      if (typeof j.pid === "number" && typeof j.startedAt === "number") out.push({ pid: j.pid, at: secs(j.startedAt) });
    } catch { /* none recorded */ }
  }
  return out;
}

/** Live checkout directories: the worktree list of `top` that exist (the main checkout first); `null` when git fails. */
export function liveDirs(top: string): string[] | null {
  const r = spawnSync("git", ["worktree", "list", "--porcelain"], { cwd: top, encoding: "utf8" });
  if (r.status !== 0) return null;
  return r.stdout.split("\n").filter((l) => l.startsWith("worktree ")).map((l) => l.slice(9)).filter((d) => existsSync(d));
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
 *  Accepted limit: inodes are not paired with st_dev; a collision across devices can only add a live inode (a kept row). */
export function gather(top: string): Facts | null {
  const t = psRows();
  const dirs = liveDirs(top);
  if (t === null || dirs === null || dirs.length === 0) return null;
  const base = dirs[0]!;
  const cand = t.rows.filter((r) => r.kind !== "other");
  const mcpPs = t.ps.filter((p) => isMcp(p.args));
  const cwd = readCwds([...cand, ...mcpPs].map((p) => p.pid));
  if (cwd === null) return null;
  const live = new Set(liveRoots(dirs));
  const liveIds = liveWtIds(base, dirs);
  // a directory under <main>/.claude/worktrees/<id> is inside a live checkout only when <id> is live (the main checkout contains them all)
  const isLive = (c: Cwd) => { const id = wtIdOf(c.path, base); return (id === null || liveIds.includes(id)) && insideLive(c, dirs); };
  for (const c of cwd.values()) if (isLive(c)) live.add(c.ino);
  return {
    rows: t.rows.map((r) => {
      const c = cwd.get(r.pid);
      return r.kind === "other" ? r : { ...r, cwd: c?.ino ?? null, wt: c ? wtIdOf(c.path, base) : null };
    }),
    live: [...live],
    mcps: mcpPs.map((p) => ({ pid: p.pid, cwd: cwd.get(p.pid)?.ino ?? null })),
    keep: recordedConsoles(top),
    liveIds,
    protect: selfChain(t.ps),
  };
}

const request = (op: string, f: Facts) => ({ op, rows: f.rows, live: f.live, mcps: f.mcps, keep: f.keep, liveIds: f.liveIds ?? [], protect: f.protect ?? [] });

/** Lean's list for these facts. */
export function select(f: Facts, call: Call): Selected[] {
  return (call(request("ops.lspReap", f)) as { selected: Selected[] }).selected;
}

/** One printed line per selected process. */
export function render(sel: Selected[]): string[] {
  return sel.map((s) => `${s.pid} ${s.group ? "group" : "pid"} ${s.kind}: ${s.reason}`);
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
};

/** Block the thread for `ms` (the stopper is a short sequential tool, not a server). */
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
};

export type StopResult = {
  selected: Selected[]; termed: Target[]; killed: Target[]; left: Target[]; freedKb: number;
  /** per kind: the pids that are gone and their RSS (KiB) */
  byKind: { kind: string; pids: number[]; freedKb: number }[];
};

const EMPTY: StopResult = { selected: [], termed: [], killed: [], left: [], freedKb: 0, byKind: [] };

/** Stop what Lean selects, following its script: read (done by `gatherFn`), TERM the plan, wait the grace (leaving early once
 *  Lean's verify finds none left), read again, KILL Lean's survivors of unchanged (pid, start), wait, verify. `null` when the
 *  facts cannot be read. */
export function stopSelected(top: string, call: Call, io: Io = realIo, gatherFn: (top: string) => Facts | null = gather): StopResult | null {
  const f = gatherFn(top);
  if (f === null) return null;
  const plan = call(request("ops.reapPlan", f)) as { selected: Selected[]; targets: Target[]; graceMs: number; killWaitMs: number };
  if (plan.targets.length === 0) return { ...EMPTY };
  const planned = plan.targets;
  const rss0 = io.rss(planned.map((t) => t.pid));
  for (const t of planned) io.signal(t, "SIGTERM");
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
    killed = (call({ op: "ops.reapKill", planned, rows: fresh }) as { kill: Target[] }).kill;
    for (const t of killed) io.signal(t, "SIGKILL");
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
  return { selected: plan.selected, termed: planned, killed, left: still, freedKb, byKind: [...byKind].map(([kind, e]) => ({ kind, ...e })) };
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
  if (r.left.length) out.push(`still running after KILL: ${r.left.map((t) => t.pid).join(",")}`);
  return out;
}

/** The lines the land report adds after a worktree removal: stop the leftovers gracefully and say what happened. Never throws. */
export function reapStopLines(top: string, call: Call = fwcoreCall(top), io: Io = realIo, gatherFn: (top: string) => Facts | null = gather): string[] {
  try {
    const r = stopSelected(top, call, io, gatherFn);
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
  gatherFn: (top: string) => Facts | null = gather, io: Io = realIo): number {
  if (argv.length !== 1 || (argv[0] !== "--list" && argv[0] !== "--stop")) throw new ReapUsage(REAP_USAGE);
  if (argv[0] === "--stop") {
    const r = stopSelected(top, call, io, gatherFn);
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
  for (const l of render(sel)) print(l);
  if (sel.length === 0) print("reap: nothing leftover");
  return 0;
}

/** One watch tick: stop what Lean selects and return the lines to print (`REAP stopped <kind> ...`), recording each kind in
 *  `reap.jsonl`. `FW_WATCH_REAP=0` turns it off. Never throws: a failed read or stop is a quiet tick. */
export function reapTick(top: string, env: Record<string, string | undefined> = process.env, io: Io = realIo,
  gatherFn: (top: string) => Facts | null = gather, call: () => Call = () => fwcoreCall(top)): string[] {
  if (env.FW_WATCH_REAP === "0") return [];
  try {
    const r = stopSelected(top, call(), io, gatherFn);
    if (r === null || r.byKind.length === 0) return [];
    recordStopped(top, r, Date.now(), env);
    return r.byKind.map((k) => `REAP stopped ${k.kind} ${k.pids.length} process(es) [${k.pids.join(",")}] freed ${(k.freedKb / 1024).toFixed(1)} MiB${r.left.length ? `; still running: ${r.left.map((t) => t.pid).join(",")}` : ""}`);
  } catch {
    return [];
  }
}

export class ReapUsage extends Error {}
