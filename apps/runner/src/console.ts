// `fw console start|stop|restart|status|logs`: run console-api as a background process with no terminal.
// I/O glue only. What may happen comes from Lean (`console.daemon`: `Fw.Console.Daemon`): start only when no console is
// verified, stop only the verified pid, rotate the log at its limit, and the log admits no secret-bearing line kind.
// A console is verified when the pid in .fw-console/api.json answers GET /api/health on the recorded port with the same
// pid in `x-fw-console-pid`. The child's stdout and stderr are appended to .fw-console/console.log; stdin is /dev/null.
import { spawn } from "node:child_process";
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, renameSync, statSync, watchFile, unwatchFile, readSync, fstatSync } from "node:fs";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { UsageError, consoleDirOf } from "./lib.ts";
import type { FwCall } from "./run.ts";

export const CONSOLE_USAGE = "usage: fw console start [--lan] [--port N] | stop | restart [--lan] [--port N] | status | logs [-n N] [-f]";
export const DEFAULT_PORT = 8787;

type Info = { port: number; pid: number; lan?: boolean; startedAt?: number };
export type ConsoleDeps = {
  call: FwCall;
  env: Record<string, string | undefined>;
  cwd: string;
  out: (l: string) => void;
  err: (l: string) => void;
  now: () => number;
};

const MAIN = new URL("../../console-api/src/main.ts", import.meta.url).pathname;
const API_DIR = new URL("../../console-api/", import.meta.url).pathname;

function readInfo(dir: string): Info | null {
  try {
    const j = JSON.parse(readFileSync(join(dir, "api.json"), "utf8")) as Partial<Info>;
    return typeof j.port === "number" && typeof j.pid === "number" ? { port: j.port, pid: j.pid, ...(j.lan !== undefined ? { lan: j.lan } : {}), ...(j.startedAt !== undefined ? { startedAt: j.startedAt } : {}) } : null;
  } catch { return null; }
}

/** The pid the console on `port` reports, or null when nothing answers; a busy console gets three tries of 3 s. */
async function answeredPid(port: number): Promise<number | null> {
  for (let i = 0; i < 3; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/api/health`, { signal: AbortSignal.timeout(3000) });
      const h = res.headers.get("x-fw-console-pid");
      return h === null ? null : Number(h);
    } catch { /* no answer: try again */ }
  }
  return null;
}

const alive = (pid: number): boolean => { try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; } };

/** The console api.json names, with what it answered; Lean decides which pid counts as verified. */
async function probe(dir: string, call: FwCall): Promise<{ info: Info | null; verified: number | null; recorded: number | null; answered: number | null }> {
  const info = readInfo(dir);
  const answered = info ? await answeredPid(info.port) : null;
  const req = { op: "console.daemon", kind: "start", ...(info ? { recorded: info.pid } : {}), ...(answered !== null && Number.isFinite(answered) ? { answered } : {}) };
  const r = call(req);
  return { info, verified: typeof r.verified === "number" ? r.verified : null, recorded: info?.pid ?? null, answered };
}

function logTail(path: string, n: number): string[] {
  if (!existsSync(path)) return [];
  const lines = readFileSync(path, "utf8").split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  return lines.slice(-n);
}

const fmtDur = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return s >= 3600 ? `${Math.floor(s / 3600)}h${Math.floor((s % 3600) / 60)}m` : s >= 60 ? `${Math.floor(s / 60)}m${s % 60}s` : `${s}s`;
};

function parseFlags(args: string[]): { lan: boolean; port: number } {
  let lan = false; let port = DEFAULT_PORT;
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === "--lan") lan = true;
    else if (a === "--port") { const v = Number(args[++i]); if (!Number.isInteger(v) || v < 1 || v > 65534) throw new UsageError(CONSOLE_USAGE); port = v; }
    else throw new UsageError(CONSOLE_USAGE);
  }
  return { lan, port };
}

async function previewsOf(port: number): Promise<{ count: number; previewPort: number | null } | null> {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/api/previews`, { signal: AbortSignal.timeout(2000) });
    const j = (await res.json()) as { previews?: unknown[]; previewPort?: number | null };
    return { count: Array.isArray(j.previews) ? j.previews.length : 0, previewPort: j.previewPort ?? null };
  } catch { return null; }
}

