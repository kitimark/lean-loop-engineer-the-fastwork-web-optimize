// `fw land --task` on a plain (non-card) agent branch: file scope from the task's writes (Lean console.landScope),
// marker check, failing checks, dirty/locked worktrees, merge-never-rebase, safe cleanup.
import "./land-timeout.ts";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { checksFor, FWCORE_USERS, land, LOCAL_TESTS, READS_SCAN_ARGV, type Http } from "../src/land.ts";
import { askCore, coreBin } from "../hooks/land-guard.mjs";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });

const BR = "worktree-agent-t1";
const MARK = "<".repeat(7); // built at run time so this file holds no marker line

async function setup(writes: string[] = ["src/**"]) {
  const fx = makeRepo();
  const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  const app = createApp(store, undefined, new Reconciler(store, fx.root));
  const http: Http = {
    get: async (p) => { const r = await app.request(p); return { status: r.status, body: await r.json() }; },
    post: async (p, b) => {
      const r = await app.request(p, { method: "POST", body: JSON.stringify(b), headers: { "content-type": "application/json" } });
      return { status: r.status, body: await r.json() };
    },
  };
  await store.submit({ type: "task.define", key: "d", actor: "lead", task: "t1", title: "t", stream: "s", milestone: null, deps: [], owner: "builder", writes, devices: [], evidence: null } as never);
  // the writes live in the work graph file of the main checkout (untracked here)
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "t1", owner: "builder", writes }] }));
  const wt = fx.worktree(BR);
  const opts = { http, cwd: fx.root, checks: [["true"]], ci: false as const, task: "t1" };
  const mainSha = () => fx.git(fx.root, "rev-parse", "main");
  const clean = () => expect(fx.git(fx.root, "status", "--porcelain", "--untracked-files=no")).toBe("") ;
  const noMerge = () => expect(() => fx.git(fx.root, "rev-parse", "-q", "--verify", "MERGE_HEAD")).toThrow();
  return { fx, store, http, wt, opts, mainSha, clean, noMerge };
}
const text = (r: { lines: string[] }) => r.lines.join("\n");

