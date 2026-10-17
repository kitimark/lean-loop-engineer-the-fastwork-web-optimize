// `fw land <branch> [--task <id>] [--allow <glob>]...`: the only way to main. Every decision is made by console-api
// (Lean: card readiness; `Fw.Console.Land.landVerdict` for the file scope); this file runs git and the checks, sends
// typed commands, and prints a digest. It merges (never rebases), never pushes, never forces, and touches only the
// lead's main checkout (plus removing a finished, clean, unlocked worktree of the landed branch).
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { Command } from "@fw/contracts";
import { branchCard } from "../../console-api/src/reconcile/naming.ts";

export type Http = {
  get(path: string): Promise<{ status: number; body: any }>;
  post(path: string, body: unknown): Promise<{ status: number; body: any }>;
};

export const httpFor = (base: string): Http => ({
  get: async (p) => { const r = await fetch(base + p); return { status: r.status, body: await r.json() }; },
  post: async (p, b) => {
    const r = await fetch(base + p, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(b) });
    return { status: r.status, body: await r.json() };
  },
});

export type LandOptions = {
  http: Http;
  /** any directory of the repo (main checkout or a worktree) */
  cwd: string;
  mainRef?: string;
  /** how to send the land request: default is the capability door `/api/agent/commands` with `argv` */
  argv?: string[];
  submit?: (cmd: Command) => Promise<{ status: number; body: any }>;
  /** checks run in the main checkout after the merge, before it is committed; default: derived from the changed files */
  checks?: string[][];
  env?: Record<string, string | undefined>;
  /** work-graph task this landing completes: merged with --no-ff and a `Task: <id>` trailer; the reconciler then
   *  derives task.done from that trailer (the only evidence route) */
  task?: string;
  /** explicit extra scope globs (`--allow`), recorded in the merge message */
  allow?: string[];
  /** advisory CI conclusions of the task's ci/* ref; default: one `gh run list` call; `false` skips it */
  ci?: false | ((ref: string) => string[]);
  /** attribution lines of the merge commit; default: the lead's */
  attribution?: string[];
  /** run after a successful landing (plan sync); its lines are printed */
  after?: () => Promise<string[]>;
};
export type LandResult = { ok: boolean; lines: string[] };

export const ATTRIBUTION = [
  "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>",
  "Claude-Session: https://claude.ai/code/session_01R3GWpzaWka38ev9uPDctoA",
];
/** a leftover conflict marker at the start of a line */
export const MARKER_RE = "^(<<<<<<<|>>>>>>>)";

const git = (cwd: string, args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
const tryGit = (cwd: string, args: string[]) => { try { git(cwd, args); return true; } catch { return false; } };

type Wt = { dir: string; branch: string | null; locked: string | null };
/** All worktrees with their branch and lock reason (`""` = locked without a reason). */
export function worktrees(cwd: string): Wt[] {
  const out: Wt[] = [];
  let cur: Wt | null = null;
  for (const l of git(cwd, ["worktree", "list", "--porcelain"]).split("\n")) {
    if (l.startsWith("worktree ")) { cur = { dir: l.slice(9), branch: null, locked: null }; out.push(cur); }
    else if (cur && l.startsWith("branch refs/heads/")) cur.branch = l.slice(18);
    else if (cur && (l === "locked" || l.startsWith("locked "))) cur.locked = l.slice(7);
  }
  return out;
}

/** Directory where `ref` is checked out, or null. */
export function worktreeOf(cwd: string, ref: string): string | null {
  return worktrees(cwd).find((w) => w.branch === ref)?.dir ?? null;
}

const alive = (pid: number) => { try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; } };

