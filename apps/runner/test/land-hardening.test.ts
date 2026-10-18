// Incident repros for `fw land` (docs/team/incidents/ledger.json): inc-commit-during-land, inc-land-scope-registrations,
// inc-agent-on-ci-branch, inc-fw-lean-import-conflict. Decisions are Lean (Fw.Console.Land); these tests drive the real git.
import "./land-timeout.ts";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, spawnSync } from "node:child_process";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, type Http } from "../src/land.ts";
import { askCore, coreBin, lockFile } from "../hooks/land-guard.mjs";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });

const here = dirname(fileURLToPath(import.meta.url));
const GUARD = join(here, "../hooks/land-guard.mjs");
const BR = "worktree-agent-t1";

async function setup(o: { id?: string; stream?: string; writes?: string[]; br?: string } = {}) {
  const id = o.id ?? "t1", stream = o.stream ?? "s", writes = o.writes ?? ["src/**"], br = o.br ?? BR;
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
  await store.submit({ type: "task.define", key: "d", actor: "lead", task: id, title: "t", stream, milestone: null, deps: [], owner: "builder", writes, devices: [], evidence: null } as never);
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id, owner: "builder", stream, writes }] }));
  const wt = fx.worktree(br);
  const opts = { http, cwd: fx.root, checks: [["true"]], ci: false as const, task: id };
  const mainSha = () => fx.git(fx.root, "rev-parse", "main");
  const noMerge = () => expect(() => fx.git(fx.root, "rev-parse", "-q", "--verify", "MERGE_HEAD")).toThrow();
  const lock = () => lockFile(fx.root);
  return { fx, wt, opts, mainSha, noMerge, lock };
}
const text = (r: { lines: string[] }) => r.lines.join("\n");
const sh = (script: string) => ["sh", "-c", script];

/** A hook dir whose pre-commit is the land guard, as scripts/hooks/pre-commit installs it. */
function hookDir(fx: { root: string; git: (cwd: string, ...a: string[]) => string }): void {
  const d = mkdtempSync(join(realpathSync(tmpdir()), "fw-hooks-"));
  writeFileSync(join(d, "pre-commit"), `#!/bin/sh\nexec node "${GUARD}"\n`);
  chmodSync(join(d, "pre-commit"), 0o755);
  fx.git(fx.root, "config", "core.hooksPath", d);
}

