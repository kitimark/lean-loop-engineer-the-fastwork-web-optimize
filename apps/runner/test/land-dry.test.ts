import "./land-timeout.ts";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dryRun, exitCode, outcome, outcomeKind, parseVerdict } from "../src/land-verdict.ts";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { dryBase, dryLintArgv, dryMerge, dryOutcome, land, LOCAL_TESTS, type DryBase, type Http } from "../src/land.ts";
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
  it("writes its spans under a dry prefix (dry total), apart from the real land's history", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    const file = join(mkdtempSync(join(tmpdir(), "fw-dry-span-")), "timings.jsonl");
    process.env.FW_TIMINGS_FILE = file;
    try { await land(BR, { ...opts, dry: true, ...reads(["true"]), dryLints: [] }); } finally { delete process.env.FW_TIMINGS_FILE; }
    const steps = readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => (JSON.parse(l) as { tool: string; step: string }));
    expect(steps.filter((x) => x.tool === "fw land").map((x) => x.step)).toContain("dry total");
    expect(steps.filter((x) => x.tool === "fw land" && !x.step.startsWith("dry "))).toEqual([]);
  });
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
  it("path-pix 4 -> 6 (incident 2026-10-24): a workflow file change runs the overflow width test and the dry land refuses the stale row", async () => {
    const { fx, wt, opts } = await setup([".github/**"]);
    fx.commit(wt, ".github/workflows/path-pix.yml");
    const real = LOCAL_TESTS.find((x) => x.id === "runner:overflow-widths")!;
    const stale = { ...real, argv: ["sh", "-c", "echo 'path-pix.yml: Lean widths row (derived 6): expected 4 to be greater than or equal to 6'; exit 1"] };
    const bad = await land(BR, { ...opts, dry: true, ...reads(["true"], false), dryLints: [], dryLocal: [stale] });
    expect(bad.ok).toBe(false);
    expect(bad.kind).toBe("lint");
    expect(text(bad)).toContain("derived 6");
    const ok = await land(BR, { ...opts, dry: true, ...reads(["true"], false), dryLints: [], dryLocal: [{ ...stale, argv: ["true"] }] });
    expect(ok.kind).toBe("dry");
    expect(text(ok)).toContain("dry: local tests ok (runner:overflow-widths)");
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
  it("behind main by one unrelated commit: git merge-tree merges cleanly, the scope sees only the branch's path, VERDICT dry", async () => {
    const { fx, wt, opts, snap } = await setup();
    fx.commit(wt, "src/a.ts");
    fx.commit(fx.root, "docs/other.md");
    const before = snap();
    const r = await land(BR, { ...opts, dry: true, ...reads(["true"]), dryLints: [] });
    expect(r.kind, text(r)).toBe("dry");
    expect(text(r)).toContain("scope ok (1 files)");
    expect(dryRun(r.outcome!, "t1").at(-1)).toBe("VERDICT dry t1");
    expect(snap()).toEqual(before);
  });
  it("behind main, both sides made the same change to a path outside the writes: VERDICT scope, as the real land", async () => {
    const { fx, wt, opts, snap } = await setup();
    fx.commit(wt, "src/a.ts");
    fx.commit(wt, "docs/same.md", "same\n");
    fx.commit(fx.root, "docs/same.md", "same\n");
    const before = snap();
    const r = await land(BR, { ...opts, dry: true, ...reads(["true"]), dryLints: [] });
    expect(r.kind, text(r)).toBe("scope");
    expect(snap()).toEqual(before);
  });
  it("behind main with a conflicting change to one file: VERDICT conflict, main untouched", async () => {
    const { fx, wt, opts, snap } = await setup();
    fx.commit(fx.root, "src/a.ts", "base\n");
    fx.git(wt, "merge", "-q", "main");
    fx.commit(wt, "src/a.ts", "branch\n");
    fx.commit(fx.root, "src/a.ts", "main\n");
    const before = snap();
    const r = await land(BR, { ...opts, dry: true, ...reads(["true"]), dryLints: [] });
    expect(r.kind, text(r)).toBe("conflict");
    expect(dryRun(r.outcome!, "t1").at(-1)).toBe("VERDICT conflict t1");
    expect(snap()).toEqual(before);
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
    const part = "apps/site/src/parts/nav/index.tsx";
    expect(dryLintArgv(dir, [part])).toEqual([["node", "scripts/ci-paths.mjs", "--check"]]);
    mkdirSync(join(dir, "apps/site/scripts"), { recursive: true }); writeFileSync(join(dir, "apps/site/scripts/part-footprint.mjs"), "");
    expect(dryLintArgv(dir, [part])).toEqual([["node", "scripts/ci-paths.mjs", "--check"], ["node", "apps/site/scripts/part-footprint.mjs", "--check"]]);
    expect(dryLintArgv(dir, ["apps/site/src/main.tsx"])).toEqual([["node", "scripts/ci-paths.mjs", "--check"]]);
  });
  it("the default plan runs the footprint check on a part edit and refuses a stale footprint as lint (incident inc-dry-gen-stale)", async () => {
    const { fx, wt, opts } = await setup(["apps/site/src/**"]);
    const stub = "import fs from 'node:fs';\nif (fs.readFileSync('apps/site/src/parts/nav/index.tsx', 'utf8') !== 'fresh') { console.error('part-footprint: footprint.gen.json differs from the extraction (run --write)'); process.exit(1); }\n";
    fx.commit(fx.root, "apps/site/scripts/part-footprint.mjs", stub);
    fx.commit(fx.root, "apps/site/src/parts/nav/index.tsx", "fresh");
    fx.git(wt, "merge", "-q", "main");
    const base = { ...opts, dry: true, ...reads(["true"]), dryLocal: [] };
    fx.commit(wt, "apps/site/src/main.tsx", "x");
    expect((await land(BR, base)).kind).toBe("dry");
    fx.commit(wt, "apps/site/src/parts/nav/index.tsx", "comment cut");
    const stale = await land(BR, base);
    expect(stale.kind, text(stale)).toBe("lint");
    expect(text(stale)).toContain("footprint.gen.json differs");
  });
  it("every dry result carries its stage outcome, its kind is the outcome's kind, and dryRun prints exactly one VERDICT line", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "other/b.ts");
    const results = [
      await land(BR, { ...opts, dry: true, ...reads(["true"]) }),
      await land("no-such-branch", { ...opts, dry: true }),
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

type MergeRow = { name: string; request: Record<string, unknown> & { op: string }; response: Record<string, unknown> };
const mergeRows: MergeRow[] = readFileSync(join(dirname(new URL(import.meta.url).pathname), "../../../packages/contracts/golden/console/land-dry-merge.jsonl"), "utf8")
  .trim().split("\n").map((l) => JSON.parse(l));

function writeTree(fx: ReturnType<typeof makeRepo>, dir: string, files: Record<string, string>, all: string[]) {
  for (const p of all) {
    if (p in files) writeFileSync(join(dir, p), `${p}:${files[p]}\n`);
    else if (existsSync(join(dir, p))) rmSync(join(dir, p));
  }
  fx.git(dir, "add", "-A");
  fx.git(dir, "commit", "-q", "--allow-empty", "-m", "tree");
}

describe("the dry land's merge vs the Lean golden (land-dry-merge.jsonl)", () => {
  it("has base, kind and merge-tree rows", () => {
    for (const op of ["landDry.base", "landDry.baseKind", "landDry.mergeTree"]) expect(mergeRows.some((r) => r.request.op === op), op).toBe(true);
  });
  for (const g of mergeRows) it(g.name, () => {
    const q = g.request;
    if (q.op === "landDry.base") expect(g.response).toEqual({ base: dryBase(q.behind as boolean, q.mergeClean as boolean) });
    else if (q.op === "landDry.baseKind") {
      const oc = dryOutcome(q.base as DryBase, { own: q.own as boolean, scope: q.scope as boolean, merges: q.merges as boolean, reads: !(q.readsSelected as boolean) || (q.readsTest as boolean), lints: q.lints as boolean });
      expect(g.response).toEqual({ kind: outcomeKind(oc), outcome: oc });
    } else if (q.op === "landDry.mergeTree") {
      const [b, m, t] = [q.base, q.main, q.branch] as Record<string, string>[];
      const all = [...new Set([...Object.keys(b!), ...Object.keys(m!), ...Object.keys(t!)])];
      const fx = makeRepo();
      writeTree(fx, fx.root, b!, all);
      const wt = fx.worktree(BR);
      writeTree(fx, fx.root, m!, all);
      writeTree(fx, wt, t!, all);
      const mainSha = fx.git(fx.root, "rev-parse", "main");
      const r = dryMerge(fx.root, mainSha, fx.git(fx.root, "rev-parse", BR));
      expect({ clean: r !== null, changed: r?.changed ?? [], dryBase: dryBase(true, r !== null) }).toEqual({ clean: g.response.clean, changed: g.response.changed, dryBase: g.response.dryBase });
      expect(fx.git(fx.root, "rev-parse", "main")).toBe(mainSha);
      expect(fx.git(fx.root, "status", "--porcelain")).toBe("");
    } else throw new Error(`unknown op ${q.op}`);
  });
});
