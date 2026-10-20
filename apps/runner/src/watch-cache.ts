// The on-disk cache of `fw watch` transcript folds: one file per transcript under `<consoleDir>/watch-cache/`, holding
// the fold state of the complete lines before `offset`. A pass reads only the bytes appended since, or the whole file
// when `decide` says the saved state does not fit. Spec and proofs: lean/Fw/Obs/Fold.lean (`pass_eq_full`, `chain_inv`,
// `decide_*`); golden vectors: packages/contracts/golden/obs/watch-fold.jsonl (checked in test/watch-fold.test.ts).
// The cache is a memo of a pure function of the file's bytes: a missing, unreadable or foreign entry means a full read.
import { createHash } from "node:crypto";
import { closeSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, renameSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { FOLD_SCHEMA, foldText, initFold, loadFold, saveFold, stepLine, type FoldState } from "./watch-fold.ts";

/** Lean `Fw.Obs.Fold.Entry`. */
export interface Entry { schema: number; code: string; ino: number; offset: number }
/** Lean `Fw.Obs.Fold.Now`. */
export interface Now { schema: number; code: string; ino: number; size: number }
export type Mode = { mode: "resume"; offset: number } | { mode: "full" };

/** Lean `Fw.Obs.Fold.decide`. `anchorSame` is read only when the earlier checks pass. */
export function decide(e: Entry, n: Now, anchorSame: () => boolean): Mode {
  if (e.schema !== n.schema) return { mode: "full" };
  if (e.code !== n.code) return { mode: "full" };
  if (n.size < e.offset) return { mode: "full" };
  if (e.ino !== n.ino) return { mode: "full" };
  if (!anchorSame()) return { mode: "full" };
  return { mode: "resume", offset: e.offset };
}

/** Lean `Fw.Obs.Fold.cut`: the number of bytes up to and including the last newline (0: none). */
export function cutAt(buf: Uint8Array): number {
  const i = Buffer.prototype.lastIndexOf.call(buf, 10) as number;
  return i + 1;
}

let codeHashMemo: string | null = null;
/** The hash of the code that makes a state: this file and the fold. A change to either starts every transcript over. */
export function codeHash(): string {
  if (codeHashMemo) return codeHashMemo;
  const dir = dirname(fileURLToPath(import.meta.url));
  const h = createHash("sha256");
  for (const f of ["watch-fold.ts", "watch-cache.ts"]) h.update(readFileSync(join(dir, f)));
  return (codeHashMemo = h.digest("hex").slice(0, 16));
}

const CHUNK = 4 * 1024 * 1024;
const ANCHOR = 64;
const cacheFile = (dir: string, file: string) => join(dir, createHash("sha1").update(file).digest("hex").slice(0, 24) + ".json");

function readAt(fd: number, pos: number, len: number): Buffer {
  const buf = Buffer.alloc(len);
  let got = 0;
  while (got < len) { const n = readSync(fd, buf, got, len - got, pos + got); if (n <= 0) break; got += n; }
  return got === len ? buf : buf.subarray(0, got);
}

export interface Folded {
  /** the fold of the whole file as it was at `size` bytes (the unterminated tail included) */
  state: FoldState;
  /** how the state was made */
  how: "resumed" | "full";
  /** bytes read from the file */
  read: number;
}
interface Saved extends Entry { file: string; anchor: string; state: unknown }

function loadSaved(path: string): Saved | null {
  try {
    const j = JSON.parse(readFileSync(path, "utf8"));
    if (typeof j?.schema !== "number" || typeof j.code !== "string" || typeof j.ino !== "number" || typeof j.offset !== "number" ||
      typeof j.anchor !== "string" || typeof j.file !== "string") return null;
    return j as Saved;
  } catch { return null; }
}

/** The fold of `file` (which is `size` bytes now, inode `ino`), resumed from the saved state when `decide` allows it.
 *  `dir`: the cache directory (null: no cache). Writes the new saved state when the offset moved. */
export function foldFile(file: string, size: number, ino: number, dir: string | null): Folded {
  const fd = openSync(file, "r");
  try {
    const code = codeHash();
    const saved = dir ? loadSaved(cacheFile(dir, file)) : null;
    let st: FoldState | null = null, from = 0, how: Folded["how"] = "full";
    if (saved && saved.file === file) {
      const anchorOk = () => {
        const n = Math.min(ANCHOR, saved.offset);
        return readAt(fd, saved.offset - n, n).toString("hex") === saved.anchor;
      };
      const m = decide(saved, { schema: FOLD_SCHEMA, code, ino, size }, anchorOk);
      if (m.mode === "resume") {
        const s = loadFold(saved.state);
        if (s) { st = s; from = m.offset; how = "resumed"; }
      }
    }
    st ??= initFold(false);
    // whole lines go into `st`; the bytes after the last newline are `carry`
    let pos = from, carry: Buffer = Buffer.alloc(0), read = 0;
    while (pos < size) {
      const chunk = readAt(fd, pos, Math.min(CHUNK, size - pos));
      if (chunk.length === 0) break; // the file shrank under us: take what is there
      pos += chunk.length; read += chunk.length;
      const buf = carry.length ? Buffer.concat([carry, chunk]) : chunk;
      const k = cutAt(buf);
      if (k > 0) foldText(st, buf.toString("utf8", 0, k));
      carry = k < buf.length ? Buffer.from(buf.subarray(k)) : Buffer.alloc(0);
    }
    const offset = pos - carry.length;
    if (dir && (how === "full" || offset !== from)) {
      try {
        const n = Math.min(ANCHOR, offset);
        const anchor = n > 0 ? readAt(fd, offset - n, n).toString("hex") : "";
        const out: Saved = { schema: FOLD_SCHEMA, code, ino, offset, file, anchor, state: saveFold(st) };
        mkdirSync(dir, { recursive: true });
        const target = cacheFile(dir, file), tmp = `${target}.${process.pid}.tmp`;
        writeFileSync(tmp, JSON.stringify(out));
        renameSync(tmp, target);
      } catch { /* a cache that cannot be written is a cache miss next time */ }
    }
    // the unterminated tail counts in this pass's result but never in the saved state (Lean `pass_eq_full`)
    if (carry.length) {
      const tail = carry.toString("utf8");
      let parses = true;
      try { JSON.parse(tail); } catch { parses = false; } // a torn line changes nothing: no copy needed
      if (parses) {
        const view = loadFold(saveFold(st));
        if (view) { stepLine(view, tail); return { state: view, how, read }; }
        const whole = initFold(false); // cannot happen: the saved form always loads
        return { state: foldText(whole, readFileSync(file, "utf8")), how: "full", read: size };
      }
    }
    return { state: st, how, read };
  } finally { closeSync(fd); }
}

/** Delete cache files untouched for `maxAgeMs` (their transcripts left the window). */
export function sweepCache(dir: string, now: number, maxAgeMs = 7 * 86400_000): number {
  let n = 0;
  try {
    for (const f of readdirSync(dir)) {
      const p = join(dir, f);
      try { if (now - statSync(p).mtimeMs > maxAgeMs) { unlinkSync(p); n++; } } catch { /* gone */ }
    }
  } catch { /* none */ }
  return n;
}
