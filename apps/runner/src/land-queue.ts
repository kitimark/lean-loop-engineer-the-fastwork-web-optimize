// `fw land --queue`: lands in first-in-first-out order by one runner (task land-queue).
// TS stand-in for Lean `Fw.Console.LandQueue` (step/pending/next/queued, retryAfter, runnerLive); marked for replacement by an
// `fwcore` op; checked against the golden `packages/contracts/golden/console/land-queue.jsonl` (test/land-queue.test.ts).
// The queue is an append-only log `<consoleDir>/land-queue.jsonl`: `enq` lines and `res` lines; the pending list is their fold.
// Nobody writes a "state". The runner lock `<consoleDir>/land-queue.runner` holds (pid, start time); a holder is alive only when the
// start time of the process now at that pid is the recorded one. No process is ever found by a command-line pattern.
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { refusalReason, refusedLine, retryable, type Kind } from "./land-verdict.ts";

export type Entry = { task: string; branch: string };
/** a pending entry also carries the `--allow` globs it was queued with */
export type QEntry = Entry & { allow: string[] };
export type Ev = ({ ev: "enq" } & QEntry) | { ev: "res"; task: string; kind: Kind; tries?: number; ms?: number; reason?: string };

export const queueFile = (consoleDir: string): string => join(consoleDir, "land-queue.jsonl");
export const runnerFile = (consoleDir: string): string => join(consoleDir, "land-queue.runner");

/** The log of a queue file; lines that are not events are skipped (a torn or foreign line never blocks the queue). */
export function parseLog(text: string): Ev[] {
  const out: Ev[] = [];
  for (const l of text.split("\n")) {
    if (!l.trim()) continue;
    try {
      const j = JSON.parse(l) as Record<string, unknown>;
      if (j.ev === "enq" && typeof j.task === "string" && typeof j.branch === "string")
        out.push({ ev: "enq", task: j.task, branch: j.branch, allow: Array.isArray(j.allow) ? j.allow.filter((a): a is string => typeof a === "string") : [] });
      else if (j.ev === "res" && typeof j.task === "string" && typeof j.kind === "string") out.push({ ev: "res", task: j.task, kind: j.kind as Kind });
    } catch { /* skip */ }
  }
  return out;
}
export const readLog = (consoleDir: string): Ev[] => {
  const f = queueFile(consoleDir);
  return existsSync(f) ? parseLog(readFileSync(f, "utf8")) : [];
};

/** Lean `step` folded over a log (`pending`): `enq` appends unless its task is pending, `res` removes the task. */
export function pending(log: Ev[]): QEntry[] {
  let q: QEntry[] = [];
  for (const v of log) {
    if (v.ev === "enq") { if (!q.some((x) => x.task === v.task)) q = [...q, { task: v.task, branch: v.branch, allow: v.allow }]; }
    else q = q.filter((x) => x.task !== v.task);
  }
  return q;
}
/** Lean `queued`: is the branch a pending entry? (the `landQueued` fact of `fw next` / `fw watch`) */
export const queued = (q: Entry[], branch: string): boolean => q.some((x) => x.branch === branch);
/** The branches of the pending entries of a console dir (empty when there is no queue). */
export function queuedBranches(consoleDir: string): string[] {
  try { return pending(readLog(consoleDir)).map((x) => x.branch); } catch { return []; }
}
/** The last recorded result of each task, in log order (for `--queue-status`). */
export function results(log: Ev[]): { task: string; kind: Kind }[] {
  const m = new Map<string, Kind>();
  for (const v of log) if (v.ev === "res") m.set(v.task, v.kind);
  return [...m].map(([task, kind]) => ({ task, kind }));
}

/** Lean `retryAfter`: only busy and dirty, and fewer than `max` attempts so far. */
export const retryAfter = (k: Kind, tries: number, max: number): boolean => retryable(k) && tries < max;
/** Lean `runnerLive`: the recorded start time is the start time of the process now at the pid. */
export const runnerLive = (held: string, probe: string | null): boolean => probe === held;

