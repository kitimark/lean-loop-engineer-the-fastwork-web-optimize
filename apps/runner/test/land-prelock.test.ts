// Pre-lock land (Lean Fw.Console.LandSpeed: pre_eq_old_iff, preLand_commit_exact, prelockAction_fallback): the merge is checked in a
// land worktree with no lock; under the lock main is only fast-forwarded to the checked commit. These tests drive the real
// version control and fwcore; none asserts wall-clock time.
import "./land-timeout.ts";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, poolSize, prelockAction, type Http } from "../src/land.ts";
import { lockFile } from "../hooks/land-guard.mjs";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });

const here = dirname(fileURLToPath(import.meta.url));
const GUARD = join(here, "../hooks/land-guard.mjs");
const BR = "worktree-agent-t1";

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
  await store.submit({ type: "task.define", key: "d", actor: "lead", task: "t1", title: "t", stream: "s", milestone: null, deps: [], owner: "builder", writes: ["src/**"], devices: [], evidence: null } as never);
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "t1", owner: "builder", stream: "s", writes: ["src/**"], evidence: null }] }, null, 1) + "\n");
  fx.git(fx.root, "add", "--", "docs/team/work-graph.json");
  fx.git(fx.root, "commit", "-q", "-m", "work graph");
  const wt = fx.worktree(BR);
  const tip = fx.commit(wt, "src/a.ts");
  const opts = { http, cwd: fx.root, checks: [["true"]], ci: false as const, task: "t1", retryMs: 1, lockWaitMs: 0 };
  const main = () => fx.git(fx.root, "rev-parse", "main");
  const noMerge = () => expect(() => fx.git(fx.root, "rev-parse", "-q", "--verify", "MERGE_HEAD")).toThrow();
  return { fx, wt, tip, opts, main, noMerge };
}
const text = (r: { lines: string[] }) => r.lines.join("\n");
const sh = (script: string) => ["sh", "-c", script];
/** a shell snippet that runs `body` only inside a land worktree (the check's cwd) */
const inLandWt = (body: string) => sh(`case "$PWD" in *land-wt*) ${body};; esac`);

describe("pre-lock land", () => {
  it("succeeds: the checks run in the land worktree, main is fast-forwarded to a commit (main0, tip) with the Task trailer and the evidence, no merge is ever open", async () => {
    const { fx, tip, opts, main, noMerge } = await setup();
    const main0 = main();
    const seen = join(fx.root, "..", "seen");
    const r = await land(BR, { ...opts, checks: [sh(`pwd > ${seen}; test ! -e ${fx.root}/.git/MERGE_HEAD`)] });
    expect(r.ok, text(r)).toBe(true);
    expect(readFileSync(seen, "utf8")).toContain("land-wt");
    expect(fx.git(fx.root, "rev-list", "--parents", "-n1", "main").split(" ")).toEqual([main(), main0, tip]);
    expect(fx.git(fx.root, "log", "-1", "--format=%B", "main")).toContain("Task: t1");
    expect(JSON.parse(fx.git(fx.root, "show", "main:docs/team/work-graph.json")).tasks[0].evidence).toBe(tip.slice(0, 7));
    expect(fx.git(fx.root, "status", "--porcelain", "--untracked-files=no")).toBe("");
    noMerge();
    expect(existsSync(lockFile(fx.root))).toBe(false);
  });

  it("main moves during the checks: the land checks again against the new main, then succeeds", async () => {
    const { fx, tip, opts, main } = await setup();
    const marker = join(fx.root, "..", "moved-once");
    const move = inLandWt(`[ -e ${marker} ] || { touch ${marker}; git -C ${fx.root} commit --allow-empty -q -m moved; }`);
    const r = await land(BR, { ...opts, checks: [move] });
    expect(r.ok, text(r)).toBe(true);
    expect(text(r)).toMatch(/moved during the checks/);
    const [, p1, p2] = fx.git(fx.root, "rev-list", "--parents", "-n1", "main").split(" ");
    expect(p2).toBe(tip);
    expect(fx.git(fx.root, "log", "-1", "--format=%s", p1!)).toBe("moved"); // the new main is the first parent
    expect(main()).not.toBe(p1);
  });

  it("main keeps moving: after the bounded re-checks the locked protocol takes over and lands", async () => {
    const { fx, opts, main } = await setup();
    const count = join(fx.root, "..", "runs");
    const move = inLandWt(`echo x >> ${count}; git -C ${fx.root} commit --allow-empty -q -m moved`);
    const r = await land(BR, { ...opts, retries: 2, checks: [move] });
    expect(r.ok, text(r)).toBe(true);
    expect(text(r)).toMatch(/using the locked protocol/);
    expect(readFileSync(count, "utf8").trim().split("\n")).toHaveLength(3); // attempts 0, 1, 2: then fallback (Lean: prelockAction_fallback)
    expect(fx.git(fx.root, "rev-list", "--parents", "-n1", "main").split(" ")).toHaveLength(3);
    expect(main()).toBeTruthy();
  });

  it("a conflict: falls back to the locked protocol, which refuses with main untouched", async () => {
    const { fx, wt, opts, main, noMerge } = await setup();
    fx.commit(fx.root, "src/c.ts", "main side\n");
    fx.commit(wt, "src/c.ts", "branch side\n");
    const before = main();
    const r = await land(BR, opts);
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/using the locked protocol/);
    expect(text(r)).toMatch(/cannot merge/);
    expect(main()).toBe(before); noMerge();
    expect(existsSync(lockFile(fx.root))).toBe(false);
  });

  it("a failing check refuses with main untouched and no lock taken", async () => {
    const { fx, opts, main, noMerge } = await setup();
    const before = main();
    const r = await land(BR, { ...opts, checks: [["true"], ["false"]] });
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/check FAILED: false/);
    expect(main()).toBe(before); noMerge();
    expect(existsSync(lockFile(fx.root))).toBe(false);
    expect(fx.git(fx.root, "branch", "--list", BR)).toContain(BR);
  });

  it("a lead commit during the checks is not blocked by the hook, and does not enter the commit that was checked first", async () => {
    const { fx, tip, opts } = await setup();
    const d = mkdtempSync(join(realpathSync(tmpdir()), "fw-hooks-"));
    writeFileSync(join(d, "pre-commit"), `#!/bin/sh\nexec node "${GUARD}"\n`);
    chmodSync(join(d, "pre-commit"), 0o755);
    fx.git(fx.root, "config", "core.hooksPath", d);
    const marker = join(fx.root, "..", "lead-once"), seen = join(fx.root, "..", "lead-seen");
    // first run: the lead commits a file on main; the checked tree must not contain it. second run: it is part of the new main.
    const script = inLandWt(`if [ ! -e ${marker} ]; then touch ${marker}; [ -e lead.txt ] && echo leaked > ${seen}; echo lead > ${fx.root}/lead.txt; git -C ${fx.root} add lead.txt && git -C ${fx.root} commit -q -m lead; fi`);
    const r = await land(BR, { ...opts, checks: [script] });
    expect(r.ok, text(r)).toBe(true);
    expect(existsSync(seen)).toBe(false);
    expect(fx.git(fx.root, "log", "--format=%s", "main")).toContain("lead");
    expect(fx.git(fx.root, "rev-list", "--parents", "-n1", "main").split(" ")[1]).toBeTruthy();
    expect(fx.git(fx.root, "rev-list", "--parents", "-n1", "main").split(" ")[2]).toBe(tip);
  });

  it("the land worktree holds exactly the commit: an untracked file from an earlier run is gone", async () => {
    const { fx, opts, main } = await setup();
    const r1 = await land(BR, { ...opts, checks: [inLandWt("echo stray > stray.txt; exit 1")] });
    expect(r1.ok).toBe(false);
    expect(main()).toBeTruthy();
    const out = join(fx.root, "..", "stray-seen");
    const r2 = await land(BR, { ...opts, checks: [inLandWt(`ls stray.txt > ${out} 2>&1; true`)] });
    expect(r2.ok, text(r2)).toBe(true);
    expect(readFileSync(out, "utf8")).toMatch(/No such file/);
  });
});

