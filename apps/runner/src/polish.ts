import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative } from "node:path";
import { pathToFileURL } from "node:url";
import { UsageError, parseFlags } from "./lib.ts";
import { worktreeOf } from "./land.ts";
import { builtModules, noteSpan } from "./timing.ts";
import { coreCandidates, coreCaller, type CoreCall } from "./watch.ts";

export const POLISH_USAGE =
  "usage: fw polish plan --branch <b> --task <id>                     (classes and scopes of the branch diff against main)\n" +
  "       fw polish cuts --branch <b> --task <id> --cuts <file|-> [--apply yes]   (cuts: {cuts:[{path,old,new}]} or [...])\n" +
  "       fw polish commit --branch <b> --task <id> [--message <m>]     (commit kept edits; restore edits outside the branch's hunks; refuse when the main checkout is dirty in the plan's files; always end with a clean worktree: leftover edits restored, untracked files created since plan deleted)\n" +
  "       fw polish strays --branch <b> --task <id> --paths <file|->   (paths: {paths:[...]} or [...]; relative = under the main checkout; prints stray <path> for each edit outside <main>/.claude/worktrees/<name>/)\n" +
  "       fw polish --staged [--cuts <file|-> [--apply yes]]            (the staged files of this checkout, for the lead's commits)";

type Cls = { path: string; class: string; mark: string | null };
type Plan = { classes: Cls[]; stages: string[]; scopes: { comments: string[]; prose: string[] }; keep: string[]; restore: string[]; left?: string[]; protected?: string[] };
type CutOut = { path: string; old: string; verdict: string; missing: string[] };
type DocOut = { path: string; text: string; changed: boolean };

export interface Deps {
  core?: CoreCall;
  log?: (l: string) => void;
  stdin?: () => string;
  git?: (cwd: string, args: string[], input?: string) => string;
  read?: (path: string) => string | null;
  write?: (path: string, text: string) => void;
  gen?: (root: string) => Promise<string[]>;
  worktree?: (cwd: string, branch: string) => string | null;
  remove?: (path: string) => void;
  run?: (cwd: string, argv: string[]) => string | null;
  realpath?: (path: string) => string | null;
}

export const realRun = (cwd: string, argv: string[]): string | null => {
  const r = spawnSync(argv[0]!, argv.slice(1), { cwd, encoding: "utf8", maxBuffer: 64 << 20 });
  return r.status === 0 ? `${r.stdout ?? ""}${r.stderr ?? ""}` : null;
};

const realGit = (cwd: string, args: string[], input?: string) =>
  execFileSync("git", args, { cwd, encoding: "utf8", maxBuffer: 64 << 20, ...(input === undefined ? {} : { input }) });

type Hunk = { oldStart: number; oldLen: number; newStart: number; newLen: number; text: string };
type FileDiff = { path: string; header: string; hunks: Hunk[] };

