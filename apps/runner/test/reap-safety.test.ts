// Repo identity and the live console, on real processes (task reap-auto-stop, round 2). Nothing here sends a signal to any process
// but the ones this file started (killed in afterAll by pid): the file reads the process table and asks Lean what it would select.
//
// The case that went wrong in round 1: a stop run with a temp repo as `top` selected the user's real console-api (an orphan
// whose cwd is outside the temp repo's checkouts). A console-like process (node, argv ending in apps/console-api/src/main.ts)
// is started with its parent gone (double fork) and its cwd in a removed worktree of ANOTHER temp repo.
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { classify, gather, psRows, select } from "../src/reap.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const started: number[] = []; // the pids this file started: the only ones it ever signals
let tmp = "";
let repoA = ""; // the repo the stop run is aimed at
let repoB = ""; // another repo, which owns the console-like process
const git = (cwd: string, ...a: string[]) => execFileSync("git", a, { cwd, encoding: "utf8", env: { ...process.env, GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" } });
const sleepMs = (ms: number) => { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); };

function makeRepo(dir: string) {
  mkdirSync(dir, { recursive: true });
  git(dir, "init", "-q", "-b", "main");
  mkdirSync(join(dir, "apps", "console-api", "src"), { recursive: true });
  writeFileSync(join(dir, "apps", "console-api", "src", "main.ts"), "");
  git(dir, "add", "-A");
  git(dir, "commit", "-qm", "init");
  mkdirSync(join(dir, ".claude", "worktrees", "gone1"), { recursive: true }); // a worktree directory git does not know: removed
}

/** Start `node -e <body> <repo>/apps/console-api/src/main.ts` with cwd `cwd`, its parent shell gone at once; returns its pid. */
function consoleLike(repo: string, cwd: string, spawnChild: boolean): number {
  const body = (spawnChild ? 'require("child_process").spawn(process.execPath,["-e","setInterval(function(){},1000)"],{stdio:"ignore"});' : "") + "setInterval(function(){},1000)";
  const r = spawnSync("sh", ["-c", '(cd "$1" && exec "$2" -e "$3" "$4" >/dev/null 2>&1 </dev/null & echo $!)', "sh", cwd, process.execPath, body, join(repo, "apps", "console-api", "src", "main.ts")], { encoding: "utf8" });
  const pid = Number(r.stdout.trim());
  expect(pid).toBeGreaterThan(1);
  started.push(pid);
  for (let n = 0; n < 100; n++) { // bounded wait until ps shows the exec'd argv (and the child, when asked)
    const t = psRows();
    const row = t?.rows.find((x) => x.pid === pid);
    if (row?.kind === "console" && (!spawnChild || t!.rows.some((x) => x.ppid === pid))) return pid;
    sleepMs(100);
  }
  throw new Error("the console-like process did not show up in ps");
}

beforeAll(() => {
  tmp = realpathSync(mkdtempSync(join(tmpdir(), "reap-safety-")));
  repoA = join(tmp, "a");
  repoB = join(tmp, "b");
  makeRepo(repoA);
  makeRepo(repoB);
});
afterAll(() => {
  const t = psRows()?.rows ?? [];
  const mine = new Set(started);
  for (let grew = true; grew;) { grew = false; for (const r of t) if (mine.has(r.ppid) && !mine.has(r.pid)) { mine.add(r.pid); grew = true; } }
  for (const p of mine) { try { process.kill(p, "SIGKILL"); } catch { /* gone */ } }
  rmSync(tmp, { recursive: true, force: true });
});

describe("a stop run aimed at one repo never selects a console of another", () => {
  it("a console-like orphan in another repo's removed worktree is classified a console and selected for no other repo", () => {
    const pid = consoleLike(repoB, join(repoB, ".claude", "worktrees", "gone1"), false);
    const table = psRows()!;
    const row = table.rows.find((r) => r.pid === pid)!;
    expect(classify(table.ps.find((p) => p.pid === pid)!.args)).toBe("console");
    // aimed at repo A: nothing is selected, as the process really runs, and as an orphan of init (also where a subreaper adopts it)
    const f = gather(repoA)!;
    expect(f.rows.find((r) => r.pid === pid)).toMatchObject({ kind: "console", inRepo: false, wt: null });
    expect(select(f, call)).toEqual([]);
    const orphaned = { ...f, rows: f.rows.map((r) => (r.pid === pid ? { ...r, ppid: 1 } : r)) };
    expect(select(orphaned, call).map((s) => s.pid)).not.toContain(pid);
    // the control: aimed at repo B itself the same process is a leftover of its removed worktree, so the check above can fail
    const own = gather(repoB)!;
    expect(own.rows.find((r) => r.pid === pid)).toMatchObject({ inRepo: true, wt: "gone1", ppid: row.ppid });
    expect(select({ ...own, rows: own.rows.map((r) => (r.pid === pid ? { ...r, ppid: 1 } : r)) }, call).map((s) => s.pid)).toContain(pid);
  });

  it("the console recorded in api.json, and the tool below it, are never selected, even in a removed worktree of the repo", () => {
    const pid = consoleLike(repoA, join(repoA, ".claude", "worktrees", "gone1"), true);
    const kid = psRows()!.rows.find((r) => r.ppid === pid)!.pid;
    const dir = join(tmp, "console");
    mkdirSync(dir, { recursive: true });
    const before = gather(repoA)!;
    const orphan = (f: typeof before) => ({ ...f, rows: f.rows.map((r) => (r.pid === pid ? { ...r, ppid: 1 } : r)) });
    // not recorded: it is a leftover of the removed worktree (the control)
    expect(select(orphan(before), call).map((s) => s.pid)).toContain(pid);
    writeFileSync(join(dir, "api.json"), JSON.stringify({ port: 1, pid, startedAt: Date.now() }));
    process.env.FW_CONSOLE_DIR = dir;
    try {
      const f = orphan(gather(repoA)!);
      expect(f.keep).toContainEqual({ pid, at: expect.any(Number) });
      const picked = select(f, call).map((s) => s.pid);
      expect(picked).not.toContain(pid);
      expect(picked).not.toContain(kid); // its descendant (the fwcore of a console) is shielded as well
    } finally {
      delete process.env.FW_CONSOLE_DIR;
    }
  });
});
