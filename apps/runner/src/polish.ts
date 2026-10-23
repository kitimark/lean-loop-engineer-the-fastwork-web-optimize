import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative } from "node:path";
import { pathToFileURL } from "node:url";
import { UsageError, parseFlags } from "./lib.ts";
import { worktreeOf } from "./land.ts";
import { noteSpan } from "./timing.ts";
import { coreCandidates, coreCaller, type CoreCall } from "./watch.ts";

export const POLISH_USAGE =
  "usage: fw polish plan --branch <b> --task <id>                     (classes and scopes of the branch diff against main)\n" +
  "       fw polish cuts --branch <b> --task <id> --cuts <file|-> [--apply yes]   (cuts: {cuts:[{path,old,new}]} or [...])\n" +
  "       fw polish commit --branch <b> --task <id> [--message <m>]     (commit kept edits; restore edits outside the branch's hunks; refuse when the main checkout is dirty in the plan's files; always end with a clean worktree: leftover edits restored, untracked files created since plan deleted)\n" +
  "       fw polish --staged [--cuts <file|-> [--apply yes]]            (the staged files of this checkout, for the lead's commits)";

type Cls = { path: string; class: string; mark: string | null };
type Plan = { classes: Cls[]; stages: string[]; scopes: { comments: string[]; prose: string[] }; keep: string[]; restore: string[] };
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
}

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

function readJson(src: string, deps: Deps): unknown {
  const text = src === "-" ? (deps.stdin ?? (() => readFileSync(0, "utf8")))() : readFileSync(src, "utf8");
  try { return JSON.parse(text); } catch (e) { throw new UsageError(`--cuts: not JSON (${e instanceof Error ? e.message : e})`); }
}

export type Checks = { n: number; kinds: string[] };

/** The checkmap commands the pre-commit hook runs on the index of `dir` (`scripts/checkmap.mjs --staged`, asked of
 *  `ops.checkMap`): their count and sorted kinds; null when fwcore gives no command list. */
export async function stagedChecks(dir: string, git: (cwd: string, args: string[]) => string, call: CoreCall): Promise<Checks | null> {
  const z = (t: string) => t.split("\0").filter(Boolean);
  const listed = z(git(dir, ["diff", "--cached", "--no-renames", "--name-only", "-z", "--diff-filter=ACMR"]));
  const deleted = z(git(dir, ["diff", "--cached", "--no-renames", "--name-only", "-z", "--diff-filter=D"]));
  const paths = listed.filter((f) => existsSync(join(dir, f)));
  const gone = listed.filter((f) => !existsSync(join(dir, f)));
  try {
    const m = await call({ op: "ops.checkMap", paths, deleted: [...deleted, ...gone] });
    if (!Array.isArray(m.cmds)) return null;
    const cmds = m.cmds as { check?: unknown }[];
    return { n: cmds.length, kinds: [...new Set(cmds.map((c) => c.check).filter((k): k is string => typeof k === "string"))].sort() };
  } catch { return null; }
}

const BASELINE = "fw-polish-untracked";
type Git = NonNullable<Deps["git"]>;

const untrackedOf = (dir: string, git: Git) => lines(git(dir, ["-c", "core.quotePath=false", "ls-files", "--others", "--exclude-standard"]));
const dirtyOf = (dir: string, git: Git) => lines(git(dir, ["-c", "core.quotePath=false", "diff", "--name-only", "HEAD"]));

/** Writes the untracked files present before the polish stage (read by `settleTree`). TS glue. */
function saveBaseline(dir: string, git: Git, write: NonNullable<Deps["write"]>): void {
  const gd = git(dir, ["rev-parse", "--absolute-git-dir"]).trim();
  write(join(gd, BASELINE), untrackedOf(dir, git).join("\n") + "\n");
}

/** Leaves the polish worktree clean, whatever the commit step did: the index goes back to HEAD, every tracked path still
 *  differing from HEAD is restored and every untracked file not in the `fw polish plan` baseline is deleted. Which paths
 *  is Lean `Fw.Plan.Polish.settle`; with fwcore down, all dirty paths are restored and nothing is deleted (TS stand-in). Returns one report line. */
