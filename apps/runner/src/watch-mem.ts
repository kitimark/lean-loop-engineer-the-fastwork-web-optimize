import { closeSync, fstatSync, openSync, readSync } from "node:fs";


export function windowRows<T extends { at: number }>(kept: readonly T[], fresh: readonly T[], cap: number): T[] {
  const all = [...kept, ...fresh];
  all.sort((a, b) => a.at - b.at);
  return cap <= 0 ? [] : all.slice(-cap);
}

export function readFrom(cursor: number, size: number, same: boolean): number {
  return same && cursor <= size ? cursor : 0;
}

export function nextCursor(start: number, nl: number | null): number {
  return nl === null ? start : start + nl + 1;
}

export interface Cursor { ino: number; pos: number }
const CHUNK = 512 << 10;

export function readAppended(file: string, cur: Cursor | undefined, onText: (text: string) => void, onReset: () => void): Cursor | null {
  let fd: number;
  try { fd = openSync(file, "r"); } catch { return null; }
  try {
    const st = fstatSync(fd);
    const start = readFrom(cur?.pos ?? 0, st.size, cur !== undefined && cur.ino === st.ino);
    if (start === 0 && cur !== undefined && cur.pos > 0) onReset();
    let pos = start;
    let buf = Buffer.allocUnsafe(Math.min(CHUNK, Math.max(1, st.size - start)));
    while (pos < st.size) {
      const n = readSync(fd, buf, 0, Math.min(buf.length, st.size - pos), pos);
      if (n <= 0) break;
      const nl = buf.subarray(0, n).lastIndexOf(10);
      if (nl < 0) {
        if (pos + n >= st.size) break;
        buf = Buffer.allocUnsafe(Math.min(buf.length * 2, st.size - pos));
        continue;
      }
      onText(buf.toString("utf8", 0, nl + 1));
      pos = nextCursor(pos, nl);
    }
    return { ino: st.ino, pos };
  } finally { closeSync(fd); }
}

export function tailer<S>(init: () => S, fold: (s: S, text: string) => S): { read: (file: string) => S; prune: (keep: ReadonlySet<string>) => void } {
  const states = new Map<string, { cur: Cursor | undefined; s: S }>();
  return {
    read(file) {
      const e = states.get(file) ?? { cur: undefined, s: init() };
      const cur = readAppended(file, e.cur, (text) => { e.s = fold(e.s, text); }, () => { e.s = init(); });
      if (cur === null) { states.delete(file); return init(); }
      e.cur = cur;
      states.set(file, e);
      return e.s;
    },
    prune(keep) { for (const f of [...states.keys()]) if (!keep.has(f)) states.delete(f); },
  };
}

export function ownMemoryKb(): { rssKb: number; heapKb: number } {
  const m = process.memoryUsage();
  return { rssKb: Math.round(m.rss / 1024), heapKb: Math.round(m.heapUsed / 1024) };
}