const UNQUOTE: Record<string, string> = { n: "\n", t: "\t", "\"": "\"", "\\": "\\" };
/** The path of a `--- a/x` or `+++ b/x` side: unquoted when git quoted it, minus the trailing tab git adds after a path with a space; `/dev/null` gives null. */
function headerPath(raw: string): string | null {
  let s = raw.replace(/\t.*$/, "");
  if (s === "/dev/null") return null;
  if (s.startsWith('"') && s.endsWith('"')) {
    const bytes: number[] = [];
    const inner = s.slice(1, -1);
    for (let i = 0; i < inner.length; i++) {
      const c = inner[i]!;
      if (c !== "\\") { bytes.push(...Buffer.from(c)); continue; }
      const n = inner[++i]!;
      if (/[0-7]/.test(n)) { bytes.push(parseInt(inner.slice(i, i + 3), 8)); i += 2; } else bytes.push(...Buffer.from(UNQUOTE[n] ?? n));
    }
    s = Buffer.from(bytes).toString("utf8");
  }
  return s.replace(/^[ab]\//, "");
}

/** Reads `git diff -U0` text into files and hunks. TS glue: the rule that decides which hunk stays is Lean `Fw.Plan.Polish.admitted`. */
export function parseDiff(text: string): FileDiff[] {
  const files: FileDiff[] = [];
  let cur: FileDiff | null = null;
  let hunk: string[] | null = null;
  const flush = () => {
    if (cur && hunk) {
      const m = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(hunk[0]!)!;
      cur.hunks.push({ oldStart: +m[1]!, oldLen: m[2] === undefined ? 1 : +m[2], newStart: +m[3]!, newLen: m[4] === undefined ? 1 : +m[4], text: hunk.join("\n") });
    }
    hunk = null;
  };
  for (const l of text.split("\n")) {
    if (l.startsWith("diff --git ")) {
      flush();
      cur = { path: l, header: l, hunks: [] };
      files.push(cur);
    } else if (l.startsWith("@@") && cur) { flush(); hunk = [l]; }
    else if (hunk) hunk.push(l);
    else if (cur) {
      cur.header += `\n${l}`;
      const side = /^(\+\+\+|---) (.*)$/.exec(l);
      if (side && (side[1] === "+++" || cur.path.startsWith("diff --git "))) {
        const p = headerPath(side[2]!);
        if (p !== null) cur.path = p;
      }
    }
  }
  flush();
  return files.map((f) => ({ ...f, hunks: f.hunks.map((h) => ({ ...h, text: h.text.replace(/\n+$/, "") })) }));
}

const porcelainPaths = (s: string) => s.split("\n").filter((l) => l.length > 3).map((l) => l.slice(3).split(" -> ").pop()!.replace(/^"|"$/g, ""));
const spansOf = (fs: FileDiff[], side: "old" | "new") =>
  fs.map((f) => ({ path: f.path, spans: f.hunks.map((h) => (side === "old" ? { start: h.oldStart, len: h.oldLen } : { start: h.newStart, len: h.newLen })) }));
type HunkOut = { ranges: { path: string; ranges: { lo: number; hi: number }[] }[]; edits: { path: string; pathOk: boolean; kept: boolean[] }[]; blocked: string[] };
const realRead = (p: string) => { try { return readFileSync(p, "utf8"); } catch { return null; } };

export async function genOutputs(root: string): Promise<string[]> {
  const m = await import(pathToFileURL(join(root, "scripts/ci-paths.mjs")).href);
  const { table } = m.loadGolden(root) as { table: { workflows: { file: string }[] } };
  return [...table.workflows.map((w) => `.github/workflows/${w.file}`), m.LAKE_GEN as string];
}

export async function genOwned(gen: (root: string) => Promise<string[]>, root: string, dir: string): Promise<string[]> {
  const base = await gen(root);
  if (dir === root) return base;
  return [...new Set([...base, ...(await gen(dir))])];
}

const lines = (s: string) => s.split("\n").map((l) => l.trim()).filter((l) => l !== "");

function coreOf(cwd: string, deps: Deps, git: NonNullable<Deps["git"]>): CoreCall {
  if (deps.core) return deps.core;
  const root = git(cwd, ["rev-parse", "--show-toplevel"]).trim();
  const common = git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]).trim();
  return coreCaller(coreCandidates(root, join(common, "..")));
}

const realPath = (p: string): string | null => { try { return realpathSync.native(p); } catch { return null; } };

export function resolveFacts(abs: string, real: (p: string) => string | null): { path: string; resolved: boolean } {
  if (abs.split("/").some((s) => s === ".." || s === ".")) return { path: abs, resolved: true };
  let head = abs;
  let tail = "";
  for (;;) {
    const r = real(head);
    if (r !== null) return { path: r === "/" ? `/${tail}`.replace(/\/$/, "") || "/" : tail ? `${r}/${tail}` : r, resolved: true };
    const i = head.lastIndexOf("/");
    if (i <= 0) return { path: abs, resolved: false };
    tail = tail ? `${head.slice(i + 1)}/${tail}` : head.slice(i + 1);
    head = head.slice(0, i);
  }
}

