// `fw land --dry` (task land-dry; Lean Fw.Console.LandDry: dry_pass_land_pass, dry_refusal_is_land_refusal, handback_pass_land_pass).
// A dry land runs the real land's scope, merge and reads stages and nothing else: no lock, no queue, main untouched.
import "./land-timeout.ts";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, type Http } from "../src/land.ts";
import { lockFile } from "../hooks/land-guard.mjs";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });
const BR = "worktree-agent-t1";

async function setup(writes = ["src/**"]) {
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
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "t1", owner: "builder", stream: "s", writes, evidence: null }] }, null, 1) + "\n");
  fx.git(fx.root, "add", "--", "docs/team/work-graph.json");
  fx.git(fx.root, "commit", "-q", "-m", "work graph");
  const wt = fx.worktree(BR);
  const opts = { http, cwd: fx.root, checks: [["true"]], ci: false as const, task: "t1", retryMs: 1, lockWaitMs: 0 };
  const snap = () => ({ main: fx.git(fx.root, "rev-parse", "main"), status: fx.git(fx.root, "status", "--porcelain", "--untracked-files=no"), lock: existsSync(lockFile(fx.root)), queue: existsSync(join(fx.root, ".fw-console", "land-queue.jsonl")) });
  return { fx, wt, opts, snap };
}
const text = (r: { lines: string[] }) => r.lines.join("\n");
const reads = (argv: string[], selected = true) => ({ dryReads: { argv, selected } });

describe("fw land --dry", () => {
  it("passes on a clean branch and leaves main, the lock and the queue untouched; the real land then passes", async () => {
    const { fx, wt, opts, snap } = await setup();
    fx.commit(wt, "src/a.ts");
    const before = snap();
    const r = await land(BR, { ...opts, dry: true, ...reads(["true"]) });
    expect(r.ok, text(r)).toBe(true);
    expect(r.kind).toBe("dry");
    expect(snap()).toEqual(before);
    const real = await land(BR, opts);
    expect(real.ok, text(real)).toBe(true);
    expect(real.kind).toBe("done");
  });
  it("scope: a file outside the task's writes is refused as scope, and so is the real land", async () => {
    const { fx, wt, opts, snap } = await setup();
    fx.commit(wt, "other/b.ts");
    const before = snap();
    const r = await land(BR, { ...opts, dry: true, ...reads(["true"]) });
    expect(r.ok).toBe(false);
    expect(r.kind, text(r)).toBe("scope");
    expect(snap()).toEqual(before);
    expect((await land(BR, opts)).kind).toBe("scope");
  });
  it("conflict: committed conflict markers are refused as conflict, and so is the real land", async () => {
    const { fx, wt, opts, snap } = await setup();
    fx.commit(wt, "src/m.ts", "<<<<<<< ours\nx\n=======\ny\n>>>>>>> theirs\n");
    const before = snap();
    const r = await land(BR, { ...opts, dry: true, ...reads(["true"]) });
    expect(r.kind, text(r)).toBe("conflict");
    expect(snap()).toEqual(before);
    expect((await land(BR, opts)).kind).toBe("conflict");
  });
  it("reads: a failing reads test is refused as reads; when the change does not select it, it cannot refuse", async () => {
    const { fx, wt, opts, snap } = await setup();
    fx.commit(wt, "src/a.ts");
    const before = snap();
    const bad = await land(BR, { ...opts, dry: true, ...reads(["sh", "-c", "echo land-inputs.test failed; exit 1"]) });
    expect(bad.kind, text(bad)).toBe("reads");
    expect(snap()).toEqual(before);
    const skipped = await land(BR, { ...opts, dry: true, ...reads(["false"], false) });
    expect(skipped.kind, text(skipped)).toBe("dry");
  });
  it("stale: a branch that lacks main is refused as stale (the stale base that carried another task's diff)", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    fx.commit(fx.root, "docs/other.md");
    const r = await land(BR, { ...opts, dry: true, ...reads(["true"]) });
    expect(r.kind, text(r)).toBe("stale");
  });
  it("done: a branch already in main is `done`", async () => {
    const { opts } = await setup();
    const r = await land(BR, { ...opts, dry: true, ...reads(["true"]) });
    expect(r.kind, text(r)).toBe("done");
  });
  it("needs --task", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    const r = await land(BR, { ...opts, task: undefined, dry: true });
    expect(r.ok).toBe(false);
  });
});

describe("kinds of real-land refusals", () => {
  it("a failing check is `checks`", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    const r = await land(BR, { ...opts, checks: [["false"]] });
    expect(r.kind, text(r)).toBe("checks");
  });
});
