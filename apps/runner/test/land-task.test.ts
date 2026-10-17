import "./land-timeout.ts";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, type Http } from "../src/land.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
// `git merge --no-ff` needs an identity; the fixture only sets one per command
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });

async function setup() {
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
  const cmd = (c: object) => store.submit(c as never);
  await cmd({ type: "card.open", key: "o", actor: "owner", card: "A", owner: "o", needsDevice: false });
  await cmd({ type: "card.approve", key: "a", actor: "lead", card: "A" });
  await cmd({ type: "task.define", key: "d", actor: "lead", task: "my-task", title: "t", stream: "s", milestone: null, deps: [], owner: "o", writes: ["a.txt"], devices: [], evidence: null });
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "my-task", owner: "o", writes: ["a.txt"] }] }));
  const submit = (c: object) => http.post("/api/commands", c);
  const ready = async () => {
    const sha = fx.commit(fx.worktree("card/A"), "a.txt");
    await http.post("/api/reconcile", {});
    await cmd({ type: "card.screen", key: "s", actor: "script", card: "A", sha, pass: true });
    await cmd({ type: "card.review", key: "r", actor: "reviewer", card: "A", sha, signedBy: "rev", accept: true });
    return sha;
  };
  return { fx, store, http, ready, opts: { http, cwd: fx.root, checks: [["true"]], submit, ci: false as const } };
}
const task = async (s: Store) => (await s.board()).plan.tasks.find((t) => t.id === "my-task")!;

describe("fw land --task", () => {
  it("merges with --no-ff and a Task trailer, records task.done with the merge commit as evidence", async () => {
    const { fx, store, ready, opts } = await setup();
    await ready();
    const r = await land("card/A", { ...opts, task: "my-task" });
    expect(r.ok).toBe(true);
    const merge = fx.git(fx.root, "rev-parse", "main");
    expect(fx.git(fx.root, "rev-list", "--parents", "-n1", "main").split(" ")).toHaveLength(3);
    expect(fx.git(fx.root, "log", "-1", "--format=%B", "main")).toContain("Task: my-task");
    expect(await task(store)).toMatchObject({ state: "done", evidence: merge });
    expect(store.readEvents().filter((e) => e.type === "task.done")).toHaveLength(1); // reconciler and land share the key
  });

  it("prints a link built from origin, derived at runtime", async () => {
    const { fx, ready, opts } = await setup();
    fx.git(fx.root, "remote", "add", "origin", "git@example.invalid:o/r.git");
    await ready();
    const r = await land("card/A", { ...opts, task: "my-task" });
    expect(r.lines.join("\n")).toContain(`https://example.invalid/o/r/commit/${fx.git(fx.root, "rev-parse", "main")}`);
  });

  it("refuses an unknown task before touching main", async () => {
    const { fx, ready, opts } = await setup();
    await ready();
    const before = fx.git(fx.root, "rev-parse", "main");
    const r = await land("card/A", { ...opts, task: "nope" });
    expect(r.ok).toBe(false);
    expect(r.lines.join("\n")).toMatch(/unknown task/);
    expect(fx.git(fx.root, "rev-parse", "main")).toBe(before);
  });

  it("without --task still fast-forwards (with an explicit --allow) and records no task", async () => {
    const { fx, store, ready, opts } = await setup();
    const sha = await ready();
    expect((await land("card/A", { ...opts, allow: ["a.txt"] })).ok).toBe(true);
    expect(fx.git(fx.root, "rev-parse", "main")).toBe(sha);
    expect((await task(store)).state).not.toBe("done");
  });
});