async function straysCli(flags: Record<string, string | undefined>, cwd: string, deps: Deps, out: (l: string) => void, git: NonNullable<Deps["git"]>): Promise<number> {
  const task = flags.task!;
  const real = deps.realpath ?? realPath;
  try {
    const raw = readJson(flags.paths!, deps);
    const list = Array.isArray(raw) ? raw : (raw as { paths?: unknown }).paths;
    if (!Array.isArray(list) || !list.every((p) => typeof p === "string")) throw new UsageError("--paths: expected {paths:[...]} or an array of strings");
    const common = git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]).trim();
    const main = real(join(common, ".."));
    if (!main) throw new Error(`main checkout ${join(common, "..")} does not resolve`);
    const dir = (deps.worktree ?? worktreeOf)(cwd, flags.branch!);
    if (!dir) throw new Error(`no worktree has branch ${flags.branch}`);
    const call = coreOf(cwd, deps, git);
    const name = ((await call({ op: "plan.wtName", dir: real(dir) ?? dir })) as { name?: string | null }).name;
    if (typeof name !== "string") throw new Error(`worktree ${dir} is not a .claude/worktrees/<name> directory`);
    out(`main ${main}`);
    out(`worktree-name ${name}`);
    let n = 0;
    for (const p of list as string[]) {
      const { path, resolved } = resolveFacts(isAbsolute(p) ? p : `${main}/${p}`, real);
      const r = (await call({ op: "plan.inWt", main, name, path, resolved })) as { verdict?: unknown; own?: unknown };
      if (typeof r.own !== "boolean") throw new Error(`fwcore: no plan.inWt verdict (${JSON.stringify(r).slice(0, 200)})`);
      if (!r.own) { n++; out(`stray ${p}`); out(`  ${String(r.verdict)} ${path}`); }
    }
    out(`VERDICT polish-strays ${task} ${n ? "strays" : "clean"}`);
    return n ? 1 : 0;
  } catch (e) {
    if (e instanceof UsageError) throw e;
    out(`  ${e instanceof Error ? e.message : String(e)}`);
    out(`VERDICT polish-strays ${task} error`);
    return 1;
  }
}

function readJson(src: string, deps: Deps): unknown {
  const text = src === "-" ? (deps.stdin ?? (() => readFileSync(0, "utf8")))() : readFileSync(src, "utf8");
  try { return JSON.parse(text); } catch (e) { throw new UsageError(`--cuts: not JSON (${e instanceof Error ? e.message : e})`); }
}

export type Checks = { n: number; kinds: string[] };
type StagedCmd = { check?: unknown; cwd?: unknown; argv?: unknown };

/** The checkmap commands the pre-commit hook runs on the index of `dir` (`scripts/checkmap.mjs --staged`, asked of
 *  `ops.checkMap`); null when fwcore gives no command list. */
async function stagedCmds(dir: string, git: (cwd: string, args: string[]) => string, call: CoreCall): Promise<StagedCmd[] | null> {
  const z = (t: string) => t.split("\0").filter(Boolean);
  const listed = z(git(dir, ["diff", "--cached", "--no-renames", "--name-only", "-z", "--diff-filter=ACMR"]));
  const deleted = z(git(dir, ["diff", "--cached", "--no-renames", "--name-only", "-z", "--diff-filter=D"]));
  const paths = listed.filter((f) => existsSync(join(dir, f)));
  const gone = listed.filter((f) => !existsSync(join(dir, f)));
  try {
    const m = await call({ op: "ops.checkMap", paths, deleted: [...deleted, ...gone] });
    return Array.isArray(m.cmds) ? (m.cmds as StagedCmd[]) : null;
  } catch { return null; }
}

export const NO_CHECKS: Checks = { n: 0, kinds: [] };

const checksOf = (cmds: StagedCmd[]): Checks =>
  ({ n: cmds.length, kinds: [...new Set(cmds.map((c) => c.check).filter((k): k is string => typeof k === "string"))].sort() });

/** The count and sorted kinds of the staged checkmap commands; null when fwcore gives no command list. */
export async function stagedChecks(dir: string, git: (cwd: string, args: string[]) => string, call: CoreCall): Promise<Checks | null> {
  const cmds = await stagedCmds(dir, git, call);
  return cmds ? checksOf(cmds) : null;
}