describe("inc-commit-during-land: the land lock", () => {
  it("a commit made while fw land holds the merge is refused by the hook; the land's own commit has parents (main0, tip) and the Task trailer", async () => {
    const { fx, wt, opts, lock } = await setup();
    hookDir(fx);
    const tip = fx.commit(wt, "src/a.ts");
    const main0 = fx.git(fx.root, "rev-parse", "main");
    const out = join(fx.root, "..", "intruder.out");
    const intruder = `git commit --allow-empty -q -m intruder 2>${out}.err; echo $? > ${out}`;
    const r = await land(BR, { ...opts, prelock: false, checks: [sh(intruder)] });
    expect(r.ok).toBe(true);
    expect(readFileSync(out, "utf8").trim()).not.toBe("0");
    expect(readFileSync(`${out}.err`, "utf8")).toMatch(/commit refused/);
    expect(fx.git(fx.root, "rev-list", "--parents", "-n1", "main").split(" ")).toEqual([fx.git(fx.root, "rev-parse", "main"), main0, tip]);
    expect(fx.git(fx.root, "log", "-1", "--format=%B", "main")).toContain("Task: t1");
    expect(fx.git(fx.root, "log", "--format=%s", "main")).not.toContain("intruder");
    expect(existsSync(lock())).toBe(false); // released
  });

  it("outside a land the hook lets commits through", async () => {
    const { fx } = await setup();
    hookDir(fx);
    fx.git(fx.root, "commit", "--allow-empty", "-q", "-m", "plain");
    expect(fx.git(fx.root, "log", "-1", "--format=%s")).toBe("plain");
  });

  it("a stale lock (dead pid) is reported, not removed, and nothing is merged", async () => {
    const { fx, wt, opts, mainSha, noMerge, lock } = await setup();
    fx.commit(wt, "src/a.ts");
    writeFileSync(lock(), JSON.stringify({ pid: 2147483646, token: "x", at: "then", branch: "other" }) + "\n");
    const before = mainSha();
    const r = await land(BR, opts);
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/stale land lock/);
    expect(text(r)).toMatch(/not removed/);
    expect(existsSync(lock())).toBe(true);
    expect(mainSha()).toBe(before); noMerge();
  });

  it("a stale lock also makes the hook refuse a commit, and says so", async () => {
    const { fx, lock } = await setup();
    hookDir(fx);
    writeFileSync(lock(), JSON.stringify({ pid: 2147483646, token: "x", at: "then", branch: "other", dir: fx.root }) + "\n");
    const p = spawnSync("git", ["commit", "--allow-empty", "-m", "x"], { cwd: fx.root, encoding: "utf8" });
    expect(p.status).not.toBe(0);
    expect(p.stderr).toMatch(/stale land lock/);
  });

  it("a live lock held by another land makes this land refuse and leaves the lock alone", async () => {
    const { fx, wt, opts, lock } = await setup();
    fx.commit(wt, "src/a.ts");
    writeFileSync(lock(), JSON.stringify({ pid: process.pid, token: "other", at: "now", branch: "b" }) + "\n");
    const r = await land(BR, { ...opts, lockWaitMs: 0 }); // the wait for a busy lock is a timer of land.ts (default 10 s); the refusal does not depend on its length
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/another fw land holds/);
    expect(existsSync(lock())).toBe(true);
  });

  it("the lock is released when a check fails", async () => {
    const { fx, wt, opts, lock, mainSha, noMerge } = await setup();
    fx.commit(wt, "src/a.ts");
    const before = mainSha();
    const r = await land(BR, { ...opts, checks: [["false"]] });
    expect(r.ok).toBe(false);
    expect(existsSync(lock())).toBe(false);
    expect(mainSha()).toBe(before); noMerge();
  });

  it("the lock is released when a check throws", async () => {
    const { fx, wt, opts, lock } = await setup();
    fx.commit(wt, "src/a.ts");
    await land(BR, { ...opts, checks: [["/nonexistent-command-xyz"]] }).catch(() => undefined);
    expect(existsSync(lock())).toBe(false);
  });

  it("MERGE_HEAD gone before the commit: nothing is committed, main is not reset, the reason is printed", async () => {
    const { fx, wt, opts, mainSha } = await setup();
    fx.commit(wt, "src/a.ts");
    const before = mainSha();
    const r = await land(BR, { ...opts, prelock: false, checks: [sh("git merge --abort")] });
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/merge state gone/);
    expect(text(r)).toMatch(/reset/);
    expect(mainSha()).toBe(before);
    expect(fx.git(fx.root, "log", "--format=%B", "main")).not.toContain("Task: t1");
  });

  it("HEAD moved under the land: no land commit, and the other commit is kept (no reset)", async () => {
    const { fx, wt, opts, mainSha } = await setup();
    fx.commit(wt, "src/a.ts");
    const before = mainSha();
    const r = await land(BR, { ...opts, prelock: false, checks: [sh("c=$(git commit-tree 'HEAD^{tree}' -p HEAD -m other) && git update-ref refs/heads/main $c")] });
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/head moved/);
    expect(mainSha()).not.toBe(before);
    expect(fx.git(fx.root, "log", "-1", "--format=%s", "main")).toBe("other");
    expect(fx.git(fx.root, "log", "--format=%B", "main")).not.toContain("Task: t1");
  });

  it("a SIGTERM during the checks aborts the merge and releases the lock", async () => {
    const { fx, wt, lock, mainSha } = await setup();
    fx.commit(wt, "src/a.ts");
    const before = mainSha();
    const script = join(realpathSync(tmpdir()), `fw-land-sig-${process.pid}.mts`);
    const landSrc = join(here, "../src/land.ts");
    const started = join(realpathSync(tmpdir()), `fw-land-sig-${process.pid}.started`);
    writeFileSync(script, [
      `import { land } from ${JSON.stringify(landSrc)};`,
      `const http = { get: async () => ({ status: 200, body: { tasks: [{ id: "t1", state: "todo", owner: "builder", stream: "s", writes: ["src/**"] }] } }), post: async () => ({ status: 200, body: { ok: true, refusals: [], scope: [], violations: [] } }) };`,
      `await land(${JSON.stringify(BR)}, { http, cwd: ${JSON.stringify(fx.root)}, prelock: false, checks: [["sh", "-c", ${JSON.stringify("touch " + started + "; exec sleep 30")}]], ci: false, task: "t1" });`,
    ].join("\n"));
    const p = spawn(process.execPath, [script], { stdio: ["ignore", "inherit", "inherit"] });
    // the check itself says it is running (merge open, lock held): no fixed pause, and `prelock: false` so that the signal
    // really arrives under the lock (with the default the checks run before the lock and this test waited 17 s for nothing)
    const t0 = Date.now();
    while (!existsSync(started) && p.exitCode === null && Date.now() - t0 < 60_000) await new Promise((r) => setTimeout(r, 20));
    expect(existsSync(started), "the check must have started").toBe(true);
    expect(existsSync(lock()), "the lock is held while the check runs").toBe(true);
    expect(p.exitCode, "the land process must still be running (in its checks)").toBeNull();
    p.kill("SIGTERM");
    await new Promise((r) => p.once("exit", r));
    expect(existsSync(lock())).toBe(false);
    expect(mainSha()).toBe(before);
    expect(() => fx.git(fx.root, "rev-parse", "-q", "--verify", "MERGE_HEAD")).toThrow();
  }, 40000);
});

