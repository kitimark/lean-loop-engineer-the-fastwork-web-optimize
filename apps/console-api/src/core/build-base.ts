// Which commit of `main` was the fwcore binary built from? TS STAND-IN for Fw.Obs.chooseBase (lean/Fw/Obs/Stale.lean:
// chooseBase, fromLog; theorems chooseBase_fresh, chooseBase_stale_record, chooseBase_no_move, fromLog_mem), to be
// replaced by an fwcore op; test/build-base.test.ts holds the same table as the `#guard`s in that file.
//
// scripts/fwcore-build.sh writes `fwcore.commit` AFTER a successful build, so a record is at least as new as its
// binary. A plain `lake build` leaves the old record behind (older than the binary): it says nothing. Then the base is
// the newest ref move of `main` at or before the binary's mtime (a build starts at a head of `main`). No such move, or
// two moves in the same second: unknown. Unknown is an alert (svc.unknown), never silence.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

export type Base = { sha: string } | { unknown: string };
/** Reflog entries of `main`, newest first; times in seconds. */
export type LogEntry = { sha: string; time: number };

export const SHA = /^[0-9a-f]{40}$/;
export const CORE_BIN_REL = "lean/.lake/build/bin/fwcore";
export const CORE_COMMIT_REL = `${CORE_BIN_REL}.commit`;

export function fromLog(bin: number, log: LogEntry[]): Base {
  const c = log.filter((e) => e.time <= bin);
  if (c.length === 0) return { unknown: "no move of main at or before the binary" };
  const [first, ...rest] = c as [LogEntry, ...LogEntry[]];
  if (rest.some((e) => e.time === first.time)) return { unknown: "two moves of main in the same second as the binary's base" };
  return { sha: first.sha };
}

export function chooseBase(bin: number, rec: { sha: string; time: number } | null, log: LogEntry[]): Base {
  if (rec !== null && bin <= rec.time) return { sha: rec.sha };
  return fromLog(bin, log);
}

/** `git reflog show --date=unix --format='%H %gd' main` output -> entries (lines that do not parse are dropped). */
export function parseReflog(out: string): LogEntry[] {
  const res: LogEntry[] = [];
  for (const line of out.split("\n")) {
    const m = /^([0-9a-f]{40}) main@\{(\d+)\}$/.exec(line.trim());
    if (m) res.push({ sha: m[1]!, time: Number(m[2]) });
  }
  return res;
}

export const REFLOG_ARGS = ["reflog", "show", "--date=unix", "--format=%H %gd", "main"];

/** The record next to the binary: its commit and mtime (seconds), or null when absent or malformed. */
export function readRecord(binPath: string): { sha: string; time: number } | null {
  const rp = `${binPath}.commit`;
  try {
    const sha = readFileSync(rp, "utf8").trim();
    return SHA.test(sha) ? { sha, time: Math.floor(statSync(rp).mtimeMs / 1000) } : null;
  } catch { return null; }
}

/** The build commit of the binary at `binPath`, with git run in `root` (sync; console-api calls it at each spawn). */
export function buildBase(root: string, binPath: string): Base {
  if (!existsSync(binPath)) return { unknown: "no fwcore binary" };
  const bin = Math.floor(statSync(binPath).mtimeMs / 1000);
  const rec = readRecord(binPath);
  if (rec !== null && bin <= rec.time) return { sha: rec.sha };
  try {
    return fromLog(bin, parseReflog(execFileSync("git", REFLOG_ARGS, { cwd: root, encoding: "utf8", timeout: 5000 })));
  } catch (e) { return { unknown: `git reflog failed: ${(e as Error).message.split("\n")[0]}` }; }
}

export const binIn = (root: string) => join(root, CORE_BIN_REL);