export async function stagedSpan(dir: string, git: (cwd: string, args: string[]) => string, call: CoreCall,
  run: (cwd: string, argv: string[]) => string | null): Promise<{ checks: Checks; lake?: { built: number } } | null> {
  const cmds = await stagedCmds(dir, git, call);
  if (!cmds) return null;
  const lake = cmds.find((c) => c.check === "lakeBuild" && typeof c.cwd === "string" && Array.isArray(c.argv) && c.argv.length > 0);
  if (!lake) return { checks: checksOf(cmds) };
  const out = run(join(dir, lake.cwd as string), lake.argv as string[]);
  return out === null ? { checks: checksOf(cmds) } : { checks: checksOf(cmds), lake: { built: builtModules(out) } };
}

const BASELINE = "fw-polish-untracked";
const DIRTY_BASELINE = "fw-polish-dirty";
type Git = NonNullable<Deps["git"]>;

const untrackedOf = (dir: string, git: Git) => lines(git(dir, ["-c", "core.quotePath=false", "ls-files", "--others", "--exclude-standard"]));
const dirtyOf = (dir: string, git: Git) => lines(git(dir, ["-c", "core.quotePath=false", "diff", "--name-only", "HEAD"]));

/** Writes the untracked files and the tracked dirty paths present before the polish stage (read by `settleTree` and the commit step). TS glue. */
function saveBaseline(dir: string, git: Git, write: NonNullable<Deps["write"]>, dirty: string[]): void {
  const gd = git(dir, ["rev-parse", "--absolute-git-dir"]).trim();
  write(join(gd, BASELINE), untrackedOf(dir, git).join("\n") + "\n");
  write(join(gd, DIRTY_BASELINE), dirty.join("\n") + "\n");
}

/** One `-U0` hunk of the polish edits for `walkHunks`: the TS stand-in of Lean `Fw.Plan.Polish.WHunk`, replayed against the `plan.polishWalk` goldens. */
export type WHunk = { target: number; oldLen: number; new: string[]; keep: boolean };

/** HEAD lines with exactly the kept hunks applied (Lean `Fw.Plan.Polish.walk`: `walk_restored`, `walk_skip_restored`). TS stand-in. */
export function walkHunks(head: string[], hunks: WHunk[]): string[] {
  const out: string[] = [];
  let at = 0;
  for (const h of hunks) {
    const skip = Math.max(h.target - at, 0);
    out.push(...head.slice(at, at + skip));
    out.push(...(h.keep ? h.new : head.slice(at + skip, at + skip + h.oldLen)));
    at += skip + h.oldLen;
  }
  out.push(...head.slice(at));
  return out;
}

/** The file text after the kept hunks of `file` are applied to its HEAD text; null when a hunk has a no-newline marker (the caller restores the whole file). */
export function keptText(headText: string, file: FileDiff, kept: boolean[]): string | null {
  const hunks: WHunk[] = [];
  for (const [i, h] of file.hunks.entries()) {
    const body = h.text.split("\n").slice(1);
    if (body.some((l) => l.startsWith("\\"))) return null;
    hunks.push({ target: h.oldLen === 0 ? h.oldStart : h.oldStart - 1, oldLen: h.oldLen, new: body.filter((l) => l.startsWith("+")).map((l) => l.slice(1)), keep: kept[i] === true });
  }
  return walkHunks(headText.split("\n"), hunks).join("\n");
}

/** Leaves the polish worktree as the builder left it at plan time, whatever the commit step did: only paths outside the
 *  `fw polish plan` baseline are touched (tracked dirty ones restored from HEAD, new untracked ones deleted), then both
 *  baseline files are deleted. Which paths is Lean `Fw.Plan.Polish.settle`; with fwcore down, the non-baseline dirty paths
 *  are restored and nothing is deleted (TS stand-in); without a dirty baseline nothing is restored (fail closed). Returns one report line. */
