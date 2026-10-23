import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it, vi } from "vitest";
import { closureFindings, freshOf, gapsOf, implied, kindOf, lintClosure, mayNeed, owned, required, scopeBatch, type ScopeReq } from "../src/plan-closure.ts";
import { lintCli } from "../src/plan.ts";
import { coreCandidates } from "../src/watch.ts";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../../..");
const rows = readFileSync(join(root, "packages/contracts/golden/plan/writes-closure.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const paths = rows.filter((r) => r.type === "path");
const cases = rows.filter((r) => r.type === "case");
const task = (c: { id: string; owner: string; stream: string; writes: string[]; done: boolean }) => ({ id: c.id, owner: c.owner, stream: c.stream, writes: c.writes, done: c.done });

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
