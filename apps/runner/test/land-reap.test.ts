// The land report's leftover-process lines (task orphan-guard): printed right after a worktree removal, absent when the
// worktree is left.
import "./land-timeout.ts";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { checksFor, land, READS_SCAN_ARGV, type Http } from "../src/land.ts";

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

const LINES = ["leftover processes (not stopped; pnpm -s fw reap --list): 1", "  500 group lspServe: lake serve of lean-lsp-mcp, cwd in no live checkout"];

describe("land report: leftover processes", () => {
  it("the lines follow 'worktree <dir> removed'", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    const dirs: string[] = [];
    const r = await land(BR, { ...opts, reap: async (d: string) => { dirs.push(d); return LINES; } });
    expect(r.ok).toBe(true);
    const i = r.lines.findIndex((l) => /^worktree .* removed$/.test(l));
    expect(i).toBeGreaterThanOrEqual(0);
    expect(r.lines.slice(i + 1, i + 3)).toEqual(LINES);
    expect(dirs).toEqual([fx.root]);
  });

  it("a failing list is advisory: the land still succeeds", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    const r = await land(BR, { ...opts, reap: async () => { throw new Error("boom"); } });
    expect(r.ok).toBe(true);
    expect(text(r)).toMatch(/worktree .* removed/);
  });

  it("a worktree left (uncommitted changes) prints no lines", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    writeFileSync(join(wt, "scratch.txt"), "wip\n");
    let called = false;
    const r = await land(BR, { ...opts, reap: async () => { called = true; return LINES; } });
    expect(text(r)).toMatch(/left: uncommitted changes/);
    expect(called).toBe(false);
    expect(text(r)).not.toContain("leftover processes");
  });

  it("a worktree that is the current directory prints no lines", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    const r = await land(BR, { ...opts, cwd: wt, reap: async () => LINES });
    expect(text(r)).not.toContain("leftover processes");
  });
});
