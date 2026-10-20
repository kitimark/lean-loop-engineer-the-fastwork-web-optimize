// fw lake-gc (tasks lean-bin-slim, lake-gc-refs): which files of the Lake artifact cache no checkout names and no live
// Lake writer may own. This file only gathers facts and prints or deletes; the list, its basis and the budget verdict
// are Lean (`fwcore` op ops.lakeGc, lean/Fw/Ops/LakeGc.lean, golden packages/contracts/golden/ops/lakegc.jsonl).
// Docs: docs/team/tools/lake-gc.md.
import { spawnSync } from "node:child_process";
import { lstatSync, readdirSync, readFileSync, unlinkSync } from "node:fs";
import { dirname, join } from "node:path";

export const LAKE_GC_USAGE =
  "usage: fw lake-gc [--list | --json | --delete] [--check] [--age-floor <seconds>] [--root <cache>/artifacts]\n" +
  "  (no flag)  summary                              --list    the listed paths, one per line\n" +
  "  --json     the Lean reply                       --delete  delete exactly the listed paths (user-approved runs only)\n" +
  "  --check    exit 1 when the cache is over the Lean budget";

export type Fact = { name: string; file: boolean; links: number; mtime: number; ctime: number; size: number };
export type Checkout = { path: string; refs: string[] };
export type Proc = { pid: number; start: number; exe: string; args: string; cwd: string | null };
export type LakeGcReply = {
  rootOk: boolean; paths: string[]; listed: number; listBytes: number; cacheBytes: number; files: number;
  ageFloor: number; budget: number; alert: boolean; basis: "identity" | "ageFloor"; fallback: string | null;
  ageListed: number; ageListBytes: number; writers: { pid: number; start: number; checkout: string | null }[];
  checkouts: { path: string; entries: number; bytes: number }[];
};
export type LakeGcArgs = { mode: "summary" | "list" | "json" | "delete"; check: boolean; ageFloor?: number; root?: string };
export type Call = (req: Record<string, unknown>) => Record<string, unknown>;
export type Gathered = { files: Fact[]; checkouts: Checkout[] | null; procs: Proc[] | null; outputs: () => string[] | null };

export class LakeGcUsage extends Error {}

export function parseLakeGcArgs(argv: string[]): LakeGcArgs {
  const a: LakeGcArgs = { mode: "summary", check: false };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--list") a.mode = "list";
    else if (x === "--json") a.mode = "json";
    else if (x === "--delete") a.mode = "delete";
    else if (x === "--check") a.check = true;
    else if (x === "--age-floor" && /^\d+$/.test(argv[i + 1] ?? "")) a.ageFloor = Number(argv[++i]);
    else if (x === "--root" && argv[i + 1]) a.root = argv[++i];
    else throw new LakeGcUsage(`unknown or incomplete argument: ${x}\n${LAKE_GC_USAGE}`);
  }
  return a;
}

/** The artifacts dir of the cache Lake uses for `lean/` (Lake sets LAKE_CACHE_DIR in `lake env`,
 *  Lake/Config/Env.lean:310@v4.35.0). */
export function artifactsRoot(top: string): string {
  const r = spawnSync("lake", ["env", "printenv", "LAKE_CACHE_DIR"], { cwd: join(top, "lean"), encoding: "utf8" });
  const dir = (r.stdout ?? "").trim();
  if (r.status !== 0 || !dir) throw new Error(`lake env printenv LAKE_CACHE_DIR failed in lean/: ${(r.stderr ?? "").trim()}`);
  return join(dir, "artifacts");
}

const secs = (ms: number) => Math.floor(ms / 1000);

/** One fact per entry of `root` (lstat: a symlink is not a file); an entry that vanished meanwhile is skipped. */
export function gatherFacts(root: string): Fact[] {
  const out: Fact[] = [];
  for (const name of readdirSync(root)) {
    try {
      const s = lstatSync(join(root, name));
      out.push({ name, file: s.isFile(), links: s.nlink, mtime: secs(s.mtimeMs), ctime: secs(s.ctimeMs), size: s.size });
    } catch { /* removed between readdir and lstat */ }
  }
  return out;
}

const isMissing = (e: unknown) => (e as NodeJS.ErrnoException).code === "ENOENT" || (e as NodeJS.ErrnoException).code === "ENOTDIR";

function stringLeaves(j: unknown, out: string[]): void {
  if (typeof j === "string") out.push(j);
  else if (Array.isArray(j)) for (const x of j) stringLeaves(x, out);
  else if (j && typeof j === "object") for (const x of Object.values(j)) stringLeaves(x, out);
}