describe("inc-land-scope-registrations: per-kind registration sets", () => {
  it("a port task lands its registration files without --allow", async () => {
    const { fx, wt, opts } = await setup({ id: "port-nav", stream: "port", writes: ["apps/site/src/parts/nav/**"], br: "worktree-agent-pn" });
    fx.commit(wt, "apps/site/src/parts/nav/Nav.tsx");
    fx.commit(wt, "apps/site/src/registry/index.ts");
    fx.commit(wt, "apps/site/src/App.tsx");
    fx.commit(wt, "lean/Fw/Parts/NavMount.lean");
    const r = await land("worktree-agent-pn", opts);
    expect(text(r)).not.toMatch(/REFUSED/);
    expect(r.ok).toBe(true);
  });

  it("a port task may not touch another part's Lean file or a protected path, even with --allow **", async () => {
    const { fx, wt, opts, mainSha } = await setup({ id: "port-nav", stream: "port", writes: ["apps/site/src/parts/nav/**"], br: "worktree-agent-pn" });
    const before = mainSha();
    fx.commit(wt, "lean/Fw/Parts/Hero.lean");
    fx.commit(wt, ".claude/settings.json");
    const r = await land("worktree-agent-pn", { ...opts, allow: ["**"] });
    expect(r.ok).toBe(false);
    expect(text(r)).toContain(".claude/settings.json");
    expect(mainSha()).toBe(before);
  });

  it("a measure task lands packages/measure-* and baselines; a task of another stream does not", async () => {
    const m = await setup({ id: "m1", stream: "measure", writes: ["x/**"], br: "worktree-agent-m1" });
    m.fx.commit(m.wt, "packages/measure-chromium/src/a.ts");
    m.fx.commit(m.wt, "results/baselines/b.json");
    expect((await land("worktree-agent-m1", m.opts)).ok).toBe(true);
    const o = await setup({ id: "m2", stream: "other", writes: ["x/**"], br: "worktree-agent-m2" });
    o.fx.commit(o.wt, "packages/measure-chromium/src/a.ts");
    const r = await land("worktree-agent-m2", o.opts);
    expect(r.ok).toBe(false);
    expect(text(r)).toContain("packages/measure-chromium/src/a.ts");
  });

  it("a proof task lands its Lean part files and engine golden", async () => {
    const { fx, wt, opts } = await setup({ id: "proof-hero-exit", stream: "proof", writes: ["x/**"], br: "worktree-agent-ph" });
    fx.commit(wt, "lean/Fw/Parts/HeroExitMotion.lean");
    fx.commit(wt, "packages/contracts/golden/engine/hero-exit.jsonl");
    const r = await land("worktree-agent-ph", opts);
    expect(text(r)).not.toMatch(/REFUSED/);
    expect(r.ok).toBe(true);
  });
});