describe("fw land --task on an agent branch", () => {
  it("lands an in-scope branch: merge commit with Task + attribution trailers, done from the trailer, worktree and branch cleaned", async () => {
    const { fx, store, wt, opts, mainSha } = await setup();
    fx.commit(wt, "src/a.ts");
    fx.commit(wt, "docs/team/handoffs/t1.md");
    fx.commit(wt, "packages/contracts/golden/x/a.jsonl");
    const tip = fx.git(wt, "rev-parse", "HEAD");
    const r = await land(BR, { ...opts, ci: (ref) => [`${ref} success`] });
    expect(r.ok).toBe(true);
    expect(fx.git(fx.root, "rev-list", "--parents", "-n1", "main").split(" ")).toHaveLength(3);
    const msg = fx.git(fx.root, "log", "-1", "--format=%B", "main");
    expect(msg).toContain("Task: t1");
    expect(msg).toContain("Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>");
    expect(msg).toContain("Claude-Session: https://claude.ai/code/session_");
    expect((await store.board()).plan.tasks.find((t) => t.id === "t1")).toMatchObject({ state: "done", evidence: mainSha() });
    expect(store.readEvents().filter((e) => e.type === "task.done")).toHaveLength(1); // one evidence route
    expect(text(r)).toContain("ci (advisory) ci/t1: ci/t1 success");
    expect(text(r)).toMatch(/worktree .* removed/);
    expect(fx.git(fx.root, "branch", "--list", BR)).toBe(""); // deleted with -d
    expect(fx.git(fx.root, "rev-parse", tip)).toBe(tip);
  });

  it("refuses a file outside the task's scope and leaves main alone", async () => {
    const { fx, wt, opts, mainSha, clean, noMerge } = await setup();
    const before = mainSha();
    fx.commit(wt, "src/a.ts");
    fx.commit(wt, "apps/site/other.tsx");
    const r = await land(BR, opts);
    expect(r.ok).toBe(false);
    expect(text(r)).toContain("apps/site/other.tsx");
    expect(text(r)).not.toMatch(/\n {2}src\/a\.ts/);
    expect(mainSha()).toBe(before); clean(); noMerge();
    expect(fx.git(fx.root, "branch", "--list", BR)).toContain(BR);
  });

  it("refuses protected paths even with --allow **", async () => {
    const { fx, wt, opts, mainSha } = await setup();
    const before = mainSha();
    fx.commit(wt, ".claude/settings.json");
    const r = await land(BR, { ...opts, allow: ["**"] });
    expect(r.ok).toBe(false);
    expect(text(r)).toContain(".claude/settings.json");
    expect(mainSha()).toBe(before);
  });

  it("a task without writes is refused with the changed files; --allow admits them and is recorded in the merge message", async () => {
    const { fx, wt, opts, mainSha } = await setup([]);
    const before = mainSha();
    fx.commit(wt, "notes/a.md");
    const r = await land(BR, opts);
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/no writes/);
    expect(text(r)).toContain("notes/a.md");
    expect(text(r)).toContain("--allow");
    expect(mainSha()).toBe(before);
    const r2 = await land(BR, { ...opts, allow: ["notes/**"] });
    expect(r2.ok).toBe(true);
    expect(fx.git(fx.root, "log", "-1", "--format=%B", "main")).toContain("Land-Allow: notes/**");
  });

  it("refuses when the merged tree has a conflict marker, aborting the merge", async () => {
    const { fx, wt, opts, mainSha, clean, noMerge } = await setup();
    const before = mainSha();
    fx.commit(wt, "src/m.ts", `a\n${MARK} HEAD\nb\n`);
    const r = await land(BR, opts);
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/conflict markers/);
    expect(text(r)).toContain("src/m.ts");
    expect(mainSha()).toBe(before); clean(); noMerge();
  });

  it("refuses a real merge conflict without leaving a half merge", async () => {
    const { fx, wt, opts, mainSha, clean, noMerge } = await setup();
    fx.commit(fx.root, "src/c.ts", "main side\n");
    const before = mainSha();
    fx.commit(wt, "src/c.ts", "branch side\n");
    const r = await land(BR, opts);
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/cannot merge/);
    expect(mainSha()).toBe(before); clean(); noMerge();
  });

  it("a failing check aborts the merge: main is exactly as before", async () => {
    const { fx, wt, opts, mainSha, clean, noMerge } = await setup();
    fx.commit(wt, "src/a.ts");
    const before = mainSha();
    const r = await land(BR, { ...opts, checks: [["true"], ["false"]] });
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/check FAILED: false/);
    expect(mainSha()).toBe(before); clean(); noMerge();
    expect(fx.git(fx.root, "branch", "--list", BR)).toContain(BR);
  });

  it("merges a branch that is behind main and never rebases it", async () => {
    const { fx, wt, opts } = await setup();
    const tip = fx.commit(wt, "src/a.ts");
    fx.commit(fx.root, "elsewhere.txt");
    const r = await land(BR, opts);
    expect(r.ok).toBe(true);
    expect(fx.git(fx.root, "merge-base", "--is-ancestor", tip, "main")).toBe(""); // the original commit is in main
  });

  it("leaves a worktree with uncommitted changes, and keeps its branch", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    writeFileSync(join(wt, "scratch.txt"), "wip\n");
    const r = await land(BR, opts);
    expect(r.ok).toBe(true);
    expect(text(r)).toMatch(/left: uncommitted changes/);
    expect(fx.git(fx.root, "worktree", "list")).toContain(wt);
    expect(fx.git(fx.root, "branch", "--list", BR)).toContain(BR);
  });

  it("leaves a locked worktree (a live agent), and keeps its branch", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    fx.git(fx.root, "worktree", "lock", "--reason", `claude agent x (pid ${process.pid} start now)`, wt);
    const r = await land(BR, opts);
    expect(r.ok).toBe(true);
    expect(text(r)).toMatch(/left: locked/);
    expect(text(r)).not.toMatch(/stale/);
    expect(fx.git(fx.root, "worktree", "list")).toContain(wt);
    expect(fx.git(fx.root, "branch", "--list", BR)).toContain(BR);
  });

  it("flags a lock whose pid is gone as stale, but still does not remove it", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    fx.git(fx.root, "worktree", "lock", "--reason", "claude agent x (pid 2147483646 start now)", wt);
    const r = await land(BR, opts);
    expect(text(r)).toMatch(/lock looks stale/);
    expect(fx.git(fx.root, "worktree", "list")).toContain(wt);
  });

  it("refuses a non-card branch without --task, an unknown task, and main uncommitted", async () => {
    const { fx, wt, opts, mainSha } = await setup();
    fx.commit(wt, "src/a.ts");
    expect((await land(BR, { ...opts, task: undefined })).ok).toBe(false);
    expect(text(await land(BR, { ...opts, task: "nope" }))).toMatch(/unknown task/);
    writeFileSync(join(fx.root, "README"), "dirty\n");
    const before = mainSha();
    expect(text(await land(BR, opts))).toMatch(/uncommitted/);
    expect(mainSha()).toBe(before);
  });

  it("never pushes: no remote is needed and none is touched", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    await land(BR, opts);
    expect(fx.git(fx.root, "remote")).toBe("");
  });
});