export async function settleTree(dir: string, git: Git, call: CoreCall | null, read: NonNullable<Deps["read"]>, remove: (p: string) => void): Promise<string> {
  const gd = git(dir, ["rev-parse", "--absolute-git-dir"]).trim();
  const base = read(join(gd, BASELINE));
  git(dir, ["reset", "-q"]);
  const dirty = dirtyOf(dir, git);
  const untracked = untrackedOf(dir, git);
  const before = base === null ? untracked : lines(base);
  let restore = dirty;
  let rm: string[] = [];
  let note = base === null ? "; no baseline from fw polish plan, untracked files kept" : "";
  try {
    if (!call) throw new Error("no fwcore");
    const r = await call({ op: "plan.polishSettle", before, dirty, untracked });
    if (!Array.isArray(r.restore) || !Array.isArray(r.remove)) throw new Error("no settle verdict");
    restore = r.restore as string[]; rm = r.remove as string[];
  } catch (e) { note += `; Lean settle unavailable (${e instanceof Error ? e.message : e}), restored all dirty paths`; }
  if (restore.length) git(dir, ["checkout", "HEAD", "--", ...restore]);
  for (const p of rm) remove(join(dir, p));
  const left = dirtyOf(dir, git).length + untrackedOf(dir, git).filter((p) => !before.includes(p)).length;
  return `cleanup: restored ${restore.length}${restore.length ? ` (${restore.join(" ")})` : ""}, removed ${rm.length}${rm.length ? ` (${rm.join(" ")})` : ""}, worktree ${left === 0 ? "clean" : `NOT clean (${left} paths)`}${note}`;
}

function coreSafe(cwd: string, deps: Deps, git: Git): CoreCall | null {
  try { return coreOf(cwd, deps, git); } catch { return null; }
}

export const POLISH_VERBS = ["plan", "cuts", "commit", "staged"] as const;

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
  const task = staged ? "staged" : flags.task!;
  const kind = verb === "commit" ? "polish-commit" : verb === "cuts" || flags.cuts ? "polish-cuts" : "polish-plan";
  try {
    const root = git(cwd, ["rev-parse", "--show-toplevel"]).trim();
    const dir = staged ? root : (deps.worktree ?? worktreeOf)(cwd, flags.branch!);
    if (!dir) throw new Error(`no worktree has branch ${flags.branch}`);
    if (verb === "commit") settleDir = dir;
    const paths = lines(staged ? git(dir, ["-c", "core.quotePath=false", "diff", "--cached", "--name-only"]) : git(dir, ["-c", "core.quotePath=false", "diff", "--name-only", `main...${flags.branch}`]));
    const heads = paths.map((p) => ({ path: p, head: (read(join(dir, p)) ?? "").split("\n", 1)[0]!.slice(0, 300) }));
    const gen = await genOwned(deps.gen ?? genOutputs, root, dir);
    const call = coreOf(cwd, deps, git);
    settled = async (d: string) => out(await settleTree(d, git, call, read, remove));
    const edited = verb === "commit" ? lines(git(dir, ["-c", "core.quotePath=false", "diff", "--name-only", "HEAD"])) : [];
    const plan = (await call({ op: "plan.polishPlan", gen, heads, paths, edited })) as unknown as Plan;
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
        for (const { h } of [...bad].sort((a, b) => b.h.newStart - a.h.newStart)) {
          git(dir, ["apply", "-R", "--unidiff-zero", "-"], `${file.header}\n${h.text}\n`);
          out(`restored ${path}:${h.oldStart}-${h.oldStart + Math.max(h.oldLen, 1) - 1} (outside the branch's hunks)`);
        }
        keep.push(path);
      }
      if (!keep.length) { await settled(dir); out(`VERDICT polish-commit ${task} nothing`); return 0; }
      git(dir, ["add", "--", ...keep]);
      const checks = await stagedChecks(dir, git, call);
      if (checks) noteSpan("fw", "polish commit", { checks });
      git(dir, ["commit", "-q", "-m", flags.message ?? `polish ${task}: comment and prose cuts (fw polish)`]);
      out(`kept ${keep.join(" ")}`);
      await settled(dir);
      out(`VERDICT polish-commit ${task} committed`);
      return 0;
    }
    if (kind === "polish-plan") {
      if (!staged) saveBaseline(dir, git, write);
      out(`worktree ${dir}`);
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