/** The start time of a process, as `ps -o lstart= -p <pid>` prints it (null: no such process). Identity by pid, never by pattern. */
export function startTimeOf(pid: number): string | null {
  try { return execFileSync("ps", ["-o", "lstart=", "-p", String(pid)], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim() || null; }
  catch { return null; }
}

/** Append `enq` for the task unless it is pending (Lean `enq_idem`); one `O_APPEND` write of one short line. */
export function enqueue(consoleDir: string, e: QEntry): { added: boolean } {
  mkdirSync(consoleDir, { recursive: true });
  if (pending(readLog(consoleDir)).some((x) => x.task === e.task)) return { added: false };
  appendFileSync(queueFile(consoleDir), JSON.stringify({ ev: "enq", task: e.task, branch: e.branch, allow: e.allow, at: Date.now() }) + "\n");
  return { added: true };
}

export type Runner = { release: () => void };
/** Take the runner lock, or null when a live runner holds it. A lock of a dead pid or of another incarnation of the pid is taken over. */
export function takeRunner(consoleDir: string, startTime: (pid: number) => string | null = startTimeOf): Runner | null {
  mkdirSync(consoleDir, { recursive: true });
  const f = runnerFile(consoleDir);
  const mine = { pid: process.pid, start: startTime(process.pid) ?? "" };
  for (let i = 0; i < 3; i++) {
    try {
      writeFileSync(f, JSON.stringify(mine), { flag: "wx" });
      return { release: () => { try { if (JSON.parse(readFileSync(f, "utf8")).pid === mine.pid) unlinkSync(f); } catch { /* gone */ } } };
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
    }
    let held: { pid?: unknown; start?: unknown } = {};
    try { held = JSON.parse(readFileSync(f, "utf8")); } catch { /* torn: treat as stale */ }
    if (typeof held.pid === "number" && typeof held.start === "string" && runnerLive(held.start, startTime(held.pid))) return null;
    try { unlinkSync(f); } catch { /* another runner took it over first */ }
  }
  return null;
}

export type QueueOptions = {
  consoleDir: string;
  /** one land attempt of an entry; resolves to its verdict kind (the land's own kind, never parsed from prose) */
  attempt: (e: QEntry) => Promise<Kind | { kind: Kind; reason?: string }>;
  /** where `REFUSED: <reason>` goes before the VERDICT line, default stderr */
  err?: (line: string) => void;
  /** attempts per entry (busy and dirty only), default 5 */
  maxTries?: number;
  retryMs?: number;
  startTime?: (pid: number) => string | null;
};
export type QueueResult = { task: string; kind: Kind; tries: number; ms: number; reason?: string };

/** The land log of a task under `<consoleDir>/land-logs`: its newest `<task>-<sha7>.log`, else `<task>-queue.log`. */
export function landLogOf(consoleDir: string, task: string): string {
  const dir = join(consoleDir, "land-logs");
  const stem = task.replace(/[^A-Za-z0-9._-]/g, "_") + "-";
  const mine = new RegExp(`^${stem.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[0-9a-f]{7}\\.log$`); // the name land.ts writes
  let best: { f: string; t: number } | null = null;
  try {
    for (const f of readdirSync(dir)) if (mine.test(f)) { const t = statSync(join(dir, f)).mtimeMs; if (!best || t > best.t) best = { f, t }; }
  } catch { /* no dir yet */ }
  return join(dir, best?.f ?? `${stem}queue.log`);
}

/** The queue's view of one real land: its kind, and the reason of a refusal taken from the land's last `REFUSED: ` line. */
export function landAttemptResult(res: { ok: boolean; kind?: Kind; lines: string[] }): Kind | { kind: Kind; reason: string } {
  const kind = res.kind ?? (res.ok ? "done" : "unknown");
  const why = res.lines.filter((l) => l.startsWith("REFUSED: ")).pop()?.slice("REFUSED: ".length);
  return !res.ok && why !== undefined ? { kind, reason: why } : kind;
}

/** Run the queue: take the runner lock (or return `ran: false` when a live runner has it), land the head until the queue is empty,
 *  then look again after releasing the lock so an entry queued in between is not forgotten. */
export async function runQueue(o: QueueOptions): Promise<{ ran: boolean; results: QueueResult[] }> {
  const done: QueueResult[] = [];
  let ran = false;
  const max = o.maxTries ?? 5;
  for (;;) {
    const lock = takeRunner(o.consoleDir, o.startTime);
    if (!lock) return { ran, results: done };
    ran = true;
    try {
      for (;;) {
        const e = pending(readLog(o.consoleDir))[0];
        if (!e) break;
        const t0 = Date.now();
        let tries = 1;
        let kind: Kind;
        let reason: string | undefined;
        let shown = false; // a refusal the attempt already explained on stderr (`fw land` prints its REFUSED lines)
        for (;;) {
          reason = undefined;
          shown = false;
          try {
            const r = await o.attempt(e);
            if (typeof r === "string") kind = r; else { kind = r.kind; reason = r.reason; shown = r.reason !== undefined && r.reason !== ""; }
          } catch (x) { kind = "unknown"; reason = x instanceof Error ? x.message : String(x); }
          reason = refusalReason(kind, reason);
          if (!retryAfter(kind, tries, max)) break;
          await new Promise((r) => setTimeout(r, o.retryMs ?? 3000));
          tries++;
        }
        if (reason !== undefined) {
          if (!shown) (o.err ?? ((l) => console.error(l)))(refusedLine(reason));
          try { const f = landLogOf(o.consoleDir, e.task); mkdirSync(dirname(f), { recursive: true }); appendFileSync(f, `queue: ${refusedLine(reason)}\n`); } catch { /* the queue log has it too */ }
        }
        appendFileSync(queueFile(o.consoleDir), JSON.stringify({ ev: "res", task: e.task, kind, tries, ms: Date.now() - t0, at: Date.now(), ...(reason !== undefined ? { reason } : {}) }) + "\n");
        done.push({ task: e.task, kind, tries, ms: Date.now() - t0, ...(reason !== undefined ? { reason } : {}) });
      }
    } finally { lock.release(); }
    if (pending(readLog(o.consoleDir)).length === 0) return { ran, results: done };
  }
}
