// fw coverage: the TS mirror of Fw.Gate.Coverage replayed on the Lean golden vectors
// (packages/contracts/golden/gate/coverage.jsonl, written by Fw.Wire.Coverage.Golden.run; see docs/team/tools/coverage.md).
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  GOLDEN, allProbes, failingCells, lint, patOk, readGolden, renderUncovered, sourceOf, tally, unionProps,
  type Anchors, type Claim, type Props, type RunFacts,
} from "../src/coverage.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const golden = readGolden(join(root, GOLDEN));

describe("coverage golden (Lean Fw.Gate.Coverage)", () => {
  it("has the claims line and cases", () => {
    expect(golden.claims.length).toBeGreaterThan(0);
    expect(golden.cases.length).toBeGreaterThanOrEqual(6);
    for (const c of golden.claims) {
      expect(["generated", "golden", "exempt"]).toContain(c.src.kind);
      expect(["count", "box", "style", "*"]).toContain(c.cls);
    }
  });
  for (const k of golden.cases) {
    it(`case: ${k.name}`, () => {
      const { anchors, props, bps, evidence, claims } = k.input as { anchors: Anchors; props: Props; bps: string[]; evidence: string[]; claims: Claim[] };
      const ev = new Set(evidence);
      const ps = allProbes(anchors, props, bps);
      expect(ps).toEqual(k.output.probes);
      expect(lint(ev, claims, ps)).toEqual(k.output.lint);
      expect(ps.map((p) => sourceOf(ev, claims, p))).toEqual(k.output.sources);
      expect(tally(ev, claims, ps)).toEqual(k.output.tally);
    });
  }
});

describe("coverage glue", () => {
  it("pattern spelling", () => {
    expect(patOk("*", "x")).toBe(true);
    expect(patOk("transition-*", "transition-delay")).toBe(true);
    expect(patOk("transition-*", "transform")).toBe(false);
    expect(patOk("w", "w")).toBe(true);
    expect(patOk("w", "wh")).toBe(false);
  });
  it("unions props over engines in first-seen order", () => {
    const r = (engine: string, restated: string[]): RunFacts => ({ engine, props: { p: { r: { restated } } }, blocks: [], sweeps: [], probeBlock: new Map() });
    expect(unionProps([r("a", ["x", "y"]), r("b", ["z", "x"])])).toEqual({ p: { r: { restated: ["x", "y", "z"] } } });
  });
  it("maps failure labels to classes and marks sources", () => {
    const claims: Claim[] = [{ part: "p", role: "*", cls: "box", key: "w", bp: "*", src: { kind: "exempt", why: "engineDefault" } }];
    const summary = { engines: { chromium: { failures: [
      { part: "p", cls: "box", role: "r", key: "w", labels: ["desk-1", "desk-2", "sw#3"] },
      { part: "p", cls: "style", role: "r", key: "color", labels: ["touch-1"] },
    ] } } };
    const blocks: Record<string, string> = { "desk-1": "desk", "desk-2": "desk", "touch-1": "touch" };
    const cells = failingCells(summary, (_e, l) => blocks[l] ?? l, new Set(), claims);
    expect(cells.map((c) => [c.key, c.bp, c.src === null])).toEqual([["w", "desk", false], ["w", "sw", false], ["color", "touch", true]]);
  });
  it("collapses all-class rows", () => {
    const p = (bp: string) => ({ part: "p", role: "r", cls: "style" as const, key: "k", bp });
    expect(renderUncovered(["a", "b"], [p("a"), p("b")])).toEqual(["  p r: style:k"]);
    expect(renderUncovered(["a", "b"], [p("a")])).toEqual(["  p r: style:k[a]"]);
  });
});
