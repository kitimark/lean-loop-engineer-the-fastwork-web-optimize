// `fw land` after the merge commit: a dropped request never fails the landing (retry once, then the remaining steps
// are listed with their commands, exit stays ok); evidence lands inside the merge commit; check output goes to a log.
import "./land-timeout.ts";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, loopback, type Http } from "../src/land.ts";
import { syncRefusal } from "../src/plan.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });
const BR = "worktree-agent-p1";

async function setup() {
  const fx = makeRepo();
  const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  const app = createApp(store, undefined, new Reconciler(store, fx.root));
  const real: Http = {
    get: async (p) => { const r = await app.request(p); return { status: r.status, body: await r.json() }; },
    post: async (p, b) => {
      const r = await app.request(p, { method: "POST", body: JSON.stringify(b), headers: { "content-type": "application/json" } });
      return { status: r.status, body: await r.json() };
    },
  };
  await store.submit({ type: "task.define", key: "d", actor: "lead", task: "t1", title: "t", stream: "s", milestone: null, deps: [], owner: "builder", writes: ["src/**"], devices: [], evidence: null } as never);
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "t1", owner: "builder", writes: ["src/**"], evidence: null }] }, null, 1) + "\n");
  fx.git(fx.root, "add", "--", "docs/team/work-graph.json");
  fx.git(fx.root, "commit", "-q", "-m", "work graph");
  const wt = fx.worktree(BR);
  const tip = fx.commit(wt, "src/a.ts");
  return { fx, real, wt, tip, base: { cwd: fx.root, checks: [["true"]], ci: false as const, task: "t1", retryMs: 1 } };
}
const text = (r: { lines: string[] }) => r.lines.join("\n");
/** a console that drops the first `n` requests whose path matches */
const dropping = (h: Http, re: RegExp, n: number, when: () => boolean = () => true): Http => {
  let left = n;
  const gate = (p: string) => { if (when() && re.test(p) && left > 0) { left--; throw new TypeError("fetch failed"); } };
  return { get: async (p) => { gate(p); return h.get(p); }, post: async (p, b) => { gate(p); return h.post(p, b); } };
};