export async function startConsole(d: ConsoleDeps, args: string[]): Promise<number> {
  const { lan, port } = parseFlags(args);
  const dir = consoleDirOf(d.env, d.cwd);
  const p = await probe(dir, d.call);
  const gate = d.call({ op: "console.daemon", kind: "start", ...(p.recorded !== null ? { recorded: p.recorded } : {}), ...(p.answered !== null ? { answered: p.answered } : {}) });
  if (gate.allow !== true) {
    d.err(`refused: a console is already running (pid ${String(gate.verified)}, port ${p.info?.port ?? "?"}); use: pnpm fw console restart`);
    return 1;
  }
  mkdirSync(dir, { recursive: true });
  const log = join(dir, "console.log");
  if (existsSync(log) && (d.call({ op: "console.daemon", kind: "rotate", size: statSync(log).size }).rotate === true)) renameSync(log, `${log}.1`);
  const fd = openSync(log, "a", 0o600);
  const env: Record<string, string | undefined> = { ...d.env, PORT: String(port), FW_CONSOLE_DIR: dir };
  if (lan) env.FW_CONSOLE_LAN = "1"; else delete env.FW_CONSOLE_LAN;
  let exited: number | string | null = null;
  const child = spawn(process.execPath, [MAIN], { cwd: API_DIR, detached: true, stdio: ["ignore", fd, fd], env: env as NodeJS.ProcessEnv });
  closeSync(fd);
  child.once("exit", (c, s) => { exited = c ?? s ?? "unknown"; });
  child.once("error", (e) => { exited = e.message; });
  const pid = child.pid;
  if (pid === undefined) { d.err("cannot start: the console process did not spawn"); return 1; }
  const t0 = d.now();
  while (d.now() - t0 < 60_000) {
    if (exited !== null) {
      d.err(`the console exited while starting (${String(exited)}); last log lines:`);
      for (const l of logTail(log, 15)) d.err(`  ${l}`);
      return 1;
    }
    const info = readInfo(dir);
    if (info && info.pid === pid && (await answeredPid(info.port)) === pid) {
      child.unref();
      const pv = await previewsOf(info.port);
      d.out(`console started: pid ${pid}, http://127.0.0.1:${info.port}, previews :${pv?.previewPort ?? "?"}, LAN ${info.lan ? "on" : "off"}`);
      d.out(`log: ${log}   (pnpm fw console logs -f)`);
      d.out(`sign in with the owner passphrase at http://127.0.0.1:${info.port}/owner/login`);
      return 0;
    }
    await sleep(200);
  }
  d.err("the console did not answer /api/health within 60 s; it keeps running (pnpm fw console status, pnpm fw console logs)");
  child.unref();
  return 1;
}

export async function stopConsole(d: ConsoleDeps): Promise<number> {
  const dir = consoleDirOf(d.env, d.cwd);
  const p = await probe(dir, d.call);
  const plan = d.call({ op: "console.daemon", kind: "stop", ...(p.recorded !== null ? { recorded: p.recorded } : {}), ...(p.answered !== null ? { answered: p.answered } : {}) });
  if (typeof plan.target !== "number") { d.out("no console is running; nothing was signalled"); return 0; }
  const pid = plan.target;
  let ids: { id: string; pid: number | null }[] = [];
  try { ids = (JSON.parse(readFileSync(join(dir, "preview", "table.json"), "utf8")) as { id: string; pid: number | null }[]).map(({ id, pid: q }) => ({ id, pid: q })); } catch { /* none recorded */ }
  process.kill(pid, "SIGTERM");
  const t0 = d.now();
  while (alive(pid) && d.now() - t0 < 30_000) await sleep(100);
  if (alive(pid)) { d.err(`the console (pid ${pid}) did not exit within 30 s after SIGTERM; it was not killed harder`); return 1; }
  const left = ids.filter((e) => e.pid !== null && alive(e.pid));
  if (left.length > 0) { d.err(`console stopped, but preview processes are still alive: ${left.map((e) => `${e.id}(${e.pid})`).join(", ")}`); return 1; }
  d.out(`console stopped (pid ${pid}); previews it owned: ${ids.length} stopped, none left`);
  return 0;
}

