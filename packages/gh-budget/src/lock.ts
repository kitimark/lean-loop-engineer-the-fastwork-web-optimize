// A lock file shared by processes: created with link(2) of a complete temp file (so the content is never half
// written), `EEXIST` means held. Stale rule: the holder's pid is dead (an OS fact, no clock, no age). Taking over
// a dead holder goes through a `.break` lock so two contenders cannot both remove a fresh lock; the break lock
// itself has a dead-pid rule only (a residual race of two processes breaking a dead break lock in the same
// millisecond is accepted and listed in the handoff).
import { linkSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { randomBytes } from "node:crypto";

type Held = { pid: number; token: string };
export type Lock = { release(): void };

/** The lock stayed held by a live process for the whole wait: a named refusal, not a crash (`ghCharged` turns it into `busy`). */
export class LockBusy extends Error {}

const alive = (pid: number): boolean => {
  try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; }
};

function readHeld(path: string): Held | null {
  try {
    const j = JSON.parse(readFileSync(path, "utf8")) as Held;
    return typeof j.pid === "number" && typeof j.token === "string" ? j : { pid: process.pid, token: "unreadable" }; // unreadable: treat as held
  } catch (e) {
    return (e as NodeJS.ErrnoException).code === "ENOENT" ? null : { pid: process.pid, token: "unreadable" };
  }
}

const unlinkQuiet = (p: string) => { try { unlinkSync(p); } catch { /* gone */ } };

/** link(2) our temp file to `path`: true if we now hold it, false if it exists. */
function linkOnce(tmp: string, path: string): boolean {
  try { linkSync(tmp, path); return true; } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "EEXIST") return false;
    throw e;
  }
}

const releaser = (path: string, token: string): Lock => ({
  release() { if (readHeld(path)?.token === token) unlinkQuiet(path); },
});

/** Try once to take the lock at `path`; null when a live process holds it. */
export function tryLock(path: string): Lock | null {
  mkdirSync(dirname(path), { recursive: true });
  const token = randomBytes(8).toString("hex");
  const tmp = `${path}.${token}.tmp`;
  writeFileSync(tmp, JSON.stringify({ pid: process.pid, token }));
  try {
    for (let attempt = 0; attempt < 3; attempt++) {
      if (linkOnce(tmp, path)) return releaser(path, token);
      const h = readHeld(path);
      if (h === null) continue; // vanished between link and read
      if (alive(h.pid)) return null;
      breakStale(path, h.token);
    }
    return null;
  } finally {
    unlinkQuiet(tmp);
  }
}

/** Remove the dead holder `token` of `path`, under a `.break` lock. */
function breakStale(path: string, token: string): void {
  const bp = `${path}.break`;
  const bt = randomBytes(8).toString("hex");
  const tmp = `${bp}.${bt}.tmp`;
  writeFileSync(tmp, JSON.stringify({ pid: process.pid, token: bt }));
  try {
    if (!linkOnce(tmp, bp)) {
      const b = readHeld(bp);
      if (b && !alive(b.pid)) unlinkQuiet(bp); // a dead breaker: clear it, the next attempt retries
      return;
    }
    const h = readHeld(path);
    if (h && h.token === token && !alive(h.pid)) unlinkQuiet(path);
    if (readHeld(bp)?.token === bt) unlinkQuiet(bp);
  } finally {
    unlinkQuiet(tmp);
  }
}

const nap = (ms: number) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

/** Take the lock, blocking the thread up to `waitMs` (the holder is another process); throws when it stays held. */
export function lockSync(path: string, waitMs: number): Lock {
  const t0 = Date.now();
  for (;;) {
    const l = tryLock(path);
    if (l) return l;
    if (Date.now() - t0 >= waitMs) throw new LockBusy(`lock ${path} held by a live process for ${waitMs} ms`);
    nap(25);
  }
}

/** Take the lock without blocking the thread: retry once a second through `sleep` (for locks held across an await). */
export async function lockAsync(path: string, waitS: number, now: () => number, sleepUntil: (t: number) => Promise<void>): Promise<Lock> {
  const t0 = now();
  for (;;) {
    const l = tryLock(path);
    if (l) return l;
    if (now() - t0 >= waitS) throw new Error(`lock ${path} held by a live process for ${waitS} s`);
    await sleepUntil(now() + 1);
  }
}
