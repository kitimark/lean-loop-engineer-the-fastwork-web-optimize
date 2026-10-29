import { begin, record } from "./timing.ts";
import { execFile, spawn } from "node:child_process";
import { appendFileSync, closeSync, existsSync, fstatSync, mkdirSync, openSync, readdirSync, readFileSync, readSync, writeFileSync, writeSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { UsageError } from "./lib.ts";
import { collectFacts, formatNext, nextAlerts, slowAlerts, slowNextLines, type NextReply } from "./next.ts";
import { contendedFlagged, ghFlagged } from "./watch-gh.ts";
import { reapTick } from "./reap.ts";
import { reapHeldAlerts } from "./watch-reap.ts";
import { heldPass, type ReapPass } from "./reap.ts";
import { startPush } from "./watch-push.ts";
import { ownMemoryKb } from "./watch-mem.ts";
import { CLASSES, diskGcTick } from "./disk-gc.ts";
import { fwcoreCall } from "./run.ts";
import { passParts } from "./run-phases.ts";
import {
  collectSnapshot, exe, parseStartRows, watchGh, pathsFor, PS_START, readKeep, readSamples, writeKeep, type AgentSnap, type KeepDecide, type KeepEntry, type Paths,
  type Prev, type Snapshot, type StartRow,
} from "./watch-collect.ts";

export const WATCH_USAGE = "usage: fw watch [--json] [--interval <s>] [--until-alert]   (exit 3 when a new alert appears)\n       fw watch [--interval <s>] --stream [--tick]   (one OPEN/CLOSE line per alert change, never exits on an alert; --tick adds a TICK line with the watcher's own memory)\n       fw watch --keep <pid> [--note <text>] | --unkeep <pid>   (declare an intended long-runner: no proc.long)";

export interface Alert { code: string; subject: string; detail: string; critical?: boolean }
export interface Health {
  agents: { id: string; state: string; alerts: string[] }[]; system: { alerts: string[] };
  counts: Record<string, number>; alerts: Alert[];
}
export type CoreCall = (req: Record<string, unknown>) => Promise<Record<string, unknown>>;

export function coreCandidates(root: string, main: string, env: NodeJS.ProcessEnv = process.env): string[] {
  const rel = "lean/.lake/build/bin/fwcore";
  const c = [env.FW_CORE_BIN, join(root, rel), join(main, rel)];
  try { for (const w of readdirSync(join(main, ".claude/worktrees"))) c.push(join(main, ".claude/worktrees", w, rel)); } catch {}
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
    if (bins.length === 0) throw new Error("fwcore not built: sh scripts/fwcore-build.sh (obs.health needs the watch-lean commit)");
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

export async function nextFor(paths: Paths, main: string, snap: Snapshot, h: Health, core: CoreCall, reap: ReapPass | null = heldPass(main)): Promise<NextReply | null> {
  try {
    const facts = await collectFacts(paths, main, snap, h, reap);
    return (await core({ op: "obs.next", now: snap.now, agents: facts })) as NextReply;
  } catch { return null; }
}

export async function slowWith(paths: Paths, core: CoreCall): Promise<{ slow: string[]; details: string[] }> {
  try {
    const samples = readSamples(paths);
    if (samples.length === 0) return { slow: [], details: [] };
    const r = await core({ op: "obs.slow", detail: true, samples });
    const strs = (x: unknown) => (Array.isArray(x) ? (x as unknown[]).filter((y): y is string => typeof y === "string") : []);
    const slow = strs(r.slow), details = strs(r.details);
    return { slow, details: details.length === slow.length ? details : [] };
  } catch { return { slow: [], details: [] }; }
}

export interface MemCheck { line: string; alerts: Alert[]; mem: { rssKb: number; heapKb: number } }
/** The watcher's own resident size against the Lean bound (ops.watchRss): its tick line and, above the bound, an alert. A failed call gives neither. */
export async function memCheck(core: CoreCall, mem = ownMemoryKb()): Promise<MemCheck | null> {
  try {
    const r = await core({ op: "ops.watchRss", ...mem });
    if (typeof r.line !== "string" || typeof r.over !== "boolean" || typeof r.detail !== "string") return null;
    return { line: r.line, mem, alerts: r.over ? [{ code: "watch.rss", subject: "fw-watch", detail: r.detail }] : [] };
  } catch { return null; }
}

export async function slowFor(paths: Paths, core: CoreCall): Promise<string[]> { return (await slowWith(paths, core)).slow; }

export async function nextMain(args: string[], cwd: string, print: (s: string) => void = console.log, core?: CoreCall): Promise<number> {
  if (args.length) throw new UsageError("usage: fw next   (prints `NEXT <agent> <action> <args>` once; read-only)");
  const { root, main } = await repoRoots(cwd);
  const paths = pathsFor(main);
  const call = core ?? coreCaller(coreCandidates(root, main));
  const last = readLastLog(paths);
  const prevSnap: Prev | null = last?.input?.system ? { at: last.at, system: last.input.system, critical: last.input.critical, ghDegraded: ghFlagged(last.output), contended: contendedFlagged(last.output) } : null;
  const snap = await collectSnapshot(paths, Date.now(), undefined, prevSnap, undefined, keepDecider(call));
  const h = await check(snap, call);
  const reply = await nextFor(paths, main, snap, h, call);
  if (!reply) { print("fw next: fwcore obs.next unavailable (sh scripts/fwcore-build.sh)"); return 0; }
  const lines = [...formatNext(reply), ...slowNextLines(await slowFor(paths, call))];
  print(lines.length ? lines.join("\n") : "NEXT: none");
  return 0;
}

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
export interface AlertKey { code: string; subject: string }
export interface Diff { opened: Alert[]; closed: AlertKey[]; next: AlertKey[] }
const keyList = (x: unknown): AlertKey[] => (Array.isArray(x) ? x : []).filter((k): k is AlertKey => typeof k?.code === "string" && typeof k?.subject === "string")
  .map((k) => ({ code: k.code, subject: k.subject }));
export async function diffAlerts(core: CoreCall, prev: AlertKey[], alerts: Alert[]): Promise<Diff> {
  const r = await core({ op: "ops.watchDiff", prev, now: alerts.map((a) => ({ code: a.code, subject: a.subject, detail: a.detail })) });
  if (!Array.isArray(r.opened) || !Array.isArray(r.closed) || !Array.isArray(r.next)) throw new Error("fwcore ops.watchDiff: bad reply");
  const opened = keyList(r.opened).map((k, i) => ({ ...k, detail: String((r.opened as { detail?: unknown }[])[i]?.detail ?? "") }));
  return { opened, closed: keyList(r.closed), next: keyList(r.next) };
}
export async function newAlerts(core: CoreCall, prev: AlertKey[] | null, h: Health): Promise<Alert[]> {
  return prev === null ? [] : (await diffAlerts(core, prev, h.alerts)).opened;
}
export function keepDecider(core: CoreCall): KeepDecide {
  return async (entries, rows) => {
    const r = await core({ op: "ops.watchKeep", entries: entries.map((e) => ({ pid: e.pid, start: e.start })), rows });
    const nums = (x: unknown) => (Array.isArray(x) ? x.filter((n): n is number => Number.isInteger(n)) : null);
    const live = nums(r.live), keep = nums(r.keep);
    if (!live || !keep) throw new Error("fwcore ops.watchKeep: bad reply");
    return { live, keep };
  };
}

const oneLine = (t: string) => t.replace(/\s+/g, " ").trim();
export function streamLines(d: Diff): string[] {
  return [...d.opened.map((a) => oneLine(`OPEN ${a.code} ${a.subject} ${a.detail}`)), ...d.closed.map((k) => oneLine(`CLOSE ${k.code} ${k.subject}`))];
}
export const syncLine = (t: string) => { try { writeSync(1, t + "\n"); } catch { process.exit(141); } };

export function appendLog(p: Paths, snap: Snapshot, h: Health, mem?: { rssKb: number; heapKb: number }): void {
  mkdirSync(p.consoleDir, { recursive: true });
  appendFileSync(join(p.consoleDir, "health.jsonl"), JSON.stringify({ at: snap.now, input: snap, output: h, ...(mem ? { mem } : {}) }) + "\n");
}

export interface LogLine { at: number; input: Snapshot; output: Health }
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
  json: boolean; intervalS: number | null; untilAlert: boolean; stream: boolean;
  keep: number | null; unkeep: number | null; note: string | null; tick: boolean;
}
export function parseWatchArgs(args: string[]): WatchOpts {
  const o: WatchOpts = { json: false, intervalS: null, untilAlert: false, stream: false, keep: null, unkeep: null, note: null, tick: false };
  const pid = (s: string | undefined) => {
    const n = Number(s);
    if (!Number.isInteger(n) || n < 1) throw new UsageError(WATCH_USAGE);
    return n;
  };
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === "--json") o.json = true;
    else if (a === "--until-alert") o.untilAlert = true;
    else if (a === "--stream") o.stream = true;
    else if (a === "--tick") o.tick = true;
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
  if ((o.keep !== null || o.unkeep !== null) && (o.intervalS !== null || o.untilAlert || o.stream || o.json || (o.keep !== null && o.unkeep !== null)))
    throw new UsageError(WATCH_USAGE);
  if (o.stream && (o.untilAlert || o.json)) throw new UsageError(WATCH_USAGE);
  if (o.tick && !o.stream) throw new UsageError(WATCH_USAGE);
  if (o.note !== null && o.keep === null) throw new UsageError(WATCH_USAGE);
  if ((o.untilAlert || o.stream) && o.intervalS === null) o.intervalS = 300;
  return o;
}

