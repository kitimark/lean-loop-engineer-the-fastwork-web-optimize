// `fw watch --stream` push: one line per new lead-facing user event of .fw-console/events.jsonl, within ~2 s of the append.
// Which events are lead-facing is fwcore's (`obs.push`, Fw.Obs.Push); this file tails the file and prints. Glue only.
import { closeSync, fstatSync, openSync, readSync, statSync, watch, type FSWatcher } from "node:fs";
import { basename, dirname } from "node:path";

export type PushCall = (req: Record<string, unknown>) => Promise<Record<string, unknown>>;

const oneLine = (t: string) => t.replace(/\s+/g, " ").trim();
const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "~" : s);

/** The stream line of one event: `USER <type> <subject> <text>`; subject is the flag or the step, text cut to 160. */
export function pushLine(e: Record<string, unknown>): string {
  const s = (k: string) => (typeof e[k] === "string" ? (e[k] as string) : "");
  const subject = s("flag") || s("step") || s("id");
  return oneLine(`USER ${s("type")} ${subject} ${cut(oneLine(s("text")), 160)}`);
}

/** Reads the complete new lines of a growing file from a byte offset. A partial last line waits for its newline;
 *  a shrunk file or a new inode (rotation) restarts at 0. */
export class LineTail {
  private off: number;
  private ino: number;
  private rest = Buffer.alloc(0);
  private readonly file: string;
  constructor(file: string) {
    this.file = file;
    try { const st = statSync(file); this.off = st.size; this.ino = st.ino; } catch { this.off = 0; this.ino = -1; }
  }
  read(): string[] {
    let fd: number;
    try { fd = openSync(this.file, "r"); } catch { return []; }
    try {
      const st = fstatSync(fd);
      if (st.ino !== this.ino || st.size < this.off) { this.off = 0; this.rest = Buffer.alloc(0); this.ino = st.ino; }
      const n = st.size - this.off;
      if (n <= 0) return [];
      const buf = Buffer.alloc(n);
      const got = readSync(fd, buf, 0, n, this.off);
      this.off += got;
      let all = Buffer.concat([this.rest, buf.subarray(0, got)]);
      const out: string[] = [];
      for (let i = all.indexOf(10); i >= 0; i = all.indexOf(10)) { out.push(all.subarray(0, i).toString("utf8")); all = all.subarray(i + 1); }
      this.rest = all;
      return out;
    } finally { closeSync(fd); }
  }
}

/** Starts the push: prints a line per new lead-facing user event. Returns a stop function. Watches the directory (so
 *  a rotated file is seen), with a 1 s safety poll in case fs.watch drops an event. */
export function startPush(file: string, core: PushCall, say: (s: string) => void): () => void {
  const tail = new LineTail(file);
  let busy = false, again = false, stopped = false;
  const drain = async () => {
    if (busy) { again = true; return; }
    busy = true;
    try {
      do {
        again = false;
        const evs: Record<string, unknown>[] = [];
        for (const l of tail.read()) { try { const o = JSON.parse(l); if (o && typeof o === "object") evs.push(o); } catch { /* not an event */ } }
        if (evs.length === 0 || stopped) continue;
        const r = await core({ op: "obs.push", events: evs.map((e) => ({ type: String(e.type ?? ""), actor: String(e.actor ?? "") })) });
        const flags = Array.isArray(r.push) ? r.push : [];
        evs.forEach((e, i) => { if (flags[i] === true && !stopped) say(pushLine(e)); });
      } while (again);
    } catch (e) { say(oneLine(`PUSH error ${e instanceof Error ? e.message : String(e)}`)); }
    finally { busy = false; }
  };
  let w: FSWatcher | null = null;
  try { w = watch(dirname(file), (_k, name) => { if (!name || name === basename(file)) void drain(); }); w.on("error", () => {}); } catch { /* the poll covers it */ }
  const poll = setInterval(() => void drain(), 1000);
  return () => { stopped = true; clearInterval(poll); w?.close(); };
}