export async function settleTree(dir: string, git: Git, call: CoreCall | null, read: NonNullable<Deps["read"]>, remove: (p: string) => void): Promise<string> {
  const gd = git(dir, ["rev-parse", "--absolute-git-dir"]).trim();
  const base = read(join(gd, BASELINE));
  const dirtyBase = read(join(gd, DIRTY_BASELINE));
  const dirty = dirtyOf(dir, git);
  const untracked = untrackedOf(dir, git);
  const before = base === null ? untracked : lines(base);
  let restore = dirtyBase === null ? [] : dirty.filter((p) => !lines(dirtyBase).includes(p));
  let rm: string[] = [];
  let note = dirtyBase !== null && restore.length < dirty.length ? `; ${dirty.length - restore.length} path(s) were dirty before plan and kept` : "";
  note += base === null ? "; no baseline from fw polish plan, untracked files kept" : "";
  try {
    if (!call) throw new Error("no fwcore");
    const r = await call({ op: "plan.polishSettle", before, dirtyBefore: dirtyBase === null ? [] : lines(dirtyBase), dirty, untracked });
    if (!Array.isArray(r.restore) || !Array.isArray(r.remove)) throw new Error("no settle verdict");
    restore = dirtyBase === null ? [] : r.restore as string[]; rm = base === null ? [] : r.remove as string[];
  } catch (e) { note += `; Lean settle unavailable (${e instanceof Error ? e.message : e}), restored the non-baseline dirty paths`; }
  if (restore.length) git(dir, ["checkout", "HEAD", "--", ...restore]);
  for (const p of rm) remove(join(dir, p));
  remove(join(gd, BASELINE));
  remove(join(gd, DIRTY_BASELINE));
  const left = dirtyOf(dir, git).length + untrackedOf(dir, git).filter((p) => !before.includes(p)).length;
  return `cleanup: restored ${restore.length}${restore.length ? ` (${restore.join(" ")})` : ""}, removed ${rm.length}${rm.length ? ` (${rm.join(" ")})` : ""}, worktree ${left === 0 ? "clean" : `NOT clean (${left} paths)`}${note}`;
}

function coreSafe(cwd: string, deps: Deps, git: Git): CoreCall | null {
  try { return coreOf(cwd, deps, git); } catch { return null; }
}

export const POLISH_VERBS = ["plan", "cuts", "commit", "staged", "strays"] as const;