describe("checksFor", () => {
  it("derives the checks from the changed files", () => {
    expect(checksFor("/nonexistent", ["docs/a.md"])).toEqual([]);
    expect(checksFor("/nonexistent", ["lean/Fw/A.lean"])).toEqual([["sh", "lean/scripts/check.sh"], ...LOCAL_TESTS.filter((t) => FWCORE_USERS.includes(t.id)).map((t) => t.argv), READS_SCAN_ARGV]);
    const root = join(dirname(new URL(import.meta.url).pathname), "../../..");
    expect(checksFor(root, ["apps/runner/src/land.ts", "apps/runner/test/x.ts"])).toEqual([["pnpm", "--filter", "./apps/runner", "test"], ["pnpm", "--filter", "./packages/engine-check", "test"], READS_SCAN_ARGV]);
  });
  it("installs first when a dependency changes", () => {
    expect(checksFor("/nonexistent", ["pnpm-lock.yaml"])).toEqual([["pnpm", "install", "--frozen-lockfile"], READS_SCAN_ARGV]);
    expect(checksFor("/nonexistent", ["packages/x/package.json"])[0]).toEqual(["pnpm", "install", "--frozen-lockfile"]);
  });
});

describe("golden registration set: the write lists of incident inc-golden-reg-scope", () => {
  const file = join(dirname(fileURLToPath(import.meta.url)), "../../../packages/contracts/golden/console/land-scope-regs.jsonl");
  const rows = readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
  it("has an admitted and a protected row for each refused task", () => {
    for (const t of ["jev-retrieval-trace", "site-layer-opts", "slot-span-key"]) {
      expect(rows.some((r) => r.request.task === t && r.response.ok)).toBe(true);
      expect(rows.some((r) => r.request.task === t && r.request.paths.includes(".git/config") && !r.response.ok)).toBe(true);
    }
  });
  it("fwcore reproduces every row", () => {
    expect(existsSync(coreBin())).toBe(true);
    for (const row of rows) {
      const got = askCore("console.landScope", row.request);
      expect(got, row.name).not.toBeNull();
      for (const [k, v] of Object.entries(row.response as Record<string, unknown>)) expect(got![k], `${row.name} .${k}`).toEqual(v);
    }
  });
});
