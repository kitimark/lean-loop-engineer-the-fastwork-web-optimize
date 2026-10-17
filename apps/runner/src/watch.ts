// `fw watch`: collect the team snapshot, ask fwcore `obs.health` for states and alerts, print a compact table,
// append input+output to .fw-console/health.jsonl. No decision logic here: every state and alert code is fwcore's.
import { spawn } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { UsageError } from "./lib.ts";
import { collectSnapshot, pathsFor, type AgentSnap, type Paths, type Snapshot } from "./watch-collect.ts";

export const WATCH_USAGE = "usage: fw watch [--json] [--interval <s>] [--until-alert]   (exit 3 when a new alert appears)";

export interface Alert { code: string; subject: string; detail: string }
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

// ---- rendering ----
const ORDER: Record<string, number> = { stalled: 0, waiting: 1, active: 2, idle: 3, done: 4 };
const min = (ms: number) => Math.max(0, Math.round(ms / 60000));
const kfmt = (n: number | null) => (n === null ? "-" : n >= 1000 ? `${Math.round(n / 1000)}k` : String(n));
const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "~" : s);
const pad = (s: string, n: number) => s.padEnd(n);
const shortModel = (m: string | null) => (m ? m.replace(/^claude-/, "").replace(/-\d{8}$/, "") : "-");

export function renderTable(snap: Snapshot, h: Health, maxRows = 24): string {
  const byId = new Map(snap.agents.map((a) => [a.id, a]));
  const live = h.agents.filter((a) => a.state !== "done")
    .sort((a, b) => (ORDER[a.state]! - ORDER[b.state]!) || (byId.get(a.id)!.lastAt - byId.get(b.id)!.lastAt));
  const lines: string[] = [];
  lines.push(`${pad("agent", 26)} ${pad("type", 15)} ${pad("model", 13)} ${pad("state", 8)} ${"idle".padStart(4)} ${"tools".padStart(5)} ${"err".padStart(3)} ${"ctx".padStart(5)}  in-flight`);
  for (const w of live.slice(0, maxRows)) {
    const a: AgentSnap = byId.get(w.id)!;
    const label = a.name ?? a.task ?? a.id;
    const inf = a.inflight ? `${a.inflight.tool} ${min(snap.now - a.inflight.since)}m` : "-";
    lines.push(`${pad(cut(label, 26), 26)} ${pad(cut(a.type ?? "-", 15), 15)} ${pad(cut(shortModel(a.model), 13), 13)} ${pad(w.state, 8)} ${(min(snap.now - a.lastAt) + "m").padStart(4)} ${String(a.tools).padStart(5)} ${String(a.errors).padStart(3)} ${kfmt(a.ctxTokens).padStart(5)}  ${inf}`);
  }
  if (live.length > maxRows) lines.push(`... +${live.length - maxRows} more live agents (use --json)`);
  if (live.length === 0) lines.push("(no live agents)");
  const c = h.counts, s = snap.system;
  const lock = s.simLock.holder ? `simlock ${s.simLock.holder} ${min(snap.now - (s.simLock.since ?? snap.now))}m` : "simlock free";
  const ciBad = s.ci.filter((r) => r.conclusion === "failure").length;
  lines.push(`agents active ${c.active} idle ${c.idle} waiting ${c.waiting} stalled ${c.stalled} done ${c.done} | load ${s.load1} mem ${s.memPressure} disk ${s.diskFreeGB}GB | ${lock} | docker ${s.docker.length} wt ${s.worktrees} ci ${s.ci.length} (${ciBad} failed)`);
  if (h.alerts.length === 0) lines.push("alerts: none");
  else {
    lines.push(`alerts (${h.alerts.length}):`);
    for (const a of h.alerts.slice(0, 8)) { const ag = byId.get(a.subject); lines.push(`  ${a.code} ${cut(ag ? (ag.name ?? ag.task ?? a.subject) : a.subject, 30)} ${cut(a.detail, 80)}`); }
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

export interface WatchOpts { json: boolean; intervalS: number | null; untilAlert: boolean }
export function parseWatchArgs(args: string[]): WatchOpts {
  const o: WatchOpts = { json: false, intervalS: null, untilAlert: false };
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === "--json") o.json = true;
    else if (a === "--until-alert") o.untilAlert = true;
    else if (a === "--interval") {
      const n = Number(args[++i]);
      if (!Number.isFinite(n) || n < 1) throw new UsageError(WATCH_USAGE);
      o.intervalS = n;
    } else throw new UsageError(WATCH_USAGE);
  }
  if (o.untilAlert && o.intervalS === null) o.intervalS = 300;
  return o;
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
  const call = core ?? coreCaller(coreCandidates(root, main));
  let prev: Set<string> | null = null;
  for (;;) {
    const snap = await collectSnapshot(paths);
    const h = await check(snap, call);
    appendLog(paths, snap, h);
    const fresh = newAlerts(prev, h);
    print(o.json ? JSON.stringify({ input: snap, output: h }) : renderTable(snap, h));
    if (o.untilAlert && fresh.length) {
      if (!o.json) print(`NEW ALERT: ${fresh.map((a) => `${a.code} ${a.subject}`).join("; ")}`);
      return 3;
    }
    prev = new Set(h.alerts.map(alertKey));
    if (o.intervalS === null) return 0;
    await new Promise((r) => setTimeout(r, o.intervalS! * 1000));
  }
}