describe("prelockAction: the Lean decision (golden landSpeed.prelock)", () => {
  const root = join(here, "../../..");
  const rows = readFileSync(join(root, "packages/contracts/golden/console/land-speed.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l)).filter((c) => c.request.op === "landSpeed.prelock");
  it("has rows, and the TS stand-in answers every one as Lean does", () => {
    expect(rows.length).toBeGreaterThan(3);
    for (const c of rows) expect(prelockAction(c.request.head, c.request.main0, c.request.verdict, c.request.attempt, c.request.maxRetry), c.name).toBe(c.response.action);
  });
  it("is bounded: once the retries are used a moved main never answers recheck", () => {
    for (const n of [0, 1, 3]) for (const a of [n, n + 1, n + 10]) expect(prelockAction("m1", "m0", true, a, n)).toBe("fallback");
  });
});

describe("load: the pool shrinks and a timeout is re-run alone", () => {
  it("poolSize = max 1 (cores - ceil load): Lean table (#guard poolSize) and monotone", () => {
    expect([poolSize(10, 0), poolSize(10, 3), poolSize(10, 23), poolSize(0, 0)]).toEqual([10, 7, 1, 1]);
    for (let c = 0; c < 12; c++) for (let l = 0; l < 30; l++) {
      expect(poolSize(c, l)).toBeGreaterThanOrEqual(1);
      expect(poolSize(c, l + 1)).toBeLessThanOrEqual(poolSize(c, l));
      expect(poolSize(c + 1, l)).toBeGreaterThanOrEqual(poolSize(c, l));
    }
  });
  it("a check that timed out is run once more alone and its second result counts; a plain failure is not re-run", async () => {
    const { fx, opts } = await setup();
    const runs = join(fx.root, "..", "timeout-runs");
    const flaky = sh(`echo x >> ${runs}; if [ $(wc -l < ${runs}) -lt 2 ]; then echo "Error: Test timed out in 5000ms."; exit 1; fi`);
    const r = await land(BR, { ...opts, checks: [flaky] });
    expect(r.ok, text(r)).toBe(true);
    expect(readFileSync(runs, "utf8").trim().split("\n")).toHaveLength(2);
  });
  it("a failure that is not a timeout is reported after one run", async () => {
    const { fx, opts } = await setup();
    const runs = join(fx.root, "..", "plain-runs");
    const r = await land(BR, { ...opts, checks: [sh(`echo x >> ${runs}; echo boom; exit 1`)] });
    expect(r.ok).toBe(false);
    expect(readFileSync(runs, "utf8").trim().split("\n")).toHaveLength(1);
  });
});