describe("fw land after the commit", () => {
  it("a console that drops every request: main is merged, cleanup runs, the rest is listed with commands, ok", async () => {
    const { fx, real, base } = await setup();
    let afterCalls = 0;
    const r = await land(BR, { ...base, http: dropping(real, /./, 99, () => fx.git(fx.root, "rev-list", "--merges", "-n1", "main") !== ""), base: "http://127.0.0.1:8787", after: async () => { afterCalls++; throw new Error("fetch failed"); } });
    expect(r.ok).toBe(true);
    expect(fx.git(fx.root, "log", "-1", "--format=%B", "main")).toContain("Task: t1");
    expect(fx.git(fx.root, "branch", "--list", BR)).toBe(""); // cleanup still ran
    expect(afterCalls).toBe(2); // retried once
    const t = text(r);
    expect(t).toContain("WARNING");
    expect(t).toContain("reconcile: curl -s -X POST");
    expect(t).toContain("http://127.0.0.1:8787/api/reconcile");
    expect(t).toContain("plan sync: pnpm fw plan sync docs/team/work-graph.json");
  });

  it("a request dropped once is retried and nothing is reported", async () => {
    const { real, base } = await setup();
    const r = await land(BR, { ...base, http: dropping(real, /reconcile/, 1) });
    expect(r.ok).toBe(true);
    expect(text(r)).not.toContain("WARNING");
    expect(text(r)).toMatch(/task t1 done/);
  });

  it("writes the branch head's short sha as evidence inside the merge commit, so the tree is clean", async () => {
    const { fx, real, tip, base } = await setup();
    const r = await land(BR, { ...base, http: real });
    expect(r.ok).toBe(true);
    const g = JSON.parse(fx.git(fx.root, "show", "main:docs/team/work-graph.json"));
    expect(g.tasks[0].evidence).toBe(tip.slice(0, 7));
    expect(fx.git(fx.root, "status", "--porcelain", "--untracked-files=no")).toBe("");
    expect(fx.git(fx.root, "rev-list", "--parents", "-n1", "main").split(" ")).toHaveLength(3); // the merge commit holds it
  });

  it("parallel checks: one failing among several is reported alone and refuses; two failing are both reported", async () => {
    const { fx, real, base } = await setup();
    const bad = (n: string) => ["sh", "-c", `echo boom-${n}; exit 1`];
    const r1 = await land(BR, { ...base, http: real, concurrency: 4, checks: [["true"], bad("a"), ["true"], ["true"]] });
    expect(r1.ok).toBe(false);
    const t1 = text(r1);
    expect(t1.match(/check FAILED/g)).toHaveLength(1);
    expect(t1).toContain("boom-a");
    expect(t1.match(/check ok: true/g)).toHaveLength(3);
    const r2 = await land(BR, { ...base, http: real, concurrency: 4, checks: [bad("a"), ["true"], bad("b")] });
    expect(r2.ok).toBe(false);
    const t2 = text(r2);
    expect(t2.match(/check FAILED/g)).toHaveLength(2);
    expect(t2).toContain("boom-a");
    expect(t2).toContain("boom-b");
    expect(fx.git(fx.root, "branch", "--list", BR)).toContain(BR); // main unchanged
  });

  it("parallel checks overlap (pool of 3): each waits until all three have started, which a sequential run could never satisfy", async () => {
    const { fx, real, base } = await setup();
    const d = join(fx.root, "..", "rendezvous");
    mkdirSync(d, { recursive: true });
    // bounded by a count of polls, not by the clock: a sequential pool leaves it at 3 started files only after the first check gave up
    const rv = (n: number) => ["sh", "-c", `touch ${d}/${n}; i=0; while [ $(ls ${d} | wc -l) -lt 3 ]; do i=$((i+1)); [ $i -gt 6000 ] && exit 1; sleep 0.05; done`];
    const r = await land(BR, { ...base, http: real, concurrency: 3, checks: [rv(1), rv(2), rv(3)] });
    expect(r.ok, r.lines.join("\n")).toBe(true);
  });

  it("check output goes to a log file; a failure prints one FAILED line, the log path and at most 30 lines", async () => {
    const { fx, real, base } = await setup();
    const noisy = ["sh", "-c", "i=0; while [ $i -lt 200 ]; do echo noise $i; i=$((i+1)); done; exit 1"];
    const r = await land(BR, { ...base, http: real, checks: [["true"], noisy] });
    expect(r.ok).toBe(false);
    const t = text(r);
    expect(t).toContain("check ok: true");
    expect(t).toContain("check FAILED: sh -c");
    const log = /log: (\S+)/.exec(t)![1]!;
    expect(log).toMatch(/\.fw-console\/land-logs\/t1-[0-9a-f]{7}\.log$/);
    expect(existsSync(log)).toBe(true);
    expect(readFileSync(log, "utf8")).toContain("noise 0");
    expect(t).not.toContain("noise 100\n");
    expect(t.split("\n").filter((l) => l.startsWith("noise")).length).toBe(30);
    expect(fx.git(fx.root, "branch", "--list", BR)).toContain(BR); // main unchanged
  });
});

describe("plan sync location", () => {
  it("is allowed in the main checkout at main, refused in a linked worktree and on another branch", async () => {
    const { fx } = await setup();
    expect(syncRefusal(fx.root)).toBeNull();
    expect(syncRefusal(fx.worktree("draft-x"))).toMatch(/linked worktree/);
    fx.git(fx.root, "checkout", "-q", "-b", "draft-y");
    expect(syncRefusal(fx.root)).toMatch(/HEAD is draft-y, not main/);
  });
  it("dials the IPv4 loopback for localhost", () => {
    expect(loopback("http://localhost:8787")).toBe("http://127.0.0.1:8787");
    expect(loopback("http://127.0.0.1:1")).toBe("http://127.0.0.1:1");
    expect(loopback("http://localhost.example:1")).toBe("http://localhost.example:1");
  });
});
