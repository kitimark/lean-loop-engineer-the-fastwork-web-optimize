// `fw land --queue`: lands in first-in-first-out order by one runner (task land-queue).
// TS stand-in for Lean `Fw.Console.LandQueue` (step/pending/next/queued, retryAfter, runnerLive); marked for replacement by an
// `fwcore` op; checked against the golden `packages/contracts/golden/console/land-queue.jsonl` (test/land-queue.test.ts).
// The queue is an append-only log `<consoleDir>/land-queue.jsonl`: `enq` lines and `res` lines; the pending list is their fold.
// Nobody writes a "state". The runner lock `<consoleDir>/land-queue.runner` holds (pid, start time); a holder is alive only when the
// start time of the process now at that pid is the recorded one. No process is ever found by a command-line pattern.
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { REBUILD_REASON, afterLand, needsRebuild, refusalReason, refusedLine, retryable, stopKind, type Kind } from "./land-verdict.ts";

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
/** The console could not be reached (connection refused or reset: it is not listening). Thrown by `httpFor` (land.ts), read by the queue as the Lean `Att.unreachable`. */
export class ConsoleUnreachable extends Error {
  readonly url: string;
  constructor(url: string, cause?: unknown) { super(`console-api unreachable at ${url}: ${cause instanceof Error ? cause.message : String(cause)}`); this.name = "ConsoleUnreachable"; this.url = url; }
}

// Lean `healthDelay` / `healthPolls` / `pollTime` / `healthBoundMs` (golden `landQueue.healthSchedule`).
export const healthDelay = (i: number): number => Math.min(4000, 250 * 2 ** i);
export const HEALTH_POLLS = 20;
export const pollTime = (i: number): number => { let t = 0; for (let j = 0; j < i; j++) t += healthDelay(j); return t; };
export const HEALTH_BOUND_MS = pollTime(HEALTH_POLLS - 1);
/** Lean `healthReached`: does some poll of the schedule find a console that is back at `back` (null: never)? */
export const healthReached = (back: number | null): boolean => back !== null && Array.from({ length: HEALTH_POLLS }, (_, i) => i).some((i) => back <= pollTime(i));
/** Lean `consoleUnreachableReason`. */
export const CONSOLE_UNREACHABLE_REASON = "console-unreachable: console-api did not answer /api/health within the bounded wait (pnpm fw console status)";
export type Att = { landed: Kind } | "unreachable";
export type Next = "retry" | { final: Kind; reason?: string };
/** Lean `attemptNext`: retry a landed busy/dirty or a console that is back within the bound (attempts remaining); else final.
 *  An unreachable console that stays down is the refusal `busy` + `console-unreachable`, never `unknown`. */
export function attemptNext(a: Att, tries: number, max: number, back: number | null): Next {
  if (a === "unreachable") return healthReached(back) && tries < max ? "retry" : { final: "busy", reason: CONSOLE_UNREACHABLE_REASON };
  return retryAfter(a.landed, tries, max) ? "retry" : { final: a.landed };
}
/** Lean `healthWaitAfter`: the queue waits for the console after the rebuild it ran (a land of kind done that changed a core source). */
export const healthWaitAfter = (k: Kind, paths: string[]): boolean => needsRebuild(k, paths);

