// `fw land <branch> [--task <id>] [--allow <glob>]...`: the only way to main. Every decision is made by console-api
// (Lean: card readiness; `Fw.Console.Land.landVerdict` for the file scope); this file runs git and the checks, sends
// typed commands, and prints a digest. It merges (never rebases), never pushes, never forces, and touches only the
// lead's main checkout (plus removing a finished, clean, unlocked worktree of the landed branch).
import { execFileSync, spawn } from "node:child_process";
import { appendFileSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { Command } from "@fw/contracts";
import { branchCard } from "../../console-api/src/reconcile/naming.ts";
import { begin, span } from "./timing.ts";
import { askCore, dropLock, lockFacts, lockFile, readLock, takeLock } from "../hooks/land-guard.mjs";

export type Http = {
  get(path: string): Promise<{ status: number; body: any }>;
  post(path: string, body: unknown): Promise<{ status: number; body: any }>;
};

/** `localhost` may resolve to ::1 first while console-api listens on 127.0.0.1 only: always dial the IPv4 loopback. */
export const loopback = (base: string) => base.replace(/^(https?:\/\/)localhost(?=[:/]|$)/, "$1127.0.0.1");
export const httpFor = (base0: string): Http => { const base = loopback(base0); return {
  get: async (p) => { const r = await fetch(base + p); return { status: r.status, body: await r.json() }; },
  post: async (p, b) => {
    const r = await fetch(base + p, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(b) });
    return { status: r.status, body: await r.json() };
  },
}; };

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
  /** run after a successful landing, in the main checkout (plan sync); its lines are printed; it throws when it failed */
  after?: (mainDir: string) => Promise<string[]>;
  /** console-api base URL, only used to print the commands for steps that failed after the commit */
  base?: string;
  /** pause between the two attempts of a post-commit step (ms); default 700 */
  retryMs?: number;
};
/** `ok` = main was changed (or, on a refusal, left as it was). Post-commit trouble never turns it false: it is in `warnings`
 *  (also printed as lines) with the commands that finish the job. */
export type LandResult = { ok: boolean; lines: string[]; warnings?: string[] };

export const ATTRIBUTION = [
  "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>",
  "Claude-Session: https://claude.ai/code/session_01R3GWpzaWka38ev9uPDctoA",
];
/** a leftover conflict marker at the start of a line */
export const MARKER_RE = "^(<<<<<<<|>>>>>>>)";

const git = (cwd: string, args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
const tryGit = (cwd: string, args: string[]) => { try { git(cwd, args); return true; } catch { return false; } };
const tryGitEnv = (cwd: string, args: string[], env: Record<string, string>) => {
  try { execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, ...env } }); return true; } catch { return false; }
};
const tryHead = (cwd: string) => { try { return git(cwd, ["rev-parse", "--short", "HEAD"]); } catch { return "?"; } };

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

/** Set `evidence` of `task` in the work graph of `dir` when it has none, keeping the file's formatting (1-space JSON). */
export function writeEvidence(dir: string, task: string, evidence: string): "written" | "present" | "none" | "failed" {
  const f = join(dir, "docs/team/work-graph.json");
  let raw: string;
  try { raw = readFileSync(f, "utf8"); } catch { return "none"; }
  try {
    const g = JSON.parse(raw) as { tasks?: (PlanTask & { evidence?: string | null })[] };
    const t = g.tasks?.find((x) => x.id === task);
    if (!t) return "none";
    if (t.evidence) return "present";
    t.evidence = evidence;
    writeFileSync(f, JSON.stringify(g, null, 1) + (raw.endsWith("\n") ? "\n" : ""));
    return tryGit(dir, ["add", "--", "docs/team/work-graph.json"]) ? "written" : "failed";
  } catch { return "failed"; }
}

type PlanTask = { id: string; state: string; owner?: string; stream?: string; writes?: string[] };

/** Facts for `console.landPick`: is `branch` already in main, and the branches that could hold its work (`ci/<task>` and every
 *  branch checked out in a worktree: an agent that switched its worktree to `ci/<task>` commits there), each with
 *  "ahead of main" and "contains `branch`". Lean (`console.landPick`) chooses; this only reads git. */
