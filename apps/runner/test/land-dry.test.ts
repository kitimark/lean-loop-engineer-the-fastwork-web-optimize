// `fw land --dry` (task land-dry; Lean Fw.Console.LandDry: dry_pass_land_pass, dry_refusal_is_land_refusal, handback_pass_land_pass).
// A dry land runs the real land's scope, merge and reads stages and nothing else: no lock, no queue, main untouched.
import "./land-timeout.ts";
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dryRun, exitCode, outcome, outcomeKind, parseVerdict } from "../src/land-verdict.ts";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { dryLintArgv, land, type Http } from "../src/land.ts";
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
  it("a selected local test that fails refuses with its name; one that passes or is not selected does not (task land-tier-compose-test)", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    const t = (cmd: string, reads = ["src/**"]) => ({ dryLocal: [{ id: "console-api:compose", reads, argv: ["sh", "-c", cmd] }] });
    const bad = await land(BR, { ...opts, dry: true, ...reads(["true"]), dryLints: [], ...t("echo FAIL test/compose.test.ts; exit 1") });
    expect(bad.ok).toBe(false);
    expect(bad.kind).toBe("lint");
    expect(text(bad)).toContain("test/compose.test.ts");
    const ok = await land(BR, { ...opts, dry: true, ...reads(["true"]), dryLints: [], ...t("exit 0") });
    expect(ok.kind).toBe("dry");
    expect(text(ok)).toContain("dry: local tests ok (console-api:compose)");
    const idle = await land(BR, { ...opts, dry: true, ...reads(["true"]), dryLints: [], ...t("exit 1", ["docs/**"]) });
    expect(idle.kind).toBe("dry");
  });
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
  it("empty: a branch with no commit of its own is `empty`, a success (exit 0), and it prints one VERDICT line", async () => {
    const { opts } = await setup();
    const r = await land(BR, { ...opts, dry: true, ...reads(["true"]) });
    expect(r.ok, text(r)).toBe(true);
    expect(r.kind, text(r)).toBe("empty");
    expect(exitCode(r.kind!)).toBe(0);
  });
  it("lint: a failing fast lint is refused as lint (exit 17) after reads; a passing one lets the dry land pass", async () => {
    const { fx, wt, opts, snap } = await setup();
    fx.commit(wt, "src/a.ts");
    const before = snap();
    const bad = await land(BR, { ...opts, dry: true, ...reads(["true"]), dryLints: [["sh", "-c", "echo 18 defs without math; exit 1"]] });
    expect(bad.ok).toBe(false);
    expect(bad.kind, text(bad)).toBe("lint");
    expect(exitCode(bad.kind!)).toBe(17);
    expect(text(bad)).toContain("18 defs without math");
    expect(snap()).toEqual(before);
    const ok = await land(BR, { ...opts, dry: true, ...reads(["true"]), dryLints: [["true"], ["true"]] });
    expect(ok.kind, text(ok)).toBe("dry");
    // reads refuses before lint
    const both = await land(BR, { ...opts, dry: true, ...reads(["sh", "-c", "echo land-inputs.test; exit 1"]), dryLints: [["false"]] });
    expect(both.kind, text(both)).toBe("reads");
  });
  it("the default fast lints: ci-paths always (when the tree has it), the axiom check only when the change touches lean/", () => {
    const dir = mkdtempSync(join(tmpdir(), "dryl-"));
    expect(dryLintArgv(dir, ["lean/Fw/X.lean"])).toEqual([]);
    mkdirSync(join(dir, "scripts"), { recursive: true }); writeFileSync(join(dir, "scripts/ci-paths.mjs"), "");
    mkdirSync(join(dir, "lean/scripts"), { recursive: true }); writeFileSync(join(dir, "lean/scripts/axiom-check.sh"), "");
    expect(dryLintArgv(dir, ["apps/x.ts"])).toEqual([["node", "scripts/ci-paths.mjs", "--check"]]);
    const withLean = dryLintArgv(dir, ["apps/x.ts", "lean/Fw/X.lean"]);
    expect(withLean).toHaveLength(2);
    expect(withLean[1]!.join(" ")).toContain("axiom-check.sh");
  });
  it("every dry result carries its stage outcome, its kind is the outcome's kind, and dryRun prints exactly one VERDICT line", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "other/b.ts");
    const results = [
      await land(BR, { ...opts, dry: true, ...reads(["true"]) }), // scope
      await land("no-such-branch", { ...opts, dry: true }), // outside the modelled stages: threw
    ];
    for (const r of results) {
      expect(r.outcome, text(r)).toBeDefined();
      expect(r.kind).toBe(outcomeKind(r.outcome!));
      const out = dryRun(r.outcome!, "t1");
      expect(out.filter((l) => l.startsWith("VERDICT ")).length).toBe(1);
      expect(parseVerdict(out.join("\n"))?.kind).toBe(r.kind);
    }
    expect(results.map((r) => r.kind)).toEqual(["scope", "unknown"]);
    expect(dryRun(results[0]!.outcome!, "t1")).toEqual(["dry: exception ok", "dry: stale ok", "dry: empty ok", "VERDICT scope t1"]);
    expect(outcome({ threw: true }).threw).toBe(true);
  });
  it("a real land prints `lint` for a lint/compile check failure, as the dry land does, and `checks` for another failure", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    const lint = await land(BR, { ...opts, checks: [["sh", "-c", "echo 'check: FAILED stage: axiom check'; exit 1"]] });
    expect(lint.kind, text(lint)).toBe("lint");
    const mixed = await land(BR, { ...opts, checks: [["sh", "-c", "echo 'check: FAILED stage: axiom check'; echo 'check: FAILED stage: lake test'; exit 1"]] });
    expect(mixed.kind, text(mixed)).toBe("checks");
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
