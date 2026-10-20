// fw reap (task orphan-guard): lists the leftover processes Lean selects (ops.lspReap, lean/Fw/Ops/Reap.lean, golden
// packages/contracts/golden/ops/lspreap.jsonl). This file gathers facts and prints; it signals no process.
import { spawnSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { fwcoreCall } from "./run.ts";

export const REAP_USAGE = "usage: fw reap --list   (prints the processes Lean selects: pid, group flag, kind, reason; signals none)";

export type ReapRow = { pid: number; ppid: number; pgid: number; start: number; cwd: number | null; kind: string };
export type Selected = { pid: number; start: number; kind: string; group: boolean; reason: string };
export type Call = (req: Record<string, unknown>) => Record<string, unknown>;
export type Facts = { rows: ReapRow[]; live: number[]; mcps: number[] };

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

/** `lsof -Fpni` output to pid -> cwd inode. */
export function parseLsof(out: string): Map<number, number> {
  const m = new Map<number, number>();
  let pid = -1;
  for (const l of out.split("\n")) {
    if (l.startsWith("p")) pid = Number(l.slice(1));
    else if (l.startsWith("i") && pid >= 0) m.set(pid, Number(l.slice(1)));
  }
  return m;
}

/** The inodes of what a live checkout's processes run in: its root, `lean/` and `apps/console-api/`. */
export function liveInodes(dirs: string[]): number[] {
  const out: number[] = [];
  for (const d of dirs) for (const sub of ["", "lean", join("apps", "console-api")]) {
    const p = join(d, sub);
    try { if (existsSync(p)) out.push(statSync(p).ino); } catch { /* removed meanwhile */ }
  }
  return [...new Set(out)];
}

/** Live checkout directories: `git worktree list` of `top` that exist; `null` when git fails. */
export function liveDirs(top: string): string[] | null {
  const r = spawnSync("git", ["worktree", "list", "--porcelain"], { cwd: top, encoding: "utf8" });
  if (r.status !== 0) return null;
  return r.stdout.split("\n").filter((l) => l.startsWith("worktree ")).map((l) => l.slice(9)).filter((d) => existsSync(d));
}

/** The facts of one run; `null` when `ps` or git fails (no list is better than a wrong one). */
export function gather(top: string): Facts | null {
  const ps = spawnSync("ps", ["-axo", "pid=,ppid=,pgid=,lstart=,args="], { encoding: "utf8", env: { ...process.env, LC_ALL: "C" }, maxBuffer: 1 << 26 });
  const dirs = liveDirs(top);
  if (ps.status !== 0 || dirs === null) return null;
  const all = parsePs(ps.stdout);
  const cand = all.filter((p) => classify(p.args) !== "other");
  const cwd = cand.length
    ? parseLsof(spawnSync("lsof", ["-a", "-d", "cwd", "-Fpni", "-p", cand.map((p) => p.pid).join(",")], { encoding: "utf8", maxBuffer: 1 << 26 }).stdout ?? "")
    : new Map<number, number>();
  return {
    rows: cand.map((p) => ({ pid: p.pid, ppid: p.ppid, pgid: p.pgid, start: p.start, cwd: cwd.get(p.pid) ?? null, kind: classify(p.args) })),
    live: liveInodes(dirs),
    mcps: all.filter((p) => isMcp(p.args)).map((p) => p.pid),
  };
}

/** Lean's list for these facts. */
export function select(f: Facts, call: Call): Selected[] {
  return (call({ op: "ops.lspReap", rows: f.rows, live: f.live, mcps: f.mcps }) as { selected: Selected[] }).selected;
}

/** One printed line per selected process. */
export function render(sel: Selected[]): string[] {
  return sel.map((s) => `${s.pid} ${s.group ? "group" : "pid"} ${s.kind}: ${s.reason}`);
}

/** The lines the land report adds after a worktree removal: leftover processes, or nothing. Never throws. */
export function reapLines(top: string, call: Call = fwcoreCall(top), gatherFn: (top: string) => Facts | null = gather): string[] {
  try {
    const f = gatherFn(top);
    if (f === null) return [];
    const sel = select(f, call);
    return sel.length ? [`leftover processes (not stopped; pnpm -s fw reap --list): ${sel.length}`, ...render(sel).map((l) => `  ${l}`)] : [];
  } catch {
    return [];
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
