import { execFileSync } from "node:child_process";
import { statSync } from "node:fs";
import { resolve } from "node:path";

const segs = (s: string): string[] => s.split("/").filter((x) => x !== "" && x !== ".");

export function segMatch(g: string, s: string): boolean {
  let gi = 0, si = 0, star = -1, mark = 0;
  while (si < s.length) {
    if (gi < g.length && g[gi] === "*") { star = gi++; mark = si; }
    else if (gi < g.length && g[gi] === s[si]) { gi++; si++; }
    else if (star >= 0) { gi = star + 1; si = ++mark; }
    else return false;
  }
  while (gi < g.length && g[gi] === "*") gi++;
  return gi === g.length;
}

function prefixMatch(g: string[], gi: number, p: string[], pi: number): boolean {
  if (gi === g.length) return true;
  if (g[gi] === "**") return prefixMatch(g, gi + 1, p, pi) || (pi < p.length && prefixMatch(g, gi, p, pi + 1));
  return pi < p.length && segMatch(g[gi]!, p[pi]!) && prefixMatch(g, gi + 1, p, pi + 1);
}

export type Scope = (path: string) => boolean;

export function compileScope(globs: string[]): Scope {
  const incl = globs.filter((g) => !g.startsWith("!")).map(segs).filter((g) => g.length > 0);
  const excl = globs.filter((g) => g.startsWith("!")).map((g) => segs(g.slice(1))).filter((g) => g.length > 0);
  return (path) => {
    const p = segs(path);
    return p.length > 0 && !p.includes("..") && incl.some((g) => prefixMatch(g, 0, p, 0)) && !excl.some((g) => prefixMatch(g, 0, p, 0));
  };
}

const compiled = new Map<string, Scope>();
export function scopeOf(globs: string[]): Scope {
  const key = globs.join("\0");
  let s = compiled.get(key);
  if (!s) {
    if (compiled.size >= 512) compiled.clear();
    s = compileScope(globs);
    compiled.set(key, s);
  }
  return s;
}

export function inScope(globs: string[], path: string): boolean {
  return scopeOf(globs)(path);
}

const listings = new Map<string, { sig: string; files: string[] }>();
const indexPaths = new Map<string, string | null>();

function indexSig(root: string): string | null {
  if (process.env.GIT_INDEX_FILE) return null;
  let p = indexPaths.get(root);
  if (p === undefined) {
    try { p = resolve(root, execFileSync("git", ["rev-parse", "--git-path", "index"], { cwd: root, encoding: "utf8" }).trim()); } catch { p = null; }
    indexPaths.set(root, p);
  }
  if (p === null) return null;
  try { const s = statSync(p, { bigint: true }); return `${s.ino}:${s.size}:${s.mtimeNs}`; } catch { return null; }
}

export function trackedFiles(root: string): string[] {
  const sig = indexSig(root);
  const hit = sig === null ? undefined : listings.get(root);
  if (hit && hit.sig === sig) return hit.files;
  const files = execFileSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8" }).split("\0").filter(Boolean);
  if (sig !== null) listings.set(root, { sig, files });
  return files;
}