export function pickFacts(cwd: string, main: string, branch: string, task?: string): { givenAhead: boolean; others: { name: string; ahead: boolean; contains: boolean }[] } {
  const inMain = (ref: string) => tryGit(cwd, ["merge-base", "--is-ancestor", ref, main]);
  const givenAhead = !inMain(branch);
  if (givenAhead) return { givenAhead, others: [] };
  const names = new Set<string>();
  if (task && tryGit(cwd, ["rev-parse", "--verify", "-q", `refs/heads/ci/${task}`])) names.add(`ci/${task}`);
  // only the worktree this branch was made for (<name>/ of `worktree-<name>`): any later branch of main contains a merged one
  const stem = branch.replace(/^worktree-/, "").replace(/\//g, "-");
  for (const w of worktrees(cwd)) if (w.branch && basename(w.dir).endsWith(stem)) names.add(w.branch);
  names.delete(branch); names.delete(main);
  return { givenAhead, others: [...names].map((name) => ({ name, ahead: !inMain(name), contains: tryGit(cwd, ["merge-base", "--is-ancestor", branch, name]) })) };
}

/** One `fw land` as one span ("fw land" / "total"): its 30 s ceiling is Lean `Fw.Obs.Timing.landCeilings`. A nested land (`via`) is part of the outer span. */
export async function land(branch: string, o: LandOptions, via?: string): Promise<LandResult> {
  const end = via ? () => {} : begin("fw land", "total");
  try { const r = await landRun(branch, o, via); end(r.ok ? 0 : 1); return r; } catch (e) { end(1); throw e; }
}

async function landRun(branch: string, o: LandOptions, via?: string): Promise<LandResult> {
  const lines: string[] = via ? [`${via} has nothing to land; landing ${branch}, which is ahead of it and contains it`] : [];
  const fail = (m: string): LandResult => { lines.push(`REFUSED: ${m}`); return { ok: false, lines }; };
  const main = o.mainRef ?? "main";
  const bc = branchCard(branch);
  if (branch === main) return fail("cannot land the main branch");
  if (!bc && !o.task) return fail(`branch ${branch} is not a card branch (card/<CARD>[/<agent>]); land it with --task <id>`);
  if (!tryGit(o.cwd, ["rev-parse", "--verify", `refs/heads/${branch}`])) return fail(`no such branch ${branch}`);
  const mainDir = worktreeOf(o.cwd, main);
  if (!mainDir) return fail(`${main} is not checked out in any worktree`);
  if (git(mainDir, ["status", "--porcelain", "--untracked-files=no"])) return fail(`${main} checkout has uncommitted changes`);
  // 0. the given branch has nothing to land: the agent may have committed on its ci/<task> branch (Lean: console.landPick)
  if (!via) {
    const pk = pickFacts(o.cwd, main, branch, o.task);
    if (!pk.givenAhead && pk.others.length) {
      const r = askCore("console.landPick", pk);
      if (!r) return fail("fwcore is not available to choose the branch to land (build lean/.lake)");
      if (r.pick === "other") {
        const res = await land(r.branch as string, o, branch);
        if (res.ok && tryGit(mainDir, ["branch", "-d", branch])) res.lines.push(`branch ${branch} deleted (it was already in ${main})`);
        return res;
      }
      if (r.pick === "ambiguous") return fail(`${branch} has nothing to land, and several branches are ahead of ${main} and contain it: ${(r.names as string[]).join(", ")}; land one of them`);
    }
  }
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
  let stream = task?.stream ?? "";
  if (task) {
    try {
      const g = JSON.parse(readFileSync(join(mainDir, "docs/team/work-graph.json"), "utf8")) as { tasks?: PlanTask[] };
      const row = g.tasks?.find((x) => x.id === o.task);
      writes = row?.writes ?? [];
      stream = row?.stream ?? stream;
    } catch { /* no work graph file: no writes */ }
  }
  const changed = git(o.cwd, ["diff", "--name-only", `${main}...${branch}`]).split("\n").filter(Boolean);
  const allow = o.allow ?? [];
  const sc = await o.http.post("/api/ops/land-scope", { writes, names: [o.task, task?.owner].filter(Boolean), allow, paths: changed, task: o.task ?? "", stream });
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

  // check output goes to .fw-console/land-logs/<task|branch>-<sha7>.log (gitignored); one line per check
  const logFile = join(mainDir, ".fw-console", "land-logs", `${(o.task ?? branch).replace(/[^A-Za-z0-9._-]/g, "_")}-${sha.slice(0, 7)}.log`);
  let logStarted = false;
  // async (not spawnSync) so SIGINT/SIGTERM handlers of the land run while a check is running
  const runCheck = (cwd: string, argv: string[]) => new Promise<{ status: number | null; stdout: string; stderr: string; error?: Error }>((resolve) => {
    const c = spawn(argv[0]!, argv.slice(1), { cwd, env: { ...process.env, ...o.env } });
    let stdout = "", stderr = "";
    c.stdout.on("data", (d) => { stdout += d; }); c.stderr.on("data", (d) => { stderr += d; });
    const kill = () => { c.kill("SIGTERM"); };
    process.once("SIGTERM", kill); process.once("SIGINT", kill);
    const done = (status: number | null, error?: Error) => { process.off("SIGTERM", kill); process.off("SIGINT", kill); resolve({ status, stdout, stderr, error }); };
    c.on("error", (e) => done(null, e));
    c.on("close", (code) => done(code));
  });
  const runChecks = async (cwd: string, list: string[][]): Promise<string | null> => {
    for (const argv of list) {
      const p = await span("fw land", argv.join(" "), () => runCheck(cwd, argv), (r) => r.status); // timing-spans
      const out = `${p.stdout}${p.stderr}${p.error ? String(p.error) : ""}`;
      mkdirSync(join(mainDir, ".fw-console", "land-logs"), { recursive: true });
      if (!logStarted) { writeFileSync(logFile, ""); logStarted = true; }
      appendFileSync(logFile, `$ ${argv.join(" ")}  (cwd ${cwd})\n${out}\n[exit ${p.status}]\n\n`);
      if (p.status !== 0) {
        const tail = out.split("\n").filter((l) => l !== "").slice(-30).join("\n");
        return `check FAILED: ${argv.join(" ")}\nlog: ${logFile}\n${tail}`;
      }
      lines.push(`check ok: ${argv.join(" ")}`);
    }
    return null;
  };
  const checks = o.checks ?? checksFor(mainDir, changed);

  let mergeSha: string;
  if (!o.task) {
    // card fast-forward: the checks run in the branch's own checkout (or main) before main moves
    const bad = await runChecks(worktreeOf(o.cwd, branch) ?? mainDir, checks);
    if (bad) return fail(bad);
    const e = await requestLand();
    if (e) return fail(e);
    const endMerge = begin("fw land", "merge");
    const ffOk = tryGit(mainDir, ["merge", "--ff-only", branch]);
    endMerge(ffOk ? 0 : 1);
    if (!ffOk) return fail(`${main} cannot fast-forward to ${branch}`);
    mergeSha = git(mainDir, ["rev-parse", "HEAD"]);
  } else {
    // 3. take the land lock (Lean: console.landLock), merge into the main checkout without committing, check, commit, release.
    // While the lock is held the pre-commit hook (hooks/land-guard.mjs) refuses every other commit in this checkout.
    const pre = git(mainDir, ["rev-parse", "HEAD"]);
    const lf = lockFile(mainDir);
    const lk0 = lockFacts(lf);
    const lv = askCore("console.landLock", { held: lk0.held, alive: lk0.alive });
    const holder = lk0.lock ? `pid ${lk0.lock.pid}, branch ${lk0.lock.branch ?? "?"}, since ${lk0.lock.at ?? "?"}` : "";
    if (!lv) return fail("fwcore is not available to decide the land lock (build lean/.lake)");
    if (lv.verdict === "busy") return fail(`another fw land holds ${lf} (${holder}); wait for it`);
    if (lv.verdict === "stale") return fail(`stale land lock ${lf} (${holder}; that process is gone). It was not removed: look at \`git status\` in ${mainDir} (an open merge: git merge --abort), then delete the file`);
    const lock = takeLock(lf, { branch, pre, dir: realpathSync(mainDir) });
    if (!lock) return fail(`another fw land took ${lf} just now; wait for it`);
    let released = false;
    const endLock = begin("fw land", "lock held"); // from take to release; its 5 s ceiling is Lean `Fw.Obs.Timing.landCeilings`
    const release = () => { if (!released) { released = true; endLock(0); dropLock(lf, lock.token); } };
    // the facts of `console.landCommit`: is the lock still ours, is MERGE_HEAD there, where is HEAD
    const facts = () => {
      let mh: string | null = null;
      try { mh = git(mainDir, ["rev-parse", "-q", "--verify", "MERGE_HEAD"]); } catch { /* none */ }
      return askCore("console.landCommit", { locked: readLock(lf)?.token === lock.token, mergeHead: mh, head: git(mainDir, ["rev-parse", "HEAD"]), pre });
    };
    // `merge --abort` only while the merge is still ours (lock held, MERGE_HEAD there, HEAD unmoved); otherwise nothing is reset
    const abort = (m: string): LandResult => {
      const d = facts();
      if (d?.ok) { tryGit(mainDir, ["merge", "--abort"]); return fail(`${m} (merge aborted, ${main} unchanged at ${pre.slice(0, 7)})`); }
      return fail(`${m}\nthe merge state is not intact (${d?.reason ?? "fwcore unavailable"}): ${main} is at ${tryHead(mainDir)}, the land started at ${pre.slice(0, 7)}; nothing was reset`);
    };
    const onSignal = (sig: NodeJS.Signals) => () => {
      try { if (facts()?.ok) tryGit(mainDir, ["merge", "--abort"]); } catch { /* best effort */ }
      release();
      process.exit(sig === "SIGINT" ? 130 : 143);
    };
    const onInt = onSignal("SIGINT"), onTerm = onSignal("SIGTERM");
    process.once("SIGINT", onInt); process.once("SIGTERM", onTerm);
    try {
      if (!span("fw land", "merge", () => tryGit(mainDir, ["merge", "--no-ff", "--no-commit", branch]), (ok) => (ok ? 0 : 1))) return abort(`${main} cannot merge ${branch} cleanly`);
      if (!tryGit(mainDir, ["rev-parse", "-q", "--verify", "MERGE_HEAD"])) return fail(`${branch} has nothing to land (already in ${main})`);
      let marks = "";
      try { marks = git(mainDir, ["grep", "-n", "-E", MARKER_RE]); } catch { /* exit 1: no match */ }
      if (marks) return abort(`conflict markers after the merge:\n${marks.split("\n").slice(0, 10).join("\n")}`);
      lines.push("no conflict markers");
      const bad = await runChecks(mainDir, checks);
      if (bad) return abort(bad);
      const e = await requestLand();
      if (e) return abort(e);
      // the task's evidence goes into the merge commit itself, next to the Task: trailer (a commit of the branch, so on main)
      const ev = writeEvidence(mainDir, o.task, sha.slice(0, 7));
      if (ev === "failed") return abort("could not write the evidence into docs/team/work-graph.json");
      if (ev === "written") lines.push(`evidence ${sha.slice(0, 7)} written into docs/team/work-graph.json (in the merge commit)`);
      // commit only into the merge the land opened (Lean: landTip): no lock, no MERGE_HEAD or a moved HEAD means someone
      // else touched main; then nothing is committed and nothing is reset
      const d = facts();
      if (!d?.ok) return fail(`will not commit: ${d ? d.reason : "fwcore is not available to decide"}. ${main} is at ${tryHead(mainDir)}, the land started at ${pre.slice(0, 7)}; ${main} was not reset. Inspect \`git status\` and \`git log\` in ${mainDir}`);
      const trailer = [`Task: ${o.task}`, ...(allow.length ? [`Land-Allow: ${allow.join(", ")}`] : []), ...(o.attribution ?? ATTRIBUTION)].join("\n");
      if (!span("fw land", "merge commit", () => tryGitEnv(mainDir, ["commit", "-m", `land ${branch}`, "-m", trailer], { FW_LAND_TOKEN: lock.token }), (ok) => (ok ? 0 : 1))) return abort("commit of the merge failed");
      mergeSha = git(mainDir, ["rev-parse", "HEAD"]);
    } finally {
      process.off("SIGINT", onInt); process.off("SIGTERM", onTerm);
      release();
    }
  }

  // From here main has moved: nothing below may fail the landing. Each step is tried twice; a step that still fails is
  // listed with the command that finishes it, and the exit stays 0 (ok = main changed).
  const warnings: string[] = [];
  const remaining: string[] = [];
  const pause = () => new Promise((r) => setTimeout(r, o.retryMs ?? 700));
  const why = (e: unknown) => {
    const code = (e as { cause?: { code?: string } })?.cause?.code;
    return `${e instanceof Error ? e.message : String(e)}${code ? ` (${code})` : ""}`;
  };
  const step = async (name: string, cmd: string, fn: () => Promise<string | void>): Promise<void> => {
    let last = "";
    for (let i = 0; i < 2; i++) {
      try { const r = await span("fw land", name, fn, (x) => (x ? 1 : 0)); if (!r) return; last = r; } catch (e) { last = why(e); }
      if (i === 0) await pause();
    }
    warnings.push(`step ${name} failed twice: ${last}`);
    remaining.push(`  ${name}: ${cmd}`);
  };
  const base = o.base ?? "$FW_API";
  const curl = (path: string) => `curl -s -X POST -H 'content-type: application/json' -d '{}' ${base}${path}`;
  lines.push(`merged ${branch} ${sha.slice(0, 7)} into ${main} as ${mergeSha.slice(0, 7)}`);

  // 4. the reconciler records card.landed and, from the Task: trailer, task.done (the only evidence route)
  await step("reconcile", curl("/api/reconcile"), async () => { await o.http.post("/api/reconcile", {}); });
  await step("verify", `${curl("/api/reconcile")} ; pnpm fw status`, async () => {
    if (bc) {
      const after = (await o.http.get(`/api/land/${encodeURIComponent(bc.card)}`)).body as { landed: boolean; violation: boolean };
      lines.push(`landed ${bc.card} ${sha.slice(0, 7)} on ${main}: ${after.landed ? "recorded" : "NOT recorded"}${after.violation ? " VIOLATION" : ""}`);
      if (!after.landed || after.violation) return `card ${bc.card} ${after.landed ? "landed with a VIOLATION" : "NOT recorded as landed"}`;
    }
    if (o.task) {
      const t = ((await o.http.get("/api/plan")).body?.tasks as PlanTask[] | undefined)?.find((x) => x.id === o.task);
      if (t?.state !== "done") return `task ${o.task} NOT recorded as done (state ${t?.state ?? "unknown"}): the Task: trailer was not picked up`;
      const url = (await o.http.get("/api/repo").catch(() => null))?.body?.commit as string | null | undefined;
      lines.push(`task ${o.task} done: ${url ? url + mergeSha : mergeSha}`);
    }
  });

  // 5. advisory CI of the task's ci/* ref: never blocks
  if (o.ci !== false && o.task) {
    try { lines.push(`ci (advisory) ci/${o.task}: ${(o.ci ?? ciLines)(`ci/${o.task}`).join("; ")}`); } catch { lines.push(`ci (advisory) ci/${o.task}: unavailable`); }
  }

  // 6. safe cleanup: `branch -d` only; the worktree only when clean and not locked (local, no console needed)
  const endCleanup = begin("fw land", "worktree cleanup");
  try {
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
  } catch (e) {
    warnings.push(`step cleanup failed: ${why(e)}`);
    remaining.push(`  cleanup: git worktree remove <dir of ${branch}> ; git branch -d ${branch}`);
  }
  endCleanup(0);

  if (o.after) await step("plan sync", "pnpm fw plan sync docs/team/work-graph.json", async () => { lines.push(...(await o.after!(mainDir))); });

  if (warnings.length) {
    lines.push(`WARNING: ${main} is changed (${mergeSha.slice(0, 7)}) but ${remaining.length} step(s) did not finish:`);
    for (const w of warnings) lines.push(`  ${w}`);
    lines.push("run these in the main checkout:", ...remaining);
  }
  return { ok: true, lines, warnings };

}
