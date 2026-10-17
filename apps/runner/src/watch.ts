// `fw watch`: collect the team snapshot, ask fwcore `obs.health` for states and alerts, print a compact table,
// append input+output to .fw-console/health.jsonl. No decision logic here: every state and alert code is fwcore's.
import { begin } from "./timing.ts";
import { execFile, spawn } from "node:child_process";
import { appendFileSync, closeSync, existsSync, fstatSync, mkdirSync, openSync, readdirSync, readSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { UsageError } from "./lib.ts";
import { collectFacts, formatNext, nextAlerts, type NextReply } from "./next.ts";
import {
  collectSnapshot, exe, liveKeep, parsePs, pathsFor, readKeep, writeKeep, type AgentSnap, type Paths, type Prev, type PsRow, type Snapshot,
} from "./watch-collect.ts";

export const WATCH_USAGE = "usage: fw watch [--json] [--interval <s>] [--until-alert]   (exit 3 when a new alert appears)\n       fw watch --keep <pid> [--note <text>] | --unkeep <pid>   (declare an intended long-runner: no proc.long)";

/** `critical`: tied to a critical-path task (fwcore sorts those first). */
export interface Alert { code: string; subject: string; detail: string; critical?: boolean }
export interface Health {
  agents: { id: string; state: string; alerts: string[] }[]; system: { alerts: string[] };
  counts: Record<string, number>; alerts: Alert[];
}
export type CoreCall = (req: Record<string, unknown>) => Promise<Record<string, unknown>>;

/** Candidate fwcore binaries, first that knows obs.health wins: FW_CORE_BIN, this checkout, the main checkout,
 *  then sibling worktrees (until the op is built in the main checkout). */
export function coreCandidates(root: string, main: string, env: NodeJS.ProcessEnv = process.env): string[] {
  const rel = "lean/.lake/build/bin/fwcore";
  const c = [env.FW_CORE_BIN, join(root, rel), join(main, rel)];
  try { for (const w of readdirSync(join(main, ".claude/worktrees"))) c.push(join(main, ".claude/worktrees", w, rel)); } catch { /* none */ }
  return [...new Set(c.filter((x): x is string => !!x && existsSync(x)))];
}

function callBin(bin: string, req: Record<string, unknown>, timeoutMs = 15000): Promise<Record<string, unknown>> {
  return new Promise((res, rej) => {
    const child = spawn(bin, [], { env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" }, stdio: ["pipe", "pipe", "pipe"] });
    let out = "";
    const t = setTimeout(() => { child.kill(); rej(new Error("fwcore timeout")); }, timeoutMs);
    child.stdout.on("data", (d) => { out += d; if (out.includes("\n")) { clearTimeout(t); child.kill(); try { res(JSON.parse(out.split("\n")[0]!)); } catch (e) { rej(e); } } });
    child.on("error", (e) => { clearTimeout(t); rej(e); });
    child.on("close", () => { clearTimeout(t); if (!out.includes("\n")) rej(new Error("fwcore closed without a reply")); });
    child.stdin.end(JSON.stringify({ id: 1, ...req }) + "\n");
  });
}

export function coreCaller(bins: string[]): CoreCall {
  return async (req) => {
    if (bins.length === 0) throw new Error("fwcore not built: cd lean && lake build (obs.health needs the watch-lean commit)");
    let last = "";
    for (const b of bins) {
      try {
        const r = await callBin(b, req);
        if (typeof r.error === "string") { last = r.error; continue; }
        return r;
      } catch (e) { last = e instanceof Error ? e.message : String(e); }
    }
    throw new Error(`fwcore obs.health failed: ${last}`);
  };
}

export async function check(snap: Snapshot, core: CoreCall): Promise<Health> {
  const r = await core({ op: "obs.health", ...snap });
  return r as unknown as Health;
}

/** `obs.next` for the same snapshot: the facts are observed in next.ts, every action is fwcore's. Null when the op or
 *  a collector is unavailable (the watch then runs without NEXT lines). */
export async function nextFor(paths: Paths, main: string, snap: Snapshot, h: Health, core: CoreCall): Promise<NextReply | null> {
  try {
    const facts = await collectFacts(paths, main, snap, h);
    return (await core({ op: "obs.next", now: snap.now, agents: facts })) as NextReply;
  } catch { return null; }
}

/** `fw next`: print the current NEXT list once. Read-only: no log line, no action. Returns the exit code. */
export async function nextMain(args: string[], cwd: string, print: (s: string) => void = console.log, core?: CoreCall): Promise<number> {
  if (args.length) throw new UsageError("usage: fw next   (prints `NEXT <agent> <action> <args>` once; read-only)");
  const { root, main } = await repoRoots(cwd);
  const paths = pathsFor(main);
  const call = core ?? coreCaller(coreCandidates(root, main));
  const last = readLastLog(paths);
  const prevSnap: Prev | null = last?.input?.system ? { at: last.at, system: last.input.system, critical: last.input.critical } : null;
  const snap = await collectSnapshot(paths, Date.now(), undefined, prevSnap);
  const h = await check(snap, call);
  const reply = await nextFor(paths, main, snap, h, call);
  if (!reply) { print("fw next: fwcore obs.next unavailable (cd lean && lake build)"); return 0; }
  const lines = formatNext(reply);
  print(lines.length ? lines.join("\n") : "NEXT: none");
  return 0;
}

// ---- rendering ----
const ORDER: Record<string, number> = { stalled: 0, active: 1, idle: 2, parked: 3, gone: 4, done: 5 };
const KIND: Record<string, string> = { teammate: "tm", subagent: "sub", workflow: "wf" };
const min = (ms: number) => Math.max(0, Math.round(ms / 60000));
const kfmt = (n: number | null) => (n === null ? "-" : n >= 1000 ? `${Math.round(n / 1000)}k` : String(n));
const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "~" : s);
const pad = (s: string, n: number) => s.padEnd(n);
const shortModel = (m: string | null) => (m ? m.replace(/^claude-/, "").replace(/-\d{8}$/, "") : "-");

export function renderTable(snap: Snapshot, h: Health, maxRows = 24): string {
  const byId = new Map(snap.agents.map((a) => [a.id, a]));
  const live = h.agents.filter((a) => a.state !== "done" && a.state !== "gone")
    .sort((a, b) => (ORDER[a.state]! - ORDER[b.state]!) || (byId.get(a.id)!.lastAt - byId.get(b.id)!.lastAt));
  const lines: string[] = [];
  lines.push(`${pad("agent", 26)} ${pad("kind", 4)} ${pad("type", 15)} ${pad("model", 13)} ${pad("state", 8)} ${"idle".padStart(4)} ${"tools".padStart(5)} ${"err".padStart(3)} ${"ctx".padStart(5)}  in-flight`);
  for (const w of live.slice(0, maxRows)) {
    const a: AgentSnap = byId.get(w.id)!;
    const label = a.name ?? a.task ?? a.id;
    const inf = a.inflight ? `${a.inflight.tool} ${min(snap.now - a.inflight.since)}m` : "-";
    lines.push(`${pad(cut(label, 26), 26)} ${pad(KIND[a.kind] ?? "-", 4)} ${pad(cut(a.type ?? "-", 15), 15)} ${pad(cut(shortModel(a.model), 13), 13)} ${pad(w.state, 8)} ${(min(snap.now - a.lastAt) + "m").padStart(4)} ${String(a.tools).padStart(5)} ${String(a.errors).padStart(3)} ${kfmt(a.ctxTokens).padStart(5)}  ${inf}`);
  }
  if (live.length > maxRows) lines.push(`... +${live.length - maxRows} more live agents (use --json)`);
  if (live.length === 0) lines.push("(no live agents)");
  const c = h.counts, s = snap.system;
  const lock = s.simLock.holder ? `simlock ${s.simLock.holder} ${min(snap.now - (s.simLock.since ?? snap.now))}m` : "simlock free";
  const ciBad = s.ci.filter((r) => r.conclusion === "failure").length;
  const st = (k: string) => (s.stale?.includes(k) ? " stale" : "");
  lines.push(`agents active ${c.active} idle ${c.idle} parked ${c.parked} stalled ${c.stalled} gone ${c.gone ?? 0} done ${c.done} | load ${s.load1} mem ${s.memPressure} disk ${s.diskFreeGB}GB | ${lock} | docker ${s.docker.length}${st("docker")} wt ${s.worktrees} ci ${s.ci.length} (${ciBad} failed)${st("ci")}`);
  if (h.alerts.length === 0) lines.push("alerts: none");
  else {
    lines.push(`alerts (${h.alerts.length}):`);
    for (const a of h.alerts.slice(0, 8)) { const ag = byId.get(a.subject); lines.push(`  ${a.critical ? "*" : ""}${a.code} ${cut(ag ? (ag.name ?? ag.task ?? a.subject) : a.subject, 30)} ${cut(a.detail, 80)}`); }
    if (h.alerts.length > 8) lines.push(`  ... +${h.alerts.length - 8} more (use --json)`);
  }
  return lines.join("\n");
}

export const alertKey = (a: Alert) => `${a.code}|${a.subject}`;
export function newAlerts(prev: Set<string> | null, h: Health): Alert[] {
  return prev === null ? [] : h.alerts.filter((a) => !prev.has(alertKey(a)));
}

export function appendLog(p: Paths, snap: Snapshot, h: Health): void {
  mkdirSync(p.consoleDir, { recursive: true });
  appendFileSync(join(p.consoleDir, "health.jsonl"), JSON.stringify({ at: snap.now, input: snap, output: h }) + "\n");
}

export interface LogLine { at: number; input: Snapshot; output: Health }
/** The last complete line of .fw-console/health.jsonl, read from the end (the file only grows); null if none parses. */
export function readLastLog(p: Paths): LogLine | null {
  let fd: number;
  try { fd = openSync(join(p.consoleDir, "health.jsonl"), "r"); } catch { return null; }
  try {
    const size = fstatSync(fd).size;
    let tail = "";
    for (let end = size, chunk = 1 << 16; end > 0; chunk *= 2) {
      const start = Math.max(0, end - chunk);
      const buf = Buffer.alloc(end - start);
      readSync(fd, buf, 0, buf.length, start);
      tail = buf.toString("utf8") + tail;
      end = start;
      const lines = tail.split("\n").filter((l) => l.trim());
      // the first piece may be cut mid-line unless we reached the file start
      if (lines.length >= (start === 0 ? 1 : 2)) {
        try {
          const o = JSON.parse(lines[lines.length - 1]!);
          return typeof o?.at === "number" && o.input && o.output && Array.isArray(o.output.alerts) ? (o as LogLine) : null;
        } catch { return null; }
      }
    }
    return null;
  } finally { closeSync(fd); }
}

export interface WatchOpts {
  json: boolean; intervalS: number | null; untilAlert: boolean;
  /** declare (`--keep`) or withdraw (`--unkeep`) an intended long-runner, then exit without a check */
  keep: number | null; unkeep: number | null; note: string | null;
}
export function parseWatchArgs(args: string[]): WatchOpts {
  const o: WatchOpts = { json: false, intervalS: null, untilAlert: false, keep: null, unkeep: null, note: null };
  const pid = (s: string | undefined) => {
    const n = Number(s);
    if (!Number.isInteger(n) || n < 1) throw new UsageError(WATCH_USAGE);
    return n;
  };
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === "--json") o.json = true;
    else if (a === "--until-alert") o.untilAlert = true;
    else if (a === "--interval") {
      const n = Number(args[++i]);
      if (!Number.isFinite(n) || n < 1) throw new UsageError(WATCH_USAGE);
      o.intervalS = n;
    } else if (a === "--keep") o.keep = pid(args[++i]);
    else if (a === "--unkeep") o.unkeep = pid(args[++i]);
    else if (a === "--note") {
      const t = args[++i];
      if (t === undefined) throw new UsageError(WATCH_USAGE);
      o.note = t;
    } else throw new UsageError(WATCH_USAGE);
  }
  if ((o.keep !== null || o.unkeep !== null) && (o.intervalS !== null || o.untilAlert || o.json || (o.keep !== null && o.unkeep !== null)))
    throw new UsageError(WATCH_USAGE);
  if (o.note !== null && o.keep === null) throw new UsageError(WATCH_USAGE);
  if (o.untilAlert && o.intervalS === null) o.intervalS = 300;
  return o;
}