export async function polishCli(argv: string[], cwd: string, deps: Deps = {}): Promise<number> {
  const out = deps.log ?? ((l: string) => console.log(l));
  const git = deps.git ?? realGit;
  const read = deps.read ?? realRead;
  const write = deps.write ?? ((p: string, t: string) => writeFileSync(p, t));
  const remove = deps.remove ?? ((p: string) => rmSync(p, { force: true }));
  let settleDir: string | null = null;
  let settled: (d: string) => Promise<void> = async () => {};
  const [verb0, ...rest] = argv;
  const verb = verb0 === "--staged" ? "staged" : verb0;
  if (!(POLISH_VERBS as readonly string[]).includes(verb ?? "")) throw new UsageError(POLISH_USAGE);
  const { flags } = parseFlags(rest);
  const staged = verb === "staged";
  if (!staged && (!flags.branch || !flags.task)) throw new UsageError(POLISH_USAGE);
  if (verb === "cuts" && !flags.cuts) throw new UsageError(POLISH_USAGE);
  if (verb === "strays") {
    if (!flags.paths) throw new UsageError(POLISH_USAGE);
    return straysCli(flags, cwd, deps, out, git);
  }
  const task = staged ? "staged" : flags.task!;
  const kind = verb === "commit" ? "polish-commit" : verb === "cuts" || flags.cuts ? "polish-cuts" : "polish-plan";
  try {
    const root = git(cwd, ["rev-parse", "--show-toplevel"]).trim();
    const dir = staged ? root : (deps.worktree ?? worktreeOf)(cwd, flags.branch!);
    if (!dir) throw new Error(`no worktree has branch ${flags.branch}`);
    let dirtyBefore: string[] = [];
    if (verb === "commit") {
      const gd0 = git(dir, ["rev-parse", "--absolute-git-dir"]).trim();
      const dtext = read(join(gd0, DIRTY_BASELINE));
      if (dtext === null || read(join(gd0, BASELINE)) === null) {
        out("no baseline from fw polish plan");
        out(`VERDICT polish-commit ${task} refused`);
        return 1;
      }
      dirtyBefore = lines(dtext);
      settleDir = dir;
    } else if (!staged && kind === "polish-plan") dirtyBefore = dirtyOf(dir, git);
    else if (!staged) dirtyBefore = lines(read(join(git(dir, ["rev-parse", "--absolute-git-dir"]).trim(), DIRTY_BASELINE)) ?? "");
    const paths = lines(staged ? git(dir, ["-c", "core.quotePath=false", "diff", "--cached", "--name-only"]) : git(dir, ["-c", "core.quotePath=false", "diff", "--name-only", `main...${flags.branch}`]));
    const heads = paths.map((p) => ({ path: p, head: (read(join(dir, p)) ?? "").split("\n", 1)[0]!.slice(0, 300) }));
    const gen = await genOwned(deps.gen ?? genOutputs, root, dir);
    const call = coreOf(cwd, deps, git);
    settled = async (d: string) => out(await settleTree(d, git, call, read, remove));
    const edited = verb === "commit" ? lines(git(dir, ["-c", "core.quotePath=false", "diff", "--name-only", "HEAD"])) : [];
    const plan = (await call({ op: "plan.polishPlan", gen, heads, paths, edited, dirtyBefore })) as unknown as Plan;
    if (!Array.isArray(plan.classes)) throw new Error(`fwcore: no plan (${JSON.stringify(plan).slice(0, 200)})`);
    const diffArgs = staged ? ["-c", "core.quotePath=false", "diff", "--cached", "-U0", "--no-color", "--no-ext-diff"] : ["-c", "core.quotePath=false", "diff", "-U0", "--no-color", "--no-ext-diff", `main...${flags.branch}`];
    const branchDiff = parseDiff(git(dir, diffArgs));
    const mainDir = staged ? dir : join(git(dir, ["rev-parse", "--path-format=absolute", "--git-common-dir"]).trim(), "..");
    const dirty = verb === "commit" && mainDir !== dir ? porcelainPaths(git(mainDir, ["-c", "core.quotePath=false", "--literal-pathspecs", "status", "--porcelain", "--", ...paths])) : [];
    const editDiff = verb === "commit" ? parseDiff(git(dir, ["-c", "core.quotePath=false", "diff", "-U0", "--no-color", "--no-ext-diff", "HEAD"])) : [];
    const hk = (await call({ op: "plan.polishHunks", diff: spansOf(branchDiff, "new"), edits: spansOf(editDiff, "old"), main: dirty })) as unknown as HunkOut;
    if (!Array.isArray(hk.ranges)) throw new Error(`fwcore: no hunk verdicts (${JSON.stringify(hk).slice(0, 200)})`);
    if (verb === "commit") {
      if (hk.blocked.length) {
        out(`the main checkout has uncommitted edits in the plan's files: ${hk.blocked.join(" ")}`);
        await settled(dir);
        out(`VERDICT polish-commit ${task} refused`);
        return 1;
      }
      for (const p of plan.left ?? []) out(`left ${p} (dirty before fw polish plan, not the polish stage's)`);
      if (plan.restore.length) { git(dir, ["checkout", "HEAD", "--", ...plan.restore]); out(`restored ${plan.restore.join(" ")}`); }
      const clsOf = new Map(plan.classes.map((c) => [c.path, c.class]));
      const keep: string[] = [];
      for (const path of plan.keep) {
        const ed = hk.edits.find((e) => e.path === path);
        const file = editDiff.find((f) => f.path === path);
        if (clsOf.get(path) === "prose") { keep.push(path); continue; }
        if (!ed || !file) { git(dir, ["checkout", "HEAD", "--", path]); out(`restored ${path} (no edit record)`); continue; }
        const bad = file.hunks.map((h, i) => ({ h, i })).filter(({ i }) => !ed.pathOk || ed.kept[i] !== true);
        if (!file.hunks.length || bad.length === file.hunks.length) { git(dir, ["checkout", "HEAD", "--", path]); out(`restored ${path} (outside the branch's hunks)`); continue; }
        if (bad.length) {
          const text = keptText(git(dir, ["show", `HEAD:${path}`]), file, file.hunks.map((_, i) => !bad.some((b) => b.i === i)));
          if (text === null) { git(dir, ["checkout", "HEAD", "--", path]); out(`restored ${path} (a hunk has a no-newline marker)`); continue; }
          write(join(dir, path), text);
          for (const { h } of bad) out(`restored ${path}:${h.oldStart}-${h.oldStart + Math.max(h.oldLen, 1) - 1} (outside the branch's hunks)`);
        }
        keep.push(path);
      }
      if (!keep.length) { noteSpan("fw", "polish commit", { checks: NO_CHECKS }); await settled(dir); out(`VERDICT polish-commit ${task} nothing`); return 0; }
      git(dir, ["add", "--", ...keep]);
      const fields = await stagedSpan(dir, git, call, deps.run ?? realRun);
      if (fields) noteSpan("fw", "polish commit", fields);
      git(dir, ["commit", "-q", "-m", flags.message ?? `polish ${task}: comment and prose cuts (fw polish)`, "--", ...keep]);
      out(`kept ${keep.join(" ")}`);
      await settled(dir);
      out(`VERDICT polish-commit ${task} committed`);
      return 0;
    }
    if (kind === "polish-plan") {
      if (!staged) saveBaseline(dir, git, write, dirtyBefore);
      out(`worktree ${dir}`);
      out(`worktree-name ${((await call({ op: "plan.wtName", dir })) as { name?: string | null }).name ?? "-"}`);
      for (const p of paths.filter((q) => dirtyBefore.includes(q))) out(`skip ${p} (dirty before plan)`);
      for (const p of plan.protected ?? []) out(`skip ${p} (protected)`);
      for (const c of plan.classes) out(`class ${c.class} ${c.mark ?? "-"} ${c.path}`);
      const rangeOf = (p: string) => (hk.ranges.find((r) => r.path === p)?.ranges ?? []).map((r) => `${r.lo}-${r.hi}`).join(",") || "none";
      for (const c of plan.classes.filter((c) => plan.scopes.comments.includes(c.path))) out(`comments ${c.mark ?? "-"} ${c.path} lines ${rangeOf(c.path)}`);
      for (const p of plan.scopes.prose) out(`prose ${p}`);
      if (staged && plan.stages.length) out("next: spawn comment-sicko on the comments lines and slop-checker on the prose lines; judge its cuts with fw polish --staged --cuts <file>");
      out(`VERDICT polish-plan ${task} ${plan.stages.length ? plan.stages.join(",") : "none"}`);
      return 0;
    }
    const raw = readJson(flags.cuts!, deps);
    const list = (Array.isArray(raw) ? raw : (raw as { cuts?: unknown }).cuts) as { path: string; old: string; new: string }[];
    if (!Array.isArray(list)) throw new UsageError("--cuts: expected {cuts:[{path,old,new}]} or an array");
    const cuts = list.map((c) => ({ path: isAbsolute(c.path) ? relative(dir, c.path) : c.path, old: String(c.old), new: String(c.new) }));
    const docs = plan.scopes.prose.map((p) => ({ path: p, text: read(join(dir, p)) ?? "" }));
    const r = (await call({ op: "plan.polishCuts", gen, heads, docs, cuts })) as unknown as { cuts: CutOut[]; docs: DocOut[] };
    if (!Array.isArray(r.cuts)) throw new Error(`fwcore: no cut verdicts (${JSON.stringify(r).slice(0, 200)})`);
    for (const c of r.cuts) out(`cut ${c.verdict} ${c.path} ${JSON.stringify(c.old.slice(0, 60))}${c.missing.length ? ` missing ${c.missing.join(" ")}` : ""}`);
    const changed = r.docs.filter((d) => d.changed);
    const apply = flags.apply === "yes";
    if (apply) {
      for (const d of changed) write(join(dir, d.path), d.text);
      if (staged && changed.length) git(dir, ["add", "--", ...changed.map((d) => d.path)]);
    }
    const n = r.cuts.filter((c) => c.verdict === "apply").length;
    out(`VERDICT polish-cuts ${task} ${apply ? "applied" : "judged"} ${n}/${r.cuts.length}`);
    return 0;
  } catch (e) {
    if (e instanceof UsageError) throw e;
    out(`  ${e instanceof Error ? e.message : String(e)}`);
    if (settleDir) {
      try { out(await settleTree(settleDir, git, coreSafe(cwd, deps, git), read, remove)); }
      catch (e2) { out(`cleanup failed: ${e2 instanceof Error ? e2.message : String(e2)}; the lead restores the worktree ${settleDir}`); }
    }
    out(`VERDICT ${kind} ${task} error`);
    return 1;
  }
}
