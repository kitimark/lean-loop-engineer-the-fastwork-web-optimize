// Task land-sha-pin: this test covers the scope diff and the merge (the ref moves inside the first GET /api/plan,
// after the behind check and the render guard); the behind check runs synchronously right after the pin with no
// await between them, and the render guard's pin is covered by land-render-guard.test.ts.
import "./land-timeout.ts";
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { afterEach, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, type Http } from "../src/land.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
const BR = "worktree-agent-t1";
const WRITES = ["src/**"];

it("the branch ref moves after the pin (during the task read): scope and merge judge only the pinned tip", async () => {
  const fx = makeRepo();
  const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  const app = createApp(store, undefined, new Reconciler(store, fx.root));
  const wt0 = fx.worktree(BR);
  const sha = fx.commit(wt0, "src/a.ts");
  let moved = false;
  const http: Http = {
    get: async (p) => {
      if (p === "/api/plan" && !moved) { moved = true; fx.commit(wt0, "docs/outside.md"); } // the ref moves after the pin
      const r = await app.request(p);
      return { status: r.status, body: await r.json() };
    },
    post: async (p, b) => {
      const r = await app.request(p, { method: "POST", body: JSON.stringify(b), headers: { "content-type": "application/json" } });
      return { status: r.status, body: await r.json() };
    },
  };
  await store.submit({ type: "task.define", key: "d", actor: "lead", task: "t1", title: "t", stream: "s", milestone: null, deps: [], owner: "builder", writes: WRITES, devices: [], evidence: null } as never);
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "t1", owner: "builder", stream: "s", writes: WRITES, evidence: null }] }, null, 1) + "\n");
  fx.git(fx.root, "add", "--", "docs/team/work-graph.json");
  fx.git(fx.root, "commit", "-q", "-m", "work graph");
  const r = await land(BR, { http, cwd: fx.root, checks: [["true"]], ci: false as const, task: "t1", retryMs: 1, lockWaitMs: 0 });
  expect(r.ok, r.lines.join("\n")).toBe(true);
  expect(moved).toBe(true);
  expect(fx.git(fx.root, "rev-parse", BR)).not.toBe(sha);
  expect(fx.git(fx.root, "rev-parse", "main^2")).toBe(sha);
  expect(fx.git(fx.root, "ls-tree", "-r", "--name-only", "main")).not.toContain("docs/outside.md");
});
