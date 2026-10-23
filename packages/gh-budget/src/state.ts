// The shared files: one budget state (opaque JSON, only fwcore reads its meaning), one state lock, one poller lock,
// one runs-status file written by the poller only. Writes are atomic: temp file + rename.
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import type { Env, Json } from "./core.ts";
import { lockSync } from "./lock.ts";

export const paths = (dir: string) => ({
  state: join(dir, "state.json"),
  lock: join(dir, "state.lock"),
  poller: join(dir, "poller.lock"),
  status: join(dir, "runs-status.json"),
  meta: (runId: number) => join(dir, "meta", `${runId}.json`),
  metaLock: (runId: number) => join(dir, "meta", `${runId}.lock`),
  jobs: (runId: number) => join(dir, "meta", `${runId}.jobs.json`),
  jobsLock: (runId: number) => join(dir, "meta", `${runId}.jobs.lock`),
  waiters: join(dir, "waiters"),
  incidents: join(dir, "incidents.jsonl"),
});

/** Atomic write: temp file in the same directory, then rename. */
export function writeAtomic(path: string, text: string): void {
  const tmp = `${path}.${process.pid}.${randomBytes(4).toString("hex")}.tmp`;
  writeFileSync(tmp, text);
  renameSync(tmp, path);
}

export function readJson<T = Json>(path: string): T | null {
  try { return JSON.parse(readFileSync(path, "utf8")) as T; } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw e;
  }
}

export const loadState = (dir: string): Json | null => readJson(paths(dir).state);
export function saveState(dir: string, s: Json): void {
  mkdirSync(dir, { recursive: true });
  writeAtomic(paths(dir).state, JSON.stringify(s));
}

/** Exactly one writer at a time: run `fn` holding the state lock. `fn` is synchronous, so no await can interleave. */
export function locked<T>(env: Env, fn: () => T, lockWaitMs: number = 120_000): T {
  mkdirSync(env.dir, { recursive: true });
  const l = lockSync(paths(env.dir).lock, lockWaitMs);
  try { return fn(); } finally { l.release(); }
}

/** A `ci.budget.step` event; the caller already holds the state lock. */
export function stepUnlocked(env: Env, event: Json): Json {
  const r = env.core({ op: "ci.budget.step", now: env.now(), state: loadState(env.dir), event });
  saveState(env.dir, r.state as Json);
  return r.state as Json;
}

/** A `ci.budget.step` event, applied under the lock. */
export const stepEvent = (env: Env, event: Json): Json => locked(env, () => stepUnlocked(env, event));

/** The row `gh run list` gave for one run. */
export type Row = { status: string; conclusion: string | null; databaseId: number; headBranch: string; workflowName: string; headSha: string; createdAt: string;
  /** GitHub's own time of the last change of the run (lag instrumentation: `fw ci wait` phases); absent in files written before it was listed. */
  updatedAt?: string;
  /** The attempt of the run (`gh run rerun` makes attempt 2 of the same id); absent in files written before it was listed. */
  attempt?: number;
  /** The trigger of the run (`push`, `workflow_dispatch`, ...) and its title (a dispatch's `run-name` carries its nonce); absent in files written before they were listed. */
  event?: string; displayTitle?: string };
/** The runs-status file: the last list the poller read. `stopped` is set when fwcore said stop. */
export type Status = { at: number; tickAt?: number; createdSince?: number | null; rows: Row[]; stopped?: string; stoppedAt?: number };

export const readStatus = (dir: string): Status | null => readJson<Status>(paths(dir).status);
export function writeStatus(dir: string, s: Status): void {
  mkdirSync(dir, { recursive: true });
  writeAtomic(paths(dir).status, JSON.stringify(s));
}