/** Checks that cover the changed files: the Lean gates for lean/, the package's own tests for apps/<n>/ and packages/<n>/. */
export function checksFor(root: string, changed: string[]): string[][] {
  const out: string[][] = [];
  // a new or changed dependency must be installed before any package test runs (a new workspace package is otherwise
  // unresolvable: TS2307 on the first landing of packages/gh-budget)
  if (changed.some((f) => f === "pnpm-lock.yaml" || /(^|\/)package\.json$/.test(f))) out.push(["pnpm", "install", "--frozen-lockfile"]);
  if (changed.some((f) => f.startsWith("lean/"))) out.push(["sh", "lean/scripts/check.sh"]);
  const pkgs = new Set<string>();
  for (const f of changed) { const m = /^(apps|packages)\/([^/]+)\//.exec(f); if (m) pkgs.add(`${m[1]}/${m[2]}`); }
  for (const p of [...pkgs].sort()) {
    try {
      if (JSON.parse(readFileSync(join(root, p, "package.json"), "utf8")).scripts?.test) out.push(["pnpm", "--filter", `./${p}`, "test"]);
    } catch { /* no package.json: nothing to run */ }
  }
  return out;
}

/** One `gh run list` call, advisory only. */
export function ciLines(ref: string): string[] {
  try {
    const raw = execFileSync("gh", ["run", "list", "--branch", ref, "--limit", "5", "--json", "name,conclusion,status,headSha"],
      { encoding: "utf8", timeout: 20_000, stdio: ["ignore", "pipe", "pipe"] });
    const rs = JSON.parse(raw) as { name: string; conclusion: string; status: string; headSha: string }[];
    return rs.length ? rs.map((r) => `${r.name} ${r.headSha.slice(0, 7)} ${r.conclusion || r.status}`) : ["no runs"];
  } catch { return ["unavailable"]; }
}

type PlanTask = { id: string; state: string; owner?: string; writes?: string[] };

export async function land(branch: string, o: LandOptions): Promise<LandResult> {
  const lines: string[] = [];
  const fail = (m: string): LandResult => { lines.push(`REFUSED: ${m}`); return { ok: false, lines }; };
  const main = o.mainRef ?? "main";
  const bc = branchCard(branch);
  if (branch === main) return fail("cannot land the main branch");
  if (!bc && !o.task) return fail(`branch ${branch} is not a card branch (card/<CARD>[/<agent>]); land it with --task <id>`);
  if (!tryGit(o.cwd, ["rev-parse", "--verify", `refs/heads/${branch}`])) return fail(`no such branch ${branch}`);
  const mainDir = worktreeOf(o.cwd, main);
  if (!mainDir) return fail(`${main} is not checked out in any worktree`);
  if (git(mainDir, ["status", "--porcelain", "--untracked-files=no"])) return fail(`${main} checkout has uncommitted changes`);
  const sha = git(o.cwd, ["rev-parse", `refs/heads/${branch}`]);
  const behind = !tryGit(o.cwd, ["merge-base", "--is-ancestor", main, branch]);
  if (behind && !o.task) return fail(`${branch} is behind ${main}; a fast-forward is impossible (land it with --task for a merge commit; branches are never rebased)`);

  // 1. the task and the file scope (Lean: console.landScope)
  let task: PlanTask | undefined;
  if (o.task) {
    if (!/^[A-Za-z0-9._-]+$/.test(o.task)) return fail(`bad task id ${o.task}`);
    const pl = await o.http.get("/api/plan");
    task = (pl.body?.tasks as PlanTask[] | undefined)?.find((x) => x.id === o.task);
    if (!task) return fail(`unknown task ${o.task} (fw plan sync first)`);
    if (task.state === "done") return fail(`task ${o.task} is already done`);
  }
  // the writes are in the work graph file of the main checkout (the board does not carry them)
  let writes: string[] = [];
  if (task) {
    try {
      const g = JSON.parse(readFileSync(join(mainDir, "docs/team/work-graph.json"), "utf8")) as { tasks?: PlanTask[] };
      writes = g.tasks?.find((x) => x.id === o.task)?.writes ?? [];
    } catch { /* no work graph file: no writes */ }
  }
  const changed = git(o.cwd, ["diff", "--name-only", `${main}...${branch}`]).split("\n").filter(Boolean);
  const allow = o.allow ?? [];
  const sc = await o.http.post("/api/ops/land-scope", { writes, names: [o.task, task?.owner].filter(Boolean), allow, paths: changed });
  if (sc.status !== 200) return fail(`scope check unavailable: ${sc.body.reason ?? sc.status}`);
  if (!sc.body.ok) {
    const list = (xs: string[]) => xs.map((x) => `\n  ${x}`).join("");
    if (sc.body.reason === "noWrites")
      return fail(`${o.task ? `task ${o.task}` : branch} has no writes, so no file may land. Changed files:${list(changed)}\nadd writes to the task in docs/team/work-graph.json (then fw plan sync), or pass --allow <glob>`);
    return fail(`files outside the scope of ${o.task ?? branch}:${list(sc.body.violations as string[])}\nwrites: ${writes.join(", ") || "(none)"}; pass --allow <glob> to admit more`);
  }
  lines.push(`scope ok (${changed.length} files)`);

  // 2. a card branch: the console's readiness, then (later) the land request, a decision the reducer may refuse
  const submit = o.submit ?? ((c: Command) => o.http.post("/api/agent/commands", { argv: o.argv ?? [], command: c }));
  if (bc) {
    await o.http.post("/api/reconcile", {});
    const r = await o.http.get(`/api/land/${encodeURIComponent(bc.card)}`);
    if (r.status !== 200) return fail(`console: ${r.body.reason ?? r.status}`);
    const rd = r.body as { stage: string; head: string | null; landed: boolean; ready: boolean; next: { who: string; command: string } };
    if (rd.landed) return fail("card already landed");
    if (!rd.ready) return fail(`card ${bc.card} is at stage ${rd.stage}; next: ${rd.next.who}: ${rd.next.command}`);
    if (rd.head !== sha) return fail(`stale: console head ${rd.head?.slice(0, 7)} is not branch tip ${sha.slice(0, 7)}`);
  }
  const requestLand = async (): Promise<string | null> => {
    if (!bc) return null;
    const cmd = Command.parse({ type: "card.land_request", key: `card.land_request:${bc.card}:${sha}`, actor: "lead", card: bc.card, sha });
    // the actor in `cmd` is a placeholder: the capability door stamps the real one from the hook's capability
    const lr = await submit(cmd);
    return lr.body.ok ? null : `land_request: ${lr.body.reason}`;
  };

  const runChecks = (cwd: string, list: string[][]): string | null => {
    for (const argv of list) {
      const p = spawnSync(argv[0]!, argv.slice(1), { cwd, stdio: "inherit", env: { ...process.env, ...o.env } });
      if (p.status !== 0) return `check failed: ${argv.join(" ")}`;
      lines.push(`check ok: ${argv.join(" ")}`);
    }
    return null;
  };
  const checks = o.checks ?? checksFor(mainDir, changed);

  let mergeSha: string;
  if (!o.task) {
    // card fast-forward: the checks run in the branch's own checkout (or main) before main moves
    const bad = runChecks(worktreeOf(o.cwd, branch) ?? mainDir, checks);
    if (bad) return fail(bad);
    const e = await requestLand();
    if (e) return fail(e);
    if (!tryGit(mainDir, ["merge", "--ff-only", branch])) return fail(`${main} cannot fast-forward to ${branch}`);
    mergeSha = git(mainDir, ["rev-parse", "HEAD"]);
  } else {
    // 3. merge into the main checkout without committing; every refusal below aborts it (main is left as it was)
    const pre = git(mainDir, ["rev-parse", "HEAD"]);
    const abort = (m: string): LandResult => { tryGit(mainDir, ["merge", "--abort"]); return fail(`${m} (merge aborted, ${main} unchanged at ${pre.slice(0, 7)})`); };
    if (!tryGit(mainDir, ["merge", "--no-ff", "--no-commit", branch])) return abort(`${main} cannot merge ${branch} cleanly`);
    if (!tryGit(mainDir, ["rev-parse", "-q", "--verify", "MERGE_HEAD"])) return fail(`${branch} has nothing to land (already in ${main})`);
    let marks = "";
    try { marks = git(mainDir, ["grep", "-n", "-E", MARKER_RE]); } catch { /* exit 1: no match */ }
    if (marks) return abort(`conflict markers after the merge:\n${marks.split("\n").slice(0, 10).join("\n")}`);
    lines.push("no conflict markers");
    const bad = runChecks(mainDir, checks);
    if (bad) return abort(bad);
    const e = await requestLand();
    if (e) return abort(e);
    const trailer = [`Task: ${o.task}`, ...(allow.length ? [`Land-Allow: ${allow.join(", ")}`] : []), ...(o.attribution ?? ATTRIBUTION)].join("\n");
    if (!tryGit(mainDir, ["commit", "-m", `land ${branch}`, "-m", trailer])) return abort("commit of the merge failed");
    mergeSha = git(mainDir, ["rev-parse", "HEAD"]);
  }

  // 4. the reconciler records card.landed and, from the Task: trailer, task.done (the only evidence route)
  await o.http.post("/api/reconcile", {});
  let ok = true;
  if (bc) {
    const after = (await o.http.get(`/api/land/${encodeURIComponent(bc.card)}`)).body as { landed: boolean; violation: boolean };
    lines.push(`landed ${bc.card} ${sha.slice(0, 7)} on ${main}: ${after.landed ? "recorded" : "NOT recorded"}${after.violation ? " VIOLATION" : ""}`);
    ok = after.landed && !after.violation;
  } else lines.push(`landed ${branch} ${sha.slice(0, 7)} on ${main} as ${mergeSha.slice(0, 7)}`);
  if (o.task) {
    const t = ((await o.http.get("/api/plan")).body?.tasks as PlanTask[] | undefined)?.find((x) => x.id === o.task);
    if (t?.state === "done") {
      const url = (await o.http.get("/api/repo").catch(() => null))?.body?.commit as string | null | undefined;
      lines.push(`task ${o.task} done: ${url ? url + mergeSha : mergeSha}`);
    } else { lines.push(`task ${o.task} NOT recorded as done (state ${t?.state ?? "unknown"}): the Task: trailer was not picked up`); ok = false; }
  }

  // 5. advisory CI of the task's ci/* ref: never blocks
  if (o.ci !== false && o.task) lines.push(`ci (advisory) ci/${o.task}: ${(o.ci ?? ciLines)(`ci/${o.task}`).join("; ")}`);

  // 6. safe cleanup: `branch -d` only; the worktree only when clean and not locked
  const wt = worktrees(o.cwd).find((w) => w.branch === branch);
  let removed = true;
  if (wt) {
    const here = resolve(o.cwd);
    if (wt.dir === mainDir) removed = false;
    else if (wt.locked !== null) {
      removed = false;
      const pid = /pid (\d+)/.exec(wt.locked)?.[1];
      lines.push(`worktree ${wt.dir} left: locked${wt.locked ? ` (${wt.locked})` : ""}${pid && !alive(Number(pid)) ? "; the lock looks stale, unlock it by hand" : ""}`);
    } else if (git(wt.dir, ["status", "--porcelain"])) {
      removed = false; lines.push(`worktree ${wt.dir} left: uncommitted changes`);
    } else if (here === resolve(wt.dir) || here.startsWith(resolve(wt.dir) + "/")) {
      removed = false; lines.push(`worktree ${wt.dir} left: it is the current directory`);
    } else if (!tryGit(mainDir, ["worktree", "remove", wt.dir])) { removed = false; lines.push(`worktree ${wt.dir} left: git refused to remove it`); }
    else lines.push(`worktree ${wt.dir} removed`);
  }
  if (removed) lines.push(tryGit(mainDir, ["branch", "-d", branch]) ? `branch ${branch} deleted` : `branch ${branch} kept (branch -d refused)`);
  else lines.push(`branch ${branch} kept`);

  if (o.after) lines.push(...(await o.after()));
  return { ok, lines };
}