async function liveDeclared(paths: Paths, rows: StartRow[], decide: KeepDecide): Promise<KeepEntry[]> {
  const entries = readKeep(paths);
  const { live } = await decide(entries, rows);
  return entries.filter((_, i) => live.includes(i));
}

export async function declareKeep(paths: Paths, o: WatchOpts, rows: StartRow[], decide: KeepDecide): Promise<string> {
  const cur = await liveDeclared(paths, rows, decide);
  if (o.unkeep !== null) {
    writeKeep(paths, readKeep(paths).filter((e) => e.pid !== o.unkeep));
    return `fw watch: pid ${o.unkeep} is no longer declared`;
  }
  const r = rows.find((x) => x.pid === o.keep);
  if (!r) throw new UsageError(`fw watch: no running process ${o.keep}`);
  writeKeep(paths, [...cur.filter((e) => e.pid !== o.keep), { pid: r.pid, start: r.start, note: o.note }]);
  return `fw watch: pid ${r.pid} (${exe(r.args.split(" ")[0] ?? r.args)}) declared as an intended long-runner; its process tree raises no proc.long`;
}

function startRows(): Promise<StartRow[]> {
  return new Promise((res) => {
    execFile("env", PS_START, { timeout: 3000, maxBuffer: 16_000_000 }, (err, stdout) => res(err ? [] : parseStartRows(String(stdout))));
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

export async function watchMain(args: string[], cwd: string, print?: (s: string) => void, core?: CoreCall): Promise<number> {
  const o = parseWatchArgs(args);
  const say = print ?? (o.stream ? syncLine : console.log);
  const { root, main } = await repoRoots(cwd);
  const paths = pathsFor(main);
  const call = core ?? coreCaller(coreCandidates(root, main));
  const decide = keepDecider(call);
  if (o.keep !== null || o.unkeep !== null) { say(await declareKeep(paths, o, await startRows(), decide)); return 0; }
  if (o.stream) return streamMain(o, paths, main, call, decide, say);
  if (o.intervalS !== null) {
    try {
      const rows = await startRows();
      const me = rows.find((r) => r.pid === process.pid);
      if (me) {
        writeKeep(paths, [...(await liveDeclared(paths, rows, decide)).filter((e) => e.pid !== me.pid),
          { pid: me.pid, start: me.start, note: "fw watch --interval" }]);
        process.once("exit", () => { try { writeKeep(paths, readKeep(paths).filter((e) => e.pid !== me.pid)); } catch {} });
      }
    } catch {}
  }
  const last = readLastLog(paths);
  let prev: AlertKey[] | null = last ? last.output.alerts.map((a) => ({ code: a.code, subject: a.subject })) : null;
  let prevSnap: Prev | null = last?.input?.system ? { at: last.at, system: last.input.system, critical: last.input.critical, ghDegraded: ghFlagged(last.output), contended: contendedFlagged(last.output) } : null;
  for (;;) {
    const { snap, h, nx, slow, tick } = await pass(paths, main, prevSnap, call, decide);
    const fresh = o.untilAlert ? await newAlerts(call, prev, h) : [];
    say(o.json ? JSON.stringify({ input: snap, output: h, next: nx, slow }) : [renderTable(snap, h), ...(nx ? formatNext(nx) : []), ...slowNextLines(slow), ...(tick ? [tick] : [])].join("\n"));
    if (o.untilAlert && fresh.length) {
      if (!o.json) say(`NEW ALERT: ${fresh.map((a) => `${a.code} ${a.subject}`).join("; ")}`);
      return 3;
    }
    const prev0 = prev;
    prev = h.alerts.map((a) => ({ code: a.code, subject: a.subject }));
    prevSnap = { at: snap.now, system: snap.system, critical: snap.critical, ghDegraded: ghFlagged(h), contended: contendedFlagged(h) };
    if (o.intervalS !== null) for (const l of reapTick(main)) if (!o.json) say(l);
    if (o.intervalS !== null && (await newAlerts(call, prev0, h)).some((a) => a.code === DISK_LOW)) for (const l of diskGcTick(main, [...CLASSES], fwcoreCall(main), process.env, { pressure: true })) if (!o.json) say(l);
    if (o.intervalS === null) return 0;
    await new Promise((r) => setTimeout(r, o.intervalS! * 1000));
  }
}

export const DISK_LOW = "sys.diskLow";

async function pass(paths: Paths, main: string, prevSnap: Prev | null, call: CoreCall, decide: KeepDecide) {
  const startMs = Date.now(), t0 = performance.now();
  watchGh.reset();
  const endPass = begin("fw", "watch pass", main);
  const snap = await collectSnapshot(paths, Date.now(), undefined, prevSnap, undefined, decide);
  const h = await check(snap, call);
  const rp = heldPass(main);
  const nx = await nextFor(paths, main, snap, h, call, rp);
  if (nx) h.alerts.push(...nextAlerts(nx));
  h.alerts.push(...reapHeldAlerts(rp));
  const { slow, details } = await slowWith(paths, call);
  h.alerts.push(...slowAlerts(slow, details));
  const mc = await memCheck(call);
  if (mc) h.alerts.push(...mc.alerts);
  appendLog(paths, snap, h, mc?.mem);
  endPass(0);
  for (const p of passParts(watchGh, performance.now() - t0)) record({ tool: "fw", step: p.step, startMs, durMs: p.durMs, exit: 0 }, main);
  return { snap, h, nx, slow, tick: mc?.line ?? null };
}

async function streamMain(o: WatchOpts, paths: Paths, main: string, call: CoreCall, decide: KeepDecide, say: (s: string) => void): Promise<number> {
  let ended = false;
  const end = (reason: string) => { if (!ended) { ended = true; say(oneLine(`STREAM END ${reason}`)); } };
  process.once("exit", (c) => end(`exit ${c}`));
  for (const [sig, n] of [["SIGINT", 2], ["SIGTERM", 15], ["SIGHUP", 1]] as const) process.once(sig, () => { end(`signal ${sig}`); process.exit(128 + n); });
  const last = readLastLog(paths);
  let prevSnap: Prev | null = last?.input?.system ? { at: last.at, system: last.input.system, critical: last.input.critical, ghDegraded: ghFlagged(last.output), contended: contendedFlagged(last.output) } : null;
  const stopPush = startPush(join(paths.consoleDir, "events.jsonl"), call, say);
  let open: AlertKey[] = [];
  try {
    for (;;) {
      const { snap, h, tick } = await pass(paths, main, prevSnap, call, decide);
      const d = await diffAlerts(call, open, h.alerts);
      for (const line of streamLines(d)) say(line);
      if (o.tick && tick) say(tick);
      open = d.next;
      for (const l of reapTick(main)) say(l);
      if (d.opened.some((a) => a.code === DISK_LOW)) for (const l of diskGcTick(main, [...CLASSES], fwcoreCall(main), process.env, { pressure: true })) say(l);
      prevSnap = { at: snap.now, system: snap.system, critical: snap.critical, ghDegraded: ghFlagged(h), contended: contendedFlagged(h) };
      await new Promise((r) => setTimeout(r, o.intervalS! * 1000));
    }
  } catch (e) {
    end(`error ${e instanceof Error ? e.message : String(e)}`);
    return 1;
  } finally { stopPush(); }
}