/** The bounded health wait (Lean `healthReached`): poll `probe` at the Lean schedule; true as soon as it answers, false after the last poll. */
export async function waitHealth(probe: () => Promise<boolean>, sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms))): Promise<boolean> {
  for (let i = 0; i < HEALTH_POLLS; i++) {
    if (await probe().catch(() => false)) return true;
    if (i < HEALTH_POLLS - 1) await sleep(healthDelay(i));
  }
  return false;
}

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
  /** main's head before an attempt; with `diff` and `rebuild` it turns on the fwcore rebuild between entries (Lean `afterLand`) */
  head?: () => string;
  /** the paths that changed in main since `from` (the merged diff of the land that just finished) */
  diff?: (from: string) => string[];
  /** `sh scripts/fwcore-build.sh` in the main checkout, timed as a span; true when it succeeded */
  rebuild?: () => Promise<boolean>;
  /** one GET /api/health of the console: true when it answers; with it an unreachable console is retried after a bounded wait (Lean `attemptNext`) */
  health?: () => Promise<boolean>;
  /** sleep of the health wait (tests pass a fake clock) */
  sleep?: (ms: number) => Promise<void>;
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
        const before = o.head && o.diff && o.rebuild ? o.head() : null;
        let kind: Kind;
        let reason: string | undefined;
        let gone = false; // the console never came back: the entry is refused and the queue stops (the rest stays pending)
        let shown = false; // a refusal the attempt already explained on stderr (`fw land` prints its REFUSED lines)
        for (;;) {
          reason = undefined;
          shown = false;
          let unreachable = false;
          try {
            const r = await o.attempt(e);
            if (typeof r === "string") kind = r; else { kind = r.kind; reason = r.reason; shown = r.reason !== undefined && r.reason !== ""; }
          } catch (x) {
            kind = "unknown"; reason = x instanceof Error ? x.message : String(x);
            unreachable = x instanceof ConsoleUnreachable && o.health !== undefined;
          }
          if (unreachable) {
            // Lean `attemptNext .unreachable`: wait for the console (bounded), then retry or refuse as console-unreachable (never unknown)
            const back = (await waitHealth(o.health!, o.sleep)) ? 0 : null;
            const n = attemptNext("unreachable", tries, max, back);
            if (n === "retry") { tries++; continue; }
            kind = "busy"; reason = typeof n === "object" ? n.reason : CONSOLE_UNREACHABLE_REASON; shown = false; gone = true;
            break;
          }
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
        if (gone) return { ran, results: done };
        if (before !== null && kind === "done") {
          // Lean `afterLand`: a land that changed a fwcore source rebuilds fwcore before the next dequeue; a failed rebuild stops the queue
          let paths: string[];
          try { paths = o.diff!(before); } catch { paths = ["lean/"]; } // an unreadable diff fails closed into a rebuild
          if (!needsRebuild(kind, paths)) continue;
          const ok = await o.rebuild!().catch(() => false);
          const nk = stopKind(afterLand(kind, paths, () => ok));
          if (nk === null) {
            // Lean `healthWaitAfter`: the console is often restarted after the rebuild; wait (bounded) before the next entry
            if (o.health && healthWaitAfter(kind, paths) && !(await waitHealth(o.health, o.sleep))) {
              const nx2 = pending(readLog(o.consoleDir))[0];
              (o.err ?? ((l) => console.error(l)))(refusedLine(CONSOLE_UNREACHABLE_REASON));
              if (nx2) {
                appendFileSync(queueFile(o.consoleDir), JSON.stringify({ ev: "res", task: nx2.task, kind: "busy", tries: 0, ms: 0, at: Date.now(), reason: CONSOLE_UNREACHABLE_REASON }) + "\n");
                done.push({ task: nx2.task, kind: "busy", tries: 0, ms: 0, reason: CONSOLE_UNREACHABLE_REASON });
              }
              return { ran, results: done };
            }
            continue;
          }
          const nx = pending(readLog(o.consoleDir))[0];
          const why = refusalReason(nk, REBUILD_REASON)!;
          (o.err ?? ((l) => console.error(l)))(refusedLine(why));
          if (nx) {
            appendFileSync(queueFile(o.consoleDir), JSON.stringify({ ev: "res", task: nx.task, kind: nk, tries: 0, ms: 0, at: Date.now(), reason: why }) + "\n");
            done.push({ task: nx.task, kind: nk, tries: 0, ms: 0, reason: why });
          }
          return { ran, results: done };
        }
      }
    } finally { lock.release(); }
    if (pending(readLog(o.consoleDir)).length === 0) return { ran, results: done };
  }
}
