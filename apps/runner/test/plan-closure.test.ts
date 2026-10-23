import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { describe, expect, it, vi } from "vitest";
import { closureFindings, freshOf, gapsOf, implied, kindOf, lintClosure, mayNeed, newErrors, owned, required, scopeBatch, type ScopeReq } from "../src/plan-closure.ts";
import { lintCli, previousGraph, syncClosureRefusal } from "../src/plan.ts";
import { coreCandidates } from "../src/watch.ts";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../../..");
const rows = readFileSync(join(root, "packages/contracts/golden/plan/writes-closure.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const paths = rows.filter((r) => r.type === "path");
const cases = rows.filter((r) => r.type === "case");
const globs = rows.filter((r) => r.type === "glob");
const gapRows = rows.filter((r) => r.type === "gaps");
const syncRows = rows.filter((r) => r.type === "sync");
const agreePaths: string[] = rows.find((r) => r.type === "agreePaths").paths;
const agreeRows = rows.filter((r) => r.type === "agree");
const timeRows = rows.filter((r) => r.type === "timeTable");
type CiPathsGaps = {
  leanScriptPaths: (text: string) => (string | null)[];
  readPath: (p: string) => string | null;
  rowGlob: (g: string) => boolean;
  gapsFrom: (scripts: { script: string; text: string }[], globs: string[]) => { script: string; path: string | null }[];
};
const ciPaths = async () => (await import(pathToFileURL(join(root, "scripts/ci-paths.mjs")).href)) as CiPathsGaps;
const task = (c:{ id: string; owner: string; stream: string; writes: string[]; done: boolean }) => ({ id: c.id, owner: c.owner, stream: c.stream, writes: c.writes, done: c.done });

describe("writes closure golden (Fw.Plan.WritesClosure)", () => {
  it("has path and case rows", () => {
    expect(paths.length).toBeGreaterThan(20);
    expect(cases.length).toBeGreaterThan(10);
  });
  it.each(paths.map((r) => [r.write, r]))("path %s", (_w, r) => {
    expect(kindOf(r.write)).toBe(r.kind);
    expect(freshOf(r.tracked, r.write)).toBe(r.fresh);
    expect(implied(kindOf(r.write))).toEqual(r.implied);
  });
  it.each(cases.map((c) => [c.name, c]))("case %s", (_n, c) => {
    expect(owned(c.writes, c.gaps)).toEqual(c.owned);
    expect(required(c.tracked, c.writes, c.gaps)).toEqual(c.required);
    expect(mayNeed(c.tracked, c.writes, c.gaps)).toEqual(c.mayNeed);
    expect(closureFindings(c.tracked, c.gaps, task(c), c.violations)).toEqual(c.findings);
  });
  it("lintClosure asks once per open row with a closure and splits the reply", async () => {
    const seen: ScopeReq[] = [];
    const c = cases.find((x) => x.name === "r322 workflow named, tables not")!;
    const out = await lintClosure([task(c), { id: "n", owner: "o", stream: "s", writes: ["docs/x.md"], done: false }], c.tracked, c.gaps,
      async (reqs) => (seen.push(...reqs), reqs.map(() => ({ violations: c.violations }))));
    expect(seen).toHaveLength(1);
    expect(seen[0]).toMatchObject({ op: "console.landScope", names: [c.id, c.owner], allow: [], task: c.id, stream: c.stream, paths: [...c.required, ...c.mayNeed] });
    expect(out).toEqual(c.findings);
  });
  it("the checkout has no gap: every literal read of lean/scripts/*.sh is a lean.yml input (ci-paths holds)", async () => {
    expect(await gapsOf(root)).toEqual([]);
  });
  it("case gaps derive from the scripts and the row globs through ci-paths gapsFrom", async () => {
    const cp = await ciPaths();
    for (const c of cases) expect(cp.gapsFrom(c.scripts, c.globs).filter((g) => g.path !== null)).toEqual(c.gaps);
  });
  it.each(globs.map((r) => [`${r.globs.join(" ")} ~ ${r.path}`, r]))("glob %s", async (_n, r) => {
    const ci = (await import(pathToFileURL(join(root, ".github/scripts/changed-inputs.mjs")).href)) as { matches: (g: string[], f: string) => boolean };
    expect(ci.matches(r.globs, r.path)).toBe(r.match);
  });
  it.each(gapRows.map((r, i) => [i, r]))("gap vector %i: reads, input gaps and closure gaps", async (_i, r) => {
    const cp = await ciPaths();
    const reads = r.scripts.flatMap((s: { script: string; text: string }) =>
      cp.leanScriptPaths(s.text).map((p) => ({ script: s.script, path: p === null ? null : cp.readPath(p) })));
    expect(reads).toEqual(r.reads);
    expect(cp.gapsFrom(r.scripts, r.globs)).toEqual(r.inputGaps);
    expect(cp.gapsFrom(r.scripts, r.globs).filter((g) => g.path !== null)).toEqual(r.gaps);
  });
  it.each(agreeRows.map((r) => [r.globs.join(" "), r]))("JS matches agrees with Lean ghMatches on rowGlob globs: %s", async (_n, r) => {
    const cp = await ciPaths();
    const ci = (await import(pathToFileURL(join(root, ".github/scripts/changed-inputs.mjs")).href)) as { matches: (g: string[], f: string) => boolean };
    expect(r.globs.every(cp.rowGlob)).toBe(true);
    expect(agreePaths.filter((p) => ci.matches(r.globs, p))).toEqual(r.hits);
  });
  it("a read with a .. segment is a non-literal gap even under a ** row glob", async () => {
    const cp = await ciPaths();
    expect(cp.gapsFrom([{ script: "s", text: "../lean/../x ../../e ../a/b..c\n" }], ["**"])).toEqual([{ script: "s", path: null }, { script: "s", path: null }]);
  });
  it.each(syncRows.map((r, i) => [i, r]))("sync vector %i", (_i, r) => {
    expect(newErrors(r.before, r.after)).toEqual(r.refused);
  });
  it("a gap is a literal ../ read of a lean/scripts/*.sh that the lean.yml row lacks", async () => {
    const dir = mkdtempSync(join(tmpdir(), "gaps-"));
    mkdirSync(join(dir, "lean/scripts"), { recursive: true });
    mkdirSync(join(dir, "packages/contracts/golden/ci"), { recursive: true });
    writeFileSync(join(dir, "packages/contracts/golden/ci/triggers.jsonl"),
      JSON.stringify({ kind: "table", sets: {}, workflows: [{ file: "lean.yml", inputs: ["lean/**", "packages/a.jsonl"] }] }) + "\n");
    writeFileSync(join(dir, "lean/scripts/check.sh"), "job a x --check ../packages/a.jsonl ../packages/b.jsonl ../lean/Fw/X.lean ../$V\n");
    writeFileSync(join(dir, "lean/scripts/other.sh"), "node ../packages/c.json\n");
    writeFileSync(join(dir, "lean/scripts/notes.md"), "../packages/d.json\n");
    expect(await gapsOf(dir, root)).toEqual([{ script: "lean/scripts/check.sh", path: "packages/b.jsonl" }, { script: "lean/scripts/other.sh", path: "packages/c.json" }]);
  });
});

const bins = coreCandidates(root, root);
describe.skipIf(bins.length === 0)("fwcore console.landScope agrees with the golden violations", () => {
  it("every case", async () => {
    const live = cases.filter((c) => !c.done && c.required.length + c.mayNeed.length > 0);
    const rs = await scopeBatch(bins)(live.map((c) => ({ op: "console.landScope", writes: c.writes, names: [c.id, c.owner], allow: [], paths: [...c.required, ...c.mayNeed], task: c.id, stream: c.stream })));
    expect(rs.map((r) => r.violations)).toEqual(live.map((c) => c.violations));
  });
});

describe("plan.md time table (scripts/plan-time.mjs, Lean timeTable)", () => {
  const planTime = async () => (await import(pathToFileURL(join(root, "scripts/plan-time.mjs")).href)) as {
    timeTable: (b: number[], a: number[]) => string; render: (root: string) => string; DOC: string };
  it.each(timeRows.map((r, i) => [i, r]))("time vector %i", async (_i, r) => {
    expect((await planTime()).timeTable(r.before, r.after)).toBe(r.text);
  });
  it("the committed table is generated from the committed samples", async () => {
    const pt = await planTime();
    expect(readFileSync(join(root, pt.DOC), "utf8")).toBe(pt.render(root));
  });
});

describe("plan lint with the writes closure", () => {
  const graph = (writes: string[], extra: object = {}) => {
    const f = join(mkdtempSync(join(tmpdir(), "closure-")), "g.json");
    writeFileSync(f, JSON.stringify({ milestones: [], tasks: [{ id: "a", title: "a", stream: "measure", milestone: "M", deps: [], owner: "o", writes, ...extra }] }));
    return f;
  };
  const good = async () => ({ ok: true, errors: 0, warnings: 0, infos: 0, findings: [] });
  const wf = [".github/workflows/new.yml", "docs/team/handoffs/a.md"];
  it("exits 1 and names each missing path", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const batch = async (reqs: ScopeReq[]) => reqs.map((r) => ({ violations: r.paths.filter((p) => p.endsWith(".lean")) }));
    expect(await lintCli([graph(wf)], here, good, [], () => true, { tracked: [], gaps: [], batch })).toBe(1);
    const text = String(log.mock.calls.at(-1)![0]);
    log.mockRestore();
    expect(text).toContain("error a writesClosure: lean/Fw/Ci/Trigger.lean for .github/workflows/new.yml");
    expect(text).toContain("error a writesClosure: lean/Fw/Ci/Overflow.lean for .github/workflows/new.yml");
    expect(text).toContain("plan lint: 3 errors, 0 warnings");
  });
  it("passes a done row and a closed one", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const batch = async (reqs: ScopeReq[]) => reqs.map(() => ({ violations: [] }));
    expect(await lintCli([graph(wf, { evidence: "abc1234" })], here, good, [], () => true, { tracked: [], gaps: [], batch: async () => { throw new Error("no call"); } })).toBe(0);
    expect(await lintCli([graph(wf)], here, good, [], () => true, { tracked: [], gaps: [], batch })).toBe(0);
    log.mockRestore();
  });
});

