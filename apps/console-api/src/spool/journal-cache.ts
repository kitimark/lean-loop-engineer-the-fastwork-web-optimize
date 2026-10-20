// Workflow journal cache. TS STAND-IN of Lean `Fw.Console.JournalFold` (plan_hit, plan_tail, plan_shrink, plan_rewrite,
// commitEnd_append_*, view_incremental, skip_*, nextTick_*), checked against packages/contracts/golden/console/journal-cache.jsonl.
import { closeSync, fstatSync, openSync, readSync } from "node:fs";
import { parseJournal, type JLine } from "./workflow.ts";

export type Cached = { size: number; mtime: number; offset: number };
export type Stat = { size: number; mtime: number };
export type Act = "hit" | "tail" | "full";

/** Lean `plan`: same stat reads nothing, a larger file is read from the committed offset, anything else in full. */
export function plan(c: Cached, s: Stat, guard: boolean): Act {
  if (s.size === c.size && s.mtime === c.mtime) return "hit";
  return c.size < s.size && guard ? "tail" : "full";
}

const GUARD = 256;

/** The guard bytes of a journal: its first bytes and the bytes just before the committed offset. An append leaves both unchanged. */
function guardOf(fd: number, offset: number): string {
  const part = (pos: number, len: number) => { const b = Buffer.alloc(len); const n = len ? readSync(fd, b, 0, len, pos) : 0; return b.subarray(0, n).toString("latin1"); };
  return part(0, Math.min(GUARD, offset)) + "|" + part(Math.max(0, offset - GUARD), Math.min(GUARD, offset));
}

/** Lean `commitEnd`: the length through the last newline (a torn last line waits). */
export const commitEnd = (b: Uint8Array): number => b.lastIndexOf(10) + 1;

/** Lean `skip`: a run is skipped when its signature is unchanged, it ended and every event of it was accepted. */
export const skipRun = (s: { sameSig: boolean; ended: boolean; allSent: boolean }): boolean => s.sameSig && s.ended && s.allSent;

/** Lean `nextTick`: the first safety tick strictly after `t`, ticks at the multiples of `p`. */
export const nextTick = (p: number, t: number): number => (Math.floor(t / p) + 1) * p;

type Entry = Cached & { committed: JLine[]; view: JLine[]; guard: string };

/** The `JLine`s of each run's `journal.jsonl`, read once and then only what was appended (Lean `view_incremental`). */
export class JournalCache {
  private m = new Map<string, Entry>();
  /** journal bytes read from disk since this cache was made (local debug counter) */
  bytesRead = 0;

  /** The lines of the journal at `path` (committed lines, then the torn last line parsed on its own). */
  read(run: string, path: string, st: Stat | null): JLine[] {
    if (!st) { this.m.delete(path); return []; }
    const c = this.m.get(path);
    let fd: number | null = null;
    try {
      let act: Act = c ? plan(c, st, true) : "full";
      if (c && act === "hit") return c.view;
      if (c && act === "tail") { fd = openSync(path, "r"); act = plan(c, st, guardOf(fd, c.offset) === c.guard); }
      const from = c && act === "tail" ? c.offset : 0;
      const base = c && act === "tail" ? c.committed : [];
      fd ??= openSync(path, "r");
      const size = fstatSync(fd).size;
      const buf = Buffer.alloc(Math.max(0, size - from));
      const n = buf.length ? readSync(fd, buf, 0, buf.length, from) : 0;
      this.bytesRead += n;
      const chunk = buf.subarray(0, n);
      const end = commitEnd(chunk);
      const committed = base.concat(parseJournal(run, chunk.subarray(0, end).toString("utf8")));
      const torn = chunk.subarray(end).toString("utf8");
      const view = torn === "" ? committed : committed.concat(parseJournal(run, torn));
      this.m.set(path, { size: st.size, mtime: st.mtime, offset: from + end, committed, view, guard: guardOf(fd, from + end) });
      return view;
    } catch { this.m.delete(path); return []; }
    finally { if (fd !== null) closeSync(fd); }
  }

  /** Forget the journals under `prefix` that are no longer listed. */
  keepOnly(prefix: string, paths: ReadonlySet<string>): void { for (const k of this.m.keys()) if (k.startsWith(prefix) && !paths.has(k)) this.m.delete(k); }
}
