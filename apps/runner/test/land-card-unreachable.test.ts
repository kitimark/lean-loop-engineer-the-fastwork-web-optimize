// Task land-queue-unreachable: a card branch whose request_land hits an unreachable console aborts its merge before the error
// reaches the queue (the queue's retry must never start a land on a main checkout with an open merge).
import "./land-timeout.ts";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, type Http } from "../src/land.ts";
import { ConsoleUnreachable } from "../src/land-queue.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });

async function setup() {
  const fx = makeRepo();
  const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  const app = createApp(store, undefined, new Reconciler(store, fx.root));
  const http: Http = {
    get: async (p) => { const r = await app.request(p); return { status: r.status, body: await r.json() }; },
    post: async (p, b) => {
      const r = await app.request(p, { method: "POST", body: JSON.stringify(b), headers: { "content-type": "application/json", "x-fw-secret": readFileSync(join(fx.consoleDir, "secret"), "utf8").trim() } });
      return { status: r.status, body: await r.json() };
    },
  };
  const cmd = (c: object) => store.submit(c as never);
  await cmd({ type: "card.open", key: "o", actor: "owner", card: "A", owner: "o", needsDevice: false });
  await cmd({ type: "card.approve", key: "a", actor: "lead", card: "A" });
  await cmd({ type: "task.define", key: "d", actor: "lead", task: "my-task", title: "t", stream: "s", milestone: null, deps: [], owner: "o", writes: ["a.txt"], devices: [], evidence: null });
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "my-task", owner: "o", writes: ["a.txt"] }] }));
  const sha = fx.commit(fx.worktree("card/A"), "a.txt");
  await http.post("/api/reconcile", {});
  await cmd({ type: "card.screen", key: "s", actor: "script", card: "A", sha, pass: true });
  await cmd({ type: "card.review", key: "r", actor: "reviewer", card: "A", sha, signedBy: "rev", accept: true });
  return { fx, http };
}

describe("card branch land with an unreachable console at the land request", () => {
  it("aborts the merge, leaves main unchanged and no open merge, then throws ConsoleUnreachable", async () => {
    const { fx, http } = await setup();
    const before = fx.git(fx.root, "rev-parse", "main");
    const submit = async (): Promise<{ status: number; body: any }> => { throw new ConsoleUnreachable("http://127.0.0.1:1", new Error("connect ECONNREFUSED")); };
    await expect(land("card/A", { http, cwd: fx.root, checks: [["true"]], submit, ci: false as const, prelock: false, task: "my-task" })).rejects.toBeInstanceOf(ConsoleUnreachable);
    expect(fx.git(fx.root, "rev-parse", "main")).toBe(before);
    expect(() => fx.git(fx.root, "rev-parse", "-q", "--verify", "MERGE_HEAD")).toThrow(); // no open merge
    expect(fx.git(fx.root, "status", "--porcelain", "--untracked-files=no")).toBe("");
    // the retry (the queue's next attempt) lands
    const again = await land("card/A", { http, cwd: fx.root, checks: [["true"]], submit: (c: object) => http.post("/api/commands", c), ci: false as const, prelock: false, task: "my-task" });
    expect(again.ok).toBe(true);
  });
});