/** Every string the `outputs` of a Lake dir's `.trace` files hold: the cache entries a build of that checkout resolves
 *  and links (Lake/Build/Common.lean:73,182,546-558,698-706@v4.35.0). A trace that does not parse (being written) is
 *  skipped. */
export function lakeDirRefs(lakeDir: string): string[] {
  const out: string[] = [];
  let entries: string[];
  try { entries = readdirSync(lakeDir, { recursive: true, encoding: "utf8" }); } catch (e) { if (isMissing(e)) return out; throw e; }
  for (const rel of entries) {
    if (!rel.endsWith(".trace")) continue;
    let text: string;
    try { text = readFileSync(join(lakeDir, rel), "utf8"); } catch (e) { if (isMissing(e) || (e as NodeJS.ErrnoException).code === "EISDIR") continue; throw e; }
    try { stringLeaves((JSON.parse(text) as { outputs?: unknown }).outputs, out); } catch { /* partial trace */ }
  }
  return out;
}

function git(top: string, args: string[]): string | null {
  const r = spawnSync("git", args, { cwd: top, encoding: "utf8", maxBuffer: 1 << 26 });
  return r.status === 0 ? r.stdout : null;
}

/** Every checkout of the repository (`git worktree list`) with the refs of each tracked Lake project's `.lake`;
 *  `null` when git or a directory read fails. */
export function gatherCheckouts(top: string): Checkout[] | null {
  const list = git(top, ["worktree", "list", "--porcelain"]);
  const files = git(top, ["ls-files", "--", "*lakefile.toml", "*lakefile.lean"]);
  if (list === null || files === null) return null;
  const projects = [...new Set(files.split("\n").filter(Boolean).map((f) => dirname(f)))];
  const paths = list.split("\n").filter((l) => l.startsWith("worktree ")).map((l) => l.slice("worktree ".length));
  try {
    return paths.map((path) => ({ path, refs: [...new Set(projects.flatMap((p) => lakeDirRefs(join(path, p, ".lake"))))] }));
  } catch {
    return null;
  }
}

/** `ps` start times are local wall-clock strings (LC_ALL=C: "Tue Oct 20 02:59:44 2026"). */
function parseStart(s: string): number | null {
  const ms = Date.parse(s);
  return Number.isFinite(ms) ? secs(ms) : null;
}

/** The process table: pid, start, executable path (`comm`), argument line, cwd (lsof); `null` when `ps` fails or a
 *  start time does not parse. A process missing from the argument listing gets an empty line. */
export function gatherProcs(): Proc[] | null {
  const env = { ...process.env, LC_ALL: "C" };
  const a = spawnSync("ps", ["-axo", "pid=,lstart=,comm="], { encoding: "utf8", env, maxBuffer: 1 << 26 });
  const b = spawnSync("ps", ["-axo", "pid=,args="], { encoding: "utf8", env, maxBuffer: 1 << 26 });
  if (a.status !== 0 || b.status !== 0) return null;
  const args = new Map<number, string>();
  for (const l of b.stdout.split("\n")) {
    const m = /^\s*(\d+) (.*)$/.exec(l);
    if (m) args.set(Number(m[1]), m[2]!);
  }
  const cwd = new Map<number, string>();
  const c = spawnSync("lsof", ["-a", "-d", "cwd", "-Fpn"], { encoding: "utf8", maxBuffer: 1 << 26 });
  let pid = -1;
  for (const l of (c.stdout ?? "").split("\n")) {
    if (l.startsWith("p")) pid = Number(l.slice(1));
    else if (l.startsWith("n") && pid >= 0) cwd.set(pid, l.slice(1));
  }
  const out: Proc[] = [];
  for (const l of a.stdout.split("\n")) {
    const m = /^\s*(\d+)\s+(\S+\s+\S+\s+\d+\s+\d+:\d+:\d+\s+\d+)\s+(.*)$/.exec(l);
    if (!m) { if (l.trim()) return null; continue; }
    const start = parseStart(m[2]!);
    if (start === null) return null;
    const p = Number(m[1]);
    out.push({ pid: p, start, exe: m[3]!, args: args.get(p) ?? "", cwd: cwd.get(p) ?? null });
  }
  return out;
}

/** Every name in Lake's outputs map `<cache>/outputs/<scope>/<input hash>.json` (Lake/Config/Cache.lean:426-454@v4.35.0);
 *  `[]` when the map does not exist, `null` when a directory read fails. A file that does not parse is skipped. */