describe("plan sync refuses a new writesClosure error", () => {
  const env = { ...process.env, GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@t", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@t", GIT_CONFIG_GLOBAL: "/dev/null" };
  const row = (id: string, writes: string[]) => ({ id, title: id, stream: "tooling", milestone: "M", deps: [], owner: "o", writes });
  const text = (...tasks: object[]) => JSON.stringify({ milestones: [], tasks }, null, 1) + "\n";
  const repo = (...versions: string[]) => {
    const dir = mkdtempSync(join(tmpdir(), "sync-closure-"));
    const g = (...a: string[]) => execFileSync("git", a, { cwd: dir, env, stdio: "ignore" });
    g("init", "-q", "-b", "main");
    for (const v of versions) { writeFileSync(join(dir, "g.json"), v); g("add", "g.json"); g("commit", "-q", "-m", "v"); }
    return dir;
  };
  const closure = { tracked: ["lean/Fw/Ci/Trigger.lean"], gaps: [], batch: async (reqs: ScopeReq[]) => reqs.map((r) => ({ violations: r.paths.filter((p) => !r.writes.includes(p)) })) };
  const ok = row("a", ["docs/x.md"]), wf = row("b", [".github/workflows/new.yml"]);
  const wfFixed = row("b", [".github/workflows/new.yml", "lean/Fw/Ci/Trigger.lean"]);
  it("a committed edit is compared with the version before it", async () => {
    const dir = repo(text(ok), text(ok, wf));
    expect(previousGraph(dir, "g.json", text(ok, wf)).tasks.map((t) => t.id)).toEqual(["a"]);
    const r = await syncClosureRefusal(dir, "g.json", closure);
    expect(r).toContain("plan sync refused: the graph adds 5 writesClosure error(s)");
    expect(r).toContain("b: lean/Fw/Ci/Trigger.lean for .github/workflows/new.yml");
  });
  it("an uncommitted edit is compared with HEAD: an error HEAD has passes, a fixed row adds nothing", async () => {
    const dir = repo(text(ok, wf));
    writeFileSync(join(dir, "g.json"), text(ok, wf, row("c", ["docs/y.md"])));
    expect(await syncClosureRefusal(dir, "g.json", closure)).toBeNull();
    writeFileSync(join(dir, "g.json"), text(ok, wfFixed));
    expect(await syncClosureRefusal(dir, "g.json", closure)).toBeNull();
  });
  it("an uncommitted new row with a closure error is refused; a first version has an empty previous graph", async () => {
    const dir = repo(text(ok));
    writeFileSync(join(dir, "g.json"), text(ok, wf));
    expect(await syncClosureRefusal(dir, "g.json", closure)).toContain("b: lean/Fw/Ci/Intent.lean");
    expect(previousGraph(dir, "g.json", text(ok))).toEqual({ milestones: [], tasks: [] });
  });
});
