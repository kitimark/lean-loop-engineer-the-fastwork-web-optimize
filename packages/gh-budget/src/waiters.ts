// Waiter markers: one file per waiting process and run, `<waiters dir>/r<runId>.<pid>.<hex>`, holding `{pid, start}`.
// `start` is the process start time the waiter read from the OS once, at start: the output of `ps -o lstart= -p <pid>`
// (macOS ps(1): "lstart  The exact time the command started, using the %c format described in strftime(3)"; procps ps(1):
// "lstart  time the command started"), kept as an opaque token and compared only for equality. Second resolution.
// The text is local time, so the call pins TZ=UTC and LC_ALL=C (as apps/runner/src/watch-collect.ts PS_START does): the
// waiter that records the token and the poller that reads it later may run under different TZ values.
// Stability on Linux is INFERRED: procps derives lstart from the boot time plus clock ticks, and a wall-clock step may
// shift the boot time by about 1 s, which would make a live waiter look reused (it is then swept as an orphan). This file only READS facts (does the pid exist, what is its start time
// now); whether the waiter is alive is `Fw.Ci.Budget.Marker.alive` in fwcore (`ci.budget.next` with `markers`).
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Env } from "./core.ts";
import { paths } from "./state.ts";

/** What fwcore's `Marker` carries (the wire shape of `ci.budget.next` `markers`). */
export type MarkerFact = { runId: number; killOk: boolean; recorded?: string; now?: string };

/** Does `kill(pid, 0)` find the process? A process of another user (EPERM) counts as found. */
export function killOk(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; }
}

/** The start time of `pid` as the OS reports it now, or null when ps cannot say. LC_ALL=C and TZ=UTC keep the text locale- and zone-free. */
export function startToken(pid: number): string | null {
  const r = spawnSync("ps", ["-o", "lstart=", "-p", String(pid)], { encoding: "utf8", env: { ...process.env, LC_ALL: "C", TZ: "UTC" } });
  const t = r.status === 0 && typeof r.stdout === "string" ? r.stdout.trim() : "";
  return t === "" ? null : t;
}

let self: string | null | undefined;
/** This process's start token, read once (the marker records it). */
export function selfStart(): string | null {
  if (self === undefined) self = startToken(process.pid);
  return self;
}

/** The text of a marker this process writes. */
export const markerText = (): string => JSON.stringify({ pid: process.pid, start: selfStart() });

/** Every marker in the waiters dir as facts for fwcore. The caller holds the state lock, so a waiter that has written
 *  its marker and sent `register` inside one lock is seen whole, and a watch without its marker cannot exist
 *  (`addWaiter`). A file that is not a marker name is ignored; a marker whose text is not `{start: string}` has no token. */
export function readMarkers(env: Env): MarkerFact[] {
  const dir = paths(env.dir).waiters;
  let names: string[];
  try { names = readdirSync(dir); } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw e;
  }
  const nowOf = new Map<number, string | null>(); // one ps per pid per call
  const out: MarkerFact[] = [];
  for (const n of names) {
    const m = /^r(\d+)\.(\d+)\.[0-9a-f]+$/.exec(n);
    if (!m) continue;
    const runId = Number(m[1]);
    const pid = Number(m[2]);
    let recorded: string | undefined;
    try {
      const j = JSON.parse(readFileSync(join(dir, n), "utf8")) as { start?: unknown };
      if (typeof j.start === "string") recorded = j.start;
    } catch { /* an empty or unreadable marker (older code) has no token */ }
    const ok = killOk(pid);
    let now: string | undefined;
    if (ok && recorded !== undefined) {
      if (!nowOf.has(pid)) nowOf.set(pid, pid === process.pid ? selfStart() : startToken(pid)); // our own start time never changes
      now = nowOf.get(pid) ?? undefined;
    }
    out.push({ runId, killOk: ok, ...(recorded === undefined ? {} : { recorded }), ...(now === undefined ? {} : { now }) });
  }
  return out;
}