describe("inc-agent-on-ci-branch: land the branch that holds the work", () => {
  it("the given branch has nothing, ci/<task> is ahead and contains it: ci/<task> is landed and the given branch is dropped", async () => {
    const { fx, wt, opts } = await setup();
    fx.git(wt, "checkout", "-q", "-b", "ci/t1");
    fx.commit(wt, "src/a.ts");
    const r = await land(BR, opts);
    expect(text(r)).toMatch(/has nothing to land; landing ci\/t1/);
    expect(r.ok).toBe(true);
    expect(fx.git(fx.root, "log", "-1", "--format=%B", "main")).toContain("Task: t1");
    expect(fx.git(fx.root, "branch", "--list", BR)).toBe("");
  });

  it("two branches qualify: refuses and names both", async () => {
    const { fx, wt, opts, mainSha } = await setup();
    fx.git(wt, "checkout", "-q", "-b", "ci/t1");
    fx.commit(wt, "src/a.ts");
    const w2 = fx.worktree("other-agent-t1");
    fx.commit(w2, "src/b.ts");
    const before = mainSha();
    const r = await land(BR, opts);
    expect(r.ok).toBe(false);
    expect(text(r)).toMatch(/ci\/t1/);
    expect(text(r)).toMatch(/other-agent-t1/);
    expect(mainSha()).toBe(before);
  });

  it("an unrelated branch that merely contains the merged one is not a candidate", async () => {
    const { fx, opts } = await setup();
    const w2 = fx.worktree("worktree-agent-zzz");
    fx.commit(w2, "src/z.ts");
    const r = await land(BR, opts); // BR sits at main with no commits; zzz is ahead of main and contains BR
    expect(text(r)).not.toMatch(/landing worktree-agent-zzz/);
  });
});

describe("inc-fw-lean-import-conflict: lean/scripts/check-imports.mjs", () => {
  const CHECK = join(here, "../../../lean/scripts/check-imports.mjs");
  const lean = (fw: string, mods: Record<string, string> = {}) => {
    const d = mkdtempSync(join(realpathSync(tmpdir()), "fw-lean-"));
    mkdirSync(join(d, "Fw"), { recursive: true });
    writeFileSync(join(d, "Fw.lean"), fw);
    for (const [m, body] of Object.entries(mods)) writeFileSync(join(d, "Fw", m), body);
    return d;
  };
  const run = (d: string) => spawnSync(process.execPath, [CHECK, d], { encoding: "utf8" });

  it("passes a clean tree", () => {
    expect(run(lean("import Fw.A\nimport Fw.B\n", { "A.lean": "def a := 1\n", "B.lean": "def b := 1\n" })).status).toBe(0);
  });
  it("fails a repeated import line (what merge=union produces)", () => {
    const r = run(lean("import Fw.A\nimport Fw.A\n", { "A.lean": "def a := 1\n" }));
    expect(r.status).not.toBe(0);
    expect(r.stdout + r.stderr).toMatch(/Fw\.A/);
  });
  it("fails a module that nothing imports", () => {
    const r = run(lean("import Fw.A\n", { "A.lean": "def a := 1\n", "Orphan.lean": "def o := 1\n" }));
    expect(r.status).not.toBe(0);
    expect(r.stdout + r.stderr).toMatch(/Fw\.Orphan/);
  });
  it("fails an import of a module that does not exist", () => {
    const r = run(lean("import Fw.A\nimport Fw.Missing\n", { "A.lean": "def a := 1\n" }));
    expect(r.status).not.toBe(0);
    expect(r.stdout + r.stderr).toMatch(/Fw\.Missing/);
  });
  it("the real lean/Fw.lean passes", () => {
    expect(spawnSync(process.execPath, [CHECK], { encoding: "utf8", cwd: join(here, "../../..") }).status).toBe(0);
  });
});

describe("golden vectors of the land ops", () => {
  const rows = (op: string) => readFileSync(join(here, `../../../packages/contracts/golden/console/${op}.jsonl`), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
  for (const op of ["console.landLock", "console.landGuard", "console.landCommit", "console.landPick", "console.landScope", "console.landPool", "console.landRetry"]) {
    it(`${op}: fwcore reproduces every row`, () => {
      expect(existsSync(coreBin())).toBe(true);
      const all = rows(op);
      expect(all.length).toBeGreaterThan(0);
      for (const row of all) {
        const got = askCore(op, row.request);
        if (row.response.error) { expect(got, JSON.stringify(row.request)).toBeNull(); continue; } // a refused request
        expect(got, JSON.stringify(row.request)).not.toBeNull();
        for (const [k, v] of Object.entries(row.response as Record<string, unknown>)) expect(got![k], `${op} ${JSON.stringify(row.request)} .${k}`).toEqual(v);
      }
    });
  }
});
