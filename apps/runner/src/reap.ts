// fw reap (task orphan-guard): lists the leftover processes Lean selects (ops.lspReap, lean/Fw/Ops/Reap.lean, golden
// packages/contracts/golden/ops/lspreap.jsonl). This file gathers facts and prints; it signals no process.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { consoleDirOf } from "./lib.ts";
import { fwcoreCall } from "./run.ts";

export const REAP_USAGE = "usage: fw reap --list   (prints the processes Lean selects: pid, group flag, kind, reason; signals none)";

export type ReapRow = { pid: number; ppid: number; pgid: number; start: number; cwd: number | null; kind: string };
export type Selected = { pid: number; start: number; kind: string; group: boolean; reason: string };
export type Call = (req: Record<string, unknown>) => Record<string, unknown>;
export type Facts = { rows: ReapRow[]; live: number[]; mcps: { pid: number; cwd: number | null }[]; keep: { pid: number; at: number }[] };

/** The argv kind the Lean op expects: `lspServe` (a `lake serve`), `console` (console-api main), else `other`. */
export function classify(args: string): "lspServe" | "console" | "other" {
  const w = args.trim().split(/\s+/);
  if (w[0]?.split("/").pop() === "lake" && w[1] === "serve") return "lspServe";
  if (/(^|\/)node$/.test(w[0] ?? "") && w.some((x) => /apps\/console-api\/src\/main\.ts$/.test(x))) return "console";
  return "other";
}

/** A process of the lean-lsp-mcp server (its launcher or the Python it runs): the parents a `lake serve` may have. */
export const isMcp = (args: string): boolean => /(^|[\s/])lean-lsp-mcp(\s|$)/.test(args);

const secs = (ms: number) => Math.floor(ms / 1000);

type Ps = { pid: number; ppid: number; pgid: number; start: number; args: string };

/** `ps` rows (LC_ALL=C start times: "Tue Oct 20 02:59:44 2026"); a line that does not parse is skipped. */
export function parsePs(out: string): Ps[] {
  const rows: Ps[] = [];
  for (const l of out.split("\n")) {
    const m = /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\S+\s+\S+\s+\d+\s+\d+:\d+:\d+\s+\d+)\s+(.*)$/.exec(l);
    if (!m) continue;
    const ms = Date.parse(m[4]!);
    if (Number.isFinite(ms)) rows.push({ pid: +m[1]!, ppid: +m[2]!, pgid: +m[3]!, start: secs(ms), args: m[5]! });
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

/** The inode of each live checkout's root directory. */
export function liveRoots(dirs: string[]): number[] {
  const out: number[] = [];
  for (const d of dirs) { try { out.push(statSync(d).ino); } catch { /* removed meanwhile */ } }
  return [...new Set(out)];
}

/** Whether `c` is a directory inside a live checkout: its path is under the checkout and `stat` of that path gives the
 *  inode lsof reports (a removed directory, or a path reused by a new one, fails the inode test). */
export function insideLive(c: Cwd, dirs: string[]): boolean {
  if (!dirs.some((d) => c.path === d || c.path.startsWith(d.endsWith("/") ? d : d + "/"))) return false;
  try { return statSync(c.path).ino === c.ino; } catch { return false; }
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

/** Live checkout directories: `git worktree list` of `top` that exist; `null` when git fails. */
export function liveDirs(top: string): string[] | null {
  const r = spawnSync("git", ["worktree", "list", "--porcelain"], { cwd: top, encoding: "utf8" });
  if (r.status !== 0) return null;
  return r.stdout.split("\n").filter((l) => l.startsWith("worktree ")).map((l) => l.slice(9)).filter((d) => existsSync(d));
}

/** The facts of one run; `null` when `ps`, `lsof` or git fails (the caller prints that, not a wrong list). The live
 *  inodes are this repo's checkout roots plus the cwd inode of every candidate that sits inside one (nested Lean projects).
 *  Accepted limit: inodes are not paired with st_dev; a collision across devices can only add a live inode (a kept row). */
export function gather(top: string): Facts | null {
  const ps = spawnSync("ps", ["-axo", "pid=,ppid=,pgid=,lstart=,args="], { encoding: "utf8", env: { ...process.env, LC_ALL: "C" }, maxBuffer: 1 << 26 });
  const dirs = liveDirs(top);
  if (ps.status !== 0 || dirs === null) return null;
  const all = parsePs(ps.stdout);
  const cand = all.filter((p) => classify(p.args) !== "other");
  const mcpPs = all.filter((p) => isMcp(p.args));
  const pids = [...cand, ...mcpPs].map((p) => p.pid);
  let cwd = new Map<number, Cwd>();
  if (pids.length) {
    const l = spawnSync("lsof", ["-a", "-d", "cwd", "-Fpni", "-p", pids.join(",")], { encoding: "utf8", maxBuffer: 1 << 26 });
    if (l.error || (l.status !== 0 && l.status !== 1)) return null; // 1: some pid already gone
    cwd = parseLsof(l.stdout ?? "");
  }
  const live = new Set(liveRoots(dirs));
  for (const c of cwd.values()) if (insideLive(c, dirs)) live.add(c.ino);
  return {
    rows: cand.map((p) => ({ pid: p.pid, ppid: p.ppid, pgid: p.pgid, start: p.start, cwd: cwd.get(p.pid)?.ino ?? null, kind: classify(p.args) })),
    live: [...live],
    mcps: mcpPs.map((p) => ({ pid: p.pid, cwd: cwd.get(p.pid)?.ino ?? null })),
    keep: recordedConsoles(top),
  };
}

/** Lean's list for these facts. */
export function select(f: Facts, call: Call): Selected[] {
  return (call({ op: "ops.lspReap", rows: f.rows, live: f.live, mcps: f.mcps, keep: f.keep }) as { selected: Selected[] }).selected;
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

/** `fw reap --list`: print Lean's list; exit 0. */
export function reapCli(argv: string[], top: string, call: Call, print: (s: string) => void = console.log,
  gatherFn: (top: string) => Facts | null = gather): number {
  if (argv.length !== 1 || argv[0] !== "--list") throw new ReapUsage(REAP_USAGE);
  const f = gatherFn(top);
  if (f === null) { print("reap: could not read the process table or the worktree list"); return 1; }
  const sel = select(f, call);
  for (const l of render(sel)) print(l);
  if (sel.length === 0) print("reap: nothing leftover");
  return 0;
}

export class ReapUsage extends Error {}