export async function statusConsole(d: ConsoleDeps): Promise<number> {
  const dir = consoleDirOf(d.env, d.cwd);
  const p = await probe(dir, d.call);
  const log = join(dir, "console.log");
  if (p.verified === null || !p.info) { d.out(`stopped; log: ${log}`); return 1; }
  const pv = await previewsOf(p.info.port);
  d.out(`running  pid ${p.verified}  uptime ${p.info.startedAt ? fmtDur(d.now() - p.info.startedAt) : "?"}`);
  d.out(`console  http://127.0.0.1:${p.info.port}   previews :${pv?.previewPort ?? "?"}   LAN ${p.info.lan ? "on" : "off"}`);
  d.out(`previews running: ${pv?.count ?? "?"}`);
  d.out(`log      ${log}`);
  return 0;
}

export async function restartConsole(d: ConsoleDeps, args: string[]): Promise<number> {
  parseFlags(args);
  const dir = consoleDirOf(d.env, d.cwd);
  const p = await probe(dir, d.call);
  const plan = d.call({ op: "console.daemon", kind: "restart", ...(p.recorded !== null ? { recorded: p.recorded } : {}), ...(p.answered !== null ? { answered: p.answered } : {}) });
  for (const s of plan.steps as { step: string }[]) {
    if (s.step === "stop") { const c = await stopConsole(d); if (c !== 0) return c; }
    else return startConsole(d, args);
  }
  return 1;
}

export async function logsConsole(d: ConsoleDeps, args: string[]): Promise<number> {
  let n = 50; let follow = false;
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === "-f") follow = true;
    else if (a === "-n") { const v = Number(args[++i]); if (!Number.isInteger(v) || v < 0) throw new UsageError(CONSOLE_USAGE); n = v; }
    else throw new UsageError(CONSOLE_USAGE);
  }
  const log = join(consoleDirOf(d.env, d.cwd), "console.log");
  if (!existsSync(log)) { d.err(`no log yet: ${log}`); return 1; }
  for (const l of logTail(log, n)) d.out(l);
  if (!follow) return 0;
  const fd = openSync(log, "r");
  let pos = fstatSync(fd).size;
  watchFile(log, { interval: 300 }, () => {
    const size = fstatSync(fd).size;
    if (size < pos) pos = 0;
    if (size === pos) return;
    const buf = Buffer.alloc(size - pos);
    const got = readSync(fd, buf, 0, buf.length, pos);
    pos += got;
    process.stdout.write(buf.subarray(0, got));
  });
  await new Promise<void>((res) => { process.once("SIGINT", res); process.once("SIGTERM", res); });
  unwatchFile(log); closeSync(fd);
  return 0;
}

export async function consoleCli(args: string[], d: ConsoleDeps): Promise<number> {
  const [sub, ...rest] = args;
  switch (sub) {
    case "start": return startConsole(d, rest);
    case "stop": if (rest.length) throw new UsageError(CONSOLE_USAGE); return stopConsole(d);
    case "restart": return restartConsole(d, rest);
    case "status": if (rest.length) throw new UsageError(CONSOLE_USAGE); return statusConsole(d);
    case "logs": return logsConsole(d, rest);
    default: throw new UsageError(CONSOLE_USAGE);
  }
}