/** `--keep`/`--unkeep`: rewrite .fw-console/keep.json (entries whose process is gone are dropped on the way).
 *  Returns the message to print. `rows` is the current `ps` table. */
export function declareKeep(paths: Paths, o: WatchOpts, rows: PsRow[], now: number): string {
  const cur = liveKeep(readKeep(paths), rows, now);
  if (o.unkeep !== null) {
    writeKeep(paths, cur.filter((e) => e.pid !== o.unkeep));
    return `fw watch: pid ${o.unkeep} is no longer declared`;
  }
  const r = rows.find((x) => x.pid === o.keep);
  if (!r) throw new UsageError(`fw watch: no running process ${o.keep}`);
  writeKeep(paths, [...cur.filter((e) => e.pid !== o.keep), { pid: r.pid, startedAt: Math.floor(now - r.ageMs), note: o.note }]);
  return `fw watch: pid ${r.pid} (${exe(r.comm)}) declared as an intended long-runner; its process tree raises no proc.long`;
}

function psRows(): Promise<PsRow[]> {
  return new Promise((res) => {
    execFile("ps", ["-A", "-o", "pid=,ppid=,etime=,comm="], { timeout: 3000, maxBuffer: 4_000_000 },
      (err, stdout) => res(err ? [] : parsePs(String(stdout))));
  });
}

