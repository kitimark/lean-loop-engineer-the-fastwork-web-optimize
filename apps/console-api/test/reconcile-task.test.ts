import { afterEach, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { commitUrl, repoUrl, taskTrailers } from "../src/reconcile/git.ts";
import { Reconciler } from "../src/reconcile/reconciler.ts";
import { Store } from "../src/store.ts";
import { makeRepo } from "./reconcile-fixture.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
const define = (id: string) => ({ type: "task.define", key: `d${id}`, actor: "lead", task: id, title: id, stream: "s", milestone: null, deps: [], owner: "o", writes: [], devices: [], evidence: null });
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });

describe("Task trailer on a plain git merge", () => {
  it("marks the named undone task done with the merge commit as evidence; inline mentions and unknown names are ignored", async () => {
    const fx = makeRepo();
    const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    const rec = new Reconciler(store, fx.root);
    for (const id of ["t1", "t2"]) await store.submit(define(id) as never);
    // branch names are not task ids (worktree-agent-x), like the lead's real merges
    fx.commit(fx.worktree("worktree-agent-x"), "x.txt");
    fx.git(fx.root, "merge", "--no-ff", "-m", "merge x", "-m", "Task: t1\nTask: ghost", "worktree-agent-x");
    const m1 = fx.git(fx.root, "rev-parse", "HEAD");
    fx.commit(fx.worktree("worktree-agent-y"), "y.txt");
    fx.git(fx.root, "merge", "--no-ff", "-m", "merge y, mentions Task: t2 inline only", "worktree-agent-y");
    const s = await rec.reconcile();
    const ts = (await store.board()).plan.tasks;
    expect(ts.find((t) => t.id === "t1")).toMatchObject({ state: "done", evidence: m1 });
    expect(ts.find((t) => t.id === "t2")!.state).not.toBe("done");
    expect(s.refused).toBe(0);
    expect((await rec.reconcile()).submitted).toBe(0); // idempotent
  });

  it("parses only whole-line trailers", () => {
    const fx = makeRepo();
    fx.git(fx.root, "commit", "-q", "--allow-empty", "-m", "a", "-m", "Task: one");
    fx.git(fx.root, "commit", "-q", "--allow-empty", "-m", "b Task: two");
    expect(taskTrailers(fx.root, "main").map((t) => t.task)).toEqual(["one"]);
  });
});

describe("repo URL from origin", () => {
  it("normalizes remote spellings at runtime; no remote -> null", () => {
    const fx = makeRepo();
    expect(repoUrl(fx.root)).toBeNull();
    expect(commitUrl(fx.root, "abc")).toBeNull();
    fx.git(fx.root, "remote", "add", "origin", "x");
    for (const u of ["git@example.invalid:o/r.git", "https://example.invalid/o/r.git", "https://user@example.invalid/o/r", "ssh://git@example.invalid/o/r.git"]) {
      fx.git(fx.root, "remote", "set-url", "origin", u);
      expect(repoUrl(fx.root)).toBe("https://example.invalid/o/r");
    }
    expect(commitUrl(fx.root, "abc")).toBe("https://example.invalid/o/r/commit/abc");
  });
});
