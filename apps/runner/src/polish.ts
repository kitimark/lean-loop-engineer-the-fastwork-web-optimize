import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative } from "node:path";
import { pathToFileURL } from "node:url";
import { UsageError, parseFlags } from "./lib.ts";
import { worktreeOf } from "./land.ts";
import { coreCandidates, coreCaller, type CoreCall } from "./watch.ts";

export const POLISH_USAGE =
  "usage: fw polish plan --branch <b> --task <id>                     (classes and scopes of the branch diff against main)\n" +
  "       fw polish cuts --branch <b> --task <id> --cuts <file|-> [--apply yes]   (cuts: {cuts:[{path,old,new}]} or [...])\n" +
  "       fw polish commit --branch <b> --task <id> [--message <m>]     (commit kept edits, restore the rest)\n" +
  "       fw polish --staged [--cuts <file|-> [--apply yes]]            (the staged files of this checkout, for the lead's commits)";

type Cls = { path: string; class: string; mark: string | null };
type Plan = { classes: Cls[]; stages: string[]; scopes: { comments: string[]; prose: string[] }; keep: string[]; restore: string[] };
type CutOut = { path: string; old: string; verdict: string; missing: string[] };
type DocOut = { path: string; text: string; changed: boolean };

export interface Deps {
  core?: CoreCall;
  log?: (l: string) => void;
  stdin?: () => string;
  git?: (cwd: string, args: string[]) => string;
  read?: (path: string) => string | null;
  write?: (path: string, text: string) => void;
  gen?: (root: string) => Promise<string[]>;
  worktree?: (cwd: string, branch: string) => string | null;
}

const realGit = (cwd: string, args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8", maxBuffer: 64 << 20 });
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

export const POLISH_VERBS = ["plan", "cuts", "commit", "staged"] as const;

export async function polishCli(argv: string[], cwd: string, deps: Deps = {}): Promise<number> {
  const out = deps.log ?? ((l: string) => console.log(l));
  const git = deps.git ?? realGit;
  const read = deps.read ?? realRead;
  const write = deps.write ?? ((p: string, t: string) => writeFileSync(p, t));
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
    const paths = lines(staged ? git(dir, ["diff", "--cached", "--name-only"]) : git(dir, ["diff", "--name-only", `main...${flags.branch}`]));
    const heads = paths.map((p) => ({ path: p, head: (read(join(dir, p)) ?? "").split("\n", 1)[0]!.slice(0, 300) }));
    const gen = await genOwned(deps.gen ?? genOutputs, root, dir);
    const call = coreOf(cwd, deps, git);
    const edited = verb === "commit" ? lines(git(dir, ["diff", "--name-only", "HEAD"])) : [];
    const plan = (await call({ op: "plan.polishPlan", gen, heads, paths, edited })) as unknown as Plan;
    if (!Array.isArray(plan.classes)) throw new Error(`fwcore: no plan (${JSON.stringify(plan).slice(0, 200)})`);
    if (verb === "commit") {
      if (plan.restore.length) { git(dir, ["checkout", "HEAD", "--", ...plan.restore]); out(`restored ${plan.restore.join(" ")}`); }
      if (!plan.keep.length) { out(`VERDICT polish-commit ${task} nothing`); return 0; }
      git(dir, ["add", "--", ...plan.keep]);
      git(dir, ["commit", "-q", "-m", flags.message ?? `polish ${task}: comment and prose cuts (fw polish)`]);
      out(`kept ${plan.keep.join(" ")}`);
      out(`VERDICT polish-commit ${task} committed`);
      return 0;
    }
    if (kind === "polish-plan") {
      out(`worktree ${dir}`);
      for (const c of plan.classes) out(`class ${c.class} ${c.mark ?? "-"} ${c.path}`);
      for (const c of plan.classes.filter((c) => plan.scopes.comments.includes(c.path))) out(`comments ${c.mark ?? "-"} ${join(dir, c.path)}`);
      for (const p of plan.scopes.prose) out(`prose ${join(dir, p)}`);
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
    out(`VERDICT ${kind} ${task} error`);
    return 1;
  }
}