export function gatherOutputs(cacheDir: string): string[] | null {
  const dir = join(cacheDir, "outputs");
  const out: string[] = [];
  try {
    for (const rel of readdirSync(dir, { recursive: true, encoding: "utf8" })) {
      if (!rel.endsWith(".json")) continue;
      try { stringLeaves((JSON.parse(readFileSync(join(dir, rel), "utf8")) as { data?: unknown }).data, out); } catch { /* partial */ }
    }
  } catch (e) {
    return isMissing(e) ? [] : null;
  }
  return [...new Set(out)];
}

/** The facts of one run; the outputs map (seconds to read) is read only when Lean asks for it. */
export function gatherAll(top: string, root: string): Gathered {
  return { files: gatherFacts(root), checkouts: gatherCheckouts(top), procs: gatherProcs(), outputs: () => gatherOutputs(dirname(root)) };
}

const gb = (n: number) => (n / 1e9).toFixed(2);

/** The printed lines of a reply in `mode` (not `delete`). */
export function render(root: string, r: LakeGcReply, mode: LakeGcArgs["mode"]): string[] {
  if (mode === "json") return [JSON.stringify(r)];
  if (mode === "list") return r.paths;
  const lines = [
    `lake-gc: ${root}`,
    `  cache:  ${r.files} entries, ${gb(r.cacheBytes)} GB (budget ${gb(r.budget)} GB)${r.alert ? "  OVER BUDGET" : ""}`,
  ];
  if (!r.rootOk) return [...lines, "  root refused by Lean (not an absolute <...>/artifacts path of plain names): nothing listed"];
  const basis = r.basis === "identity" ? "identity (no checkout names them, no live Lake writer may own them)"
    : `age floor ${r.ageFloor} s (fallback: ${r.fallback})`;
  lines.push(`  basis:  ${basis}`);
  lines.push(`  writers: ${r.writers.length === 0 ? "none" : r.writers.map((w) => `${w.pid}${w.checkout ? ` in ${w.checkout}` : ""}`).join(", ")}`);
  const named = r.checkouts.filter((c) => c.entries > 0);
  lines.push(`  checkouts: ${r.checkouts.length}, ${named.length} name cache entries`);
  lines.push(`  listed: ${r.listed} files, ${gb(r.listBytes)} GB   (age rule alone: ${r.ageListed} files, ${gb(r.ageListBytes)} GB)`);
  if (r.listed > 0) lines.push("  to delete them (user-approved): pnpm -s fw lake-gc --delete");
  return lines;
}

/** Deletes exactly `paths` (the Lean list); returns the lines to print and whether every unlink worked. */
export function deletePaths(paths: string[]): { lines: string[]; ok: boolean } {
  let n = 0, bytes = 0, gone = 0;
  const errs: string[] = [];
  for (const p of paths) {
    try {
      const size = lstatSync(p).size;
      unlinkSync(p);
      n++; bytes += size;
    } catch (e) {
      if (isMissing(e)) gone++;
      else errs.push(`  ${p}: ${(e as Error).message}`);
    }
  }
  return { lines: [`lake-gc: deleted ${n} files, ${gb(bytes)} GB; ${gone} already gone; ${errs.length} failed`, ...errs], ok: errs.length === 0 };
}

/** `fw lake-gc`: gather, ask Lean, print or delete. Exit 1 with --check and an over-budget cache, or a failed unlink. */
export function lakeGcCli(argv: string[], top: string, call: Call, print: (s: string) => void = console.log,
  gather: (top: string, root: string) => Gathered = gatherAll): number {
  const a = parseLakeGcArgs(argv);
  const root = a.root ?? artifactsRoot(top);
  const g = gather(top, root);
  const req: Record<string, unknown> = { op: "ops.lakeGc", root, now: secs(Date.now()), files: g.files };
  if (g.checkouts !== null) req.checkouts = g.checkouts;
  if (g.procs !== null) req.procs = g.procs;
  if (a.ageFloor !== undefined) req.ageFloor = a.ageFloor;
  let r = call(req) as unknown as LakeGcReply;
  if (r.fallback === "noOutputsMap") {
    const outputs = g.outputs();
    if (outputs !== null) r = call({ ...req, outputs }) as unknown as LakeGcReply;
  }
  let ok = true;
  if (a.mode === "delete") {
    const d = deletePaths(r.paths);
    for (const l of d.lines) print(l);
    ok = d.ok;
  } else for (const l of render(root, r, a.mode)) print(l);
  return !ok || (a.check && r.alert) ? 1 : 0;
}