export function repoRoots(cwd: string): Promise<{ root: string; main: string }> {
  return new Promise((res, rej) => {
    const c = spawn("git", ["rev-parse", "--show-toplevel", "--git-common-dir"], { cwd });
    let out = "";
    c.stdout.on("data", (d) => (out += d));
    c.on("close", (code) => {
      const [top, common] = out.trim().split("\n");
      if (code !== 0 || !top || !common) return rej(new Error("fw watch: run it inside the repo"));
      res({ root: top, main: dirname(resolve(top, common)) });
    });
  });
}

/** Returns the exit code. */
export async function watchMain(args: string[], cwd: string, print: (s: string) => void = console.log, core?: CoreCall): Promise<number> {
  const o = parseWatchArgs(args);
  const { root, main } = await repoRoots(cwd);
  const paths = pathsFor(main); // the console data (.fw-console, .local) lives in the main checkout
  if (o.keep !== null || o.unkeep !== null) { print(declareKeep(paths, o, await psRows(), Date.now())); return 0; }
  // a repeating watch is itself an intended long-runner: declare it while it runs, so other checks do not flag it
  if (o.intervalS !== null) {
    const me = (await psRows()).find((r) => r.pid === process.pid);
    if (me) {
      const now = Date.now();
      writeKeep(paths, [...liveKeep(readKeep(paths), await psRows(), now).filter((e) => e.pid !== me.pid),
        { pid: me.pid, startedAt: Math.floor(now - me.ageMs), note: "fw watch --interval" }]);
      process.once("exit", () => { try { writeKeep(paths, readKeep(paths).filter((e) => e.pid !== me.pid)); } catch { /* best effort */ } });
    }
  }
  const call = core ?? coreCaller(coreCandidates(root, main));
  // the last logged check is the baseline: a relaunch after exit 3 does not re-report the alert it exited on,
  // and a failed gh/docker collector carries that check's value forward (marked stale)
  const last = readLastLog(paths);
  let prev: Set<string> | null = last ? new Set(last.output.alerts.map(alertKey)) : null;
  let prevSnap: Prev | null = last?.input?.system ? { at: last.at, system: last.input.system, critical: last.input.critical } : null;
  for (;;) {
    const endPass = begin("fw", "watch pass", main); // timing-spans: one span per collection pass
    const snap = await collectSnapshot(paths, Date.now(), undefined, prevSnap);
    const h = await check(snap, call);
    const nx = await nextFor(paths, main, snap, h, call);
    if (nx) h.alerts.push(...nextAlerts(nx)); // agent.held / agent.unlanded: fwcore's proposals shown as alerts
    appendLog(paths, snap, h);
    endPass(0);
    const fresh = newAlerts(prev, h);
    print(o.json ? JSON.stringify({ input: snap, output: h, next: nx }) : [renderTable(snap, h), ...(nx ? formatNext(nx) : [])].join("\n"));
    if (o.untilAlert && fresh.length) {
      if (!o.json) print(`NEW ALERT: ${fresh.map((a) => `${a.code} ${a.subject}`).join("; ")}`);
      return 3;
    }
    prev = new Set(h.alerts.map(alertKey));
    prevSnap = { at: snap.now, system: snap.system, critical: snap.critical };
    if (o.intervalS === null) return 0;
    await new Promise((r) => setTimeout(r, o.intervalS! * 1000));
  }
}
