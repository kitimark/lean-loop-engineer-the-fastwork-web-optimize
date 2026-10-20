// Task land-legs-followups: `fw land` prints each `remote:` line once (it goes to stderr and the land log, not also to the result lines).
import "./land-timeout.ts";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, type Http } from "../src/land.ts";
import type { Adapter } from "../src/land-remote.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; vi.restoreAllMocks(); });
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });
process.env.FW_CORE_BIN ??= join(dirname(fileURLToPath(import.meta.url)), "../../../lean/.lake/build/bin/fwcore"); // the fixture repo has no build of its own
const BR = "worktree-agent-t1";

describe("fw land remote tier output", () => {
  it("each remote: line appears once across stderr and the result lines", async () => {
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
    const writes = ["apps/runner/**"];
    await store.submit({ type: "task.define", key: "d", actor: "lead", task: "t1", title: "t", stream: "s", milestone: null, deps: [], owner: "builder", writes, devices: [], evidence: null } as never);
    mkdirSync(join(fx.root, "docs/team"), { recursive: true });
    mkdirSync(join(fx.root, "apps/runner"), { recursive: true });
    writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "t1", owner: "builder", stream: "s", writes, evidence: null }] }, null, 1) + "\n");
    writeFileSync(join(fx.root, "apps/runner/package.json"), JSON.stringify({ name: "r", scripts: { test: "true" } }) + "\n");
    fx.git(fx.root, "add", "--", "docs/team/work-graph.json", "apps/runner/package.json");
    fx.git(fx.root, "commit", "-q", "-m", "work graph");
    const wt = fx.worktree(BR);
    fx.commit(wt, "apps/runner/src/a.ts");
    const adapter: Adapter = {
      provider: "github",
      async start() { return { provider: "github", branch: "b", marker: "m" } as never; },
      async poll(_h, c) { return { run: { provider: "github", sha: c.mergeSha, laneId: c.want.laneId, laneDigest: c.want.laneDigest, state: "fail" }, note: "probe note" } as never; },
    };
    const err: string[] = [];
    vi.spyOn(process.stderr, "write").mockImplementation(((s: string | Uint8Array) => { err.push(String(s)); return true; }) as never);
    const r = await land(BR, { http, cwd: fx.root, ci: false, task: "t1", retryMs: 1, lockWaitMs: 0, remote: { adapters: { github: adapter }, sliceS: 0.05, deadlineS: 5 } });
    const all = [...err.join("").split("\n"), ...r.lines].filter((l) => l.startsWith("remote:"));
    expect(all.length, r.lines.join("\n")).toBeGreaterThan(1);
    expect(all.some((l) => l.includes("probe note"))).toBe(true);
    expect(new Set(all).size).toBe(all.length);
  });
});
