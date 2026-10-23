import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it, vi } from "vitest";
import { closureFindings, freshOf, implied, kindOf, lintClosure, mayNeed, required, scopeBatch, type ScopeReq } from "../src/plan-closure.ts";
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
    expect(required(c.tracked, c.writes)).toEqual(c.required);
    expect(mayNeed(c.tracked, c.writes)).toEqual(c.mayNeed);
    expect(closureFindings(c.tracked, task(c), c.violations)).toEqual(c.findings);
  });
  it("lintClosure asks once per open row with a closure and splits the reply", async () => {
    const seen: ScopeReq[] = [];
    const c = cases.find((x) => x.name === "r322 workflow named, tables not")!;
    const out = await lintClosure([task(c), { id: "n", owner: "o", stream: "s", writes: ["docs/x.md"], done: false }], c.tracked,
      async (reqs) => (seen.push(...reqs), reqs.map(() => ({ violations: c.violations }))));
    expect(seen).toHaveLength(1);
    expect(seen[0]).toMatchObject({ op: "console.landScope", names: [c.id, c.owner], allow: [], task: c.id, stream: c.stream, paths: [...c.required, ...c.mayNeed] });
    expect(out).toEqual(c.findings);
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
    expect(await lintCli([graph(wf)], here, good, [], () => true, { tracked: [], batch })).toBe(1);
    const text = String(log.mock.calls.at(-1)![0]);
    log.mockRestore();
    expect(text).toContain("error a writesClosure: lean/Fw/Ci/Trigger.lean for .github/workflows/new.yml");
    expect(text).toContain("error a writesClosure: lean/Fw/Ci/Pool/Caps.lean for .github/workflows/new.yml");
    expect(text).toContain("plan lint: 4 errors, 0 warnings");
  });
  it("passes a done row and a closed one", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const batch = async (reqs: ScopeReq[]) => reqs.map(() => ({ violations: [] }));
    expect(await lintCli([graph(wf, { evidence: "abc1234" })], here, good, [], () => true, { tracked: [], batch: async () => { throw new Error("no call"); } })).toBe(0);
    expect(await lintCli([graph(wf)], here, good, [], () => true, { tracked: [], batch })).toBe(0);
    log.mockRestore();
  });
});
