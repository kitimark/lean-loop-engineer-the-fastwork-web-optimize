import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { parseSamples } from "../src/watch-collect.ts";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");
type Case = { name: string; request: { samples: { durMs: number; load: number; exit?: number; work?: Record<string, string> }[] }; response: { verdicts: { code: string }[] } };
const golden = readFileSync(join(root, "packages/contracts/golden/obs/timing.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Case);
const outer = golden.filter((g) => g.name.startsWith("slot width outer:"));
const rows = readFileSync(join(here, "fixtures/slot-check-outer.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Record<string, unknown>);
const inferred = (d: number): number => (d < 130000 ? 2 : 1);
const text = (withWidth: boolean): string => rows.map((r) => JSON.stringify(withWidth ? { ...r, slot: { width: inferred(r.durMs as number) } } : r)).join("\n");
const lastTwo = (g: Case): string[] => g.response.verdicts.slice(-2).map((v) => v.code);

describe("outer fw slot run check span, by admitted width (Fw.Obs.Timing.judgeQ_other_width)", () => {
  it("has the three golden cases and the nine fixture rows, the two alert rows last", () => {
    expect(outer).toHaveLength(3);
    expect(rows.map((r) => r.commit).slice(-2)).toEqual(["1414619", "401d607"]);
    expect(rows.map((r) => r.durMs).slice(-2)).toEqual([180178, 177727]);
  });
  for (const withWidth of [false, true]) {
    it(`the fixture ${withWidth ? "with" : "without"} the width reads as the Lean golden samples`, () => {
      const g = outer[withWidth ? 1 : 0]!;
      const s = parseSamples(text(withWidth));
      expect(s.map((x) => [x.durMs, x.load, x.exit, x.work ?? {}])).toEqual(g.request.samples.map((x) => [x.durMs, x.load, x.exit, x.work ?? {}]));
    });
  }
  it("the 00:16Z and 01:25Z width-1 runs read slow without the width and noBaseline with it", () => {
    expect([lastTwo(outer[0]!), lastTwo(outer[1]!)]).toEqual([["slow", "slow"], ["noBaseline", "noBaseline"]]);
  });
  it("a same-width regression still reads slow", () => {
    expect(lastTwo(outer[2]!)[1]).toBe("slow");
    expect(outer[2]!.request.samples.at(-1)!.work).toEqual({ width: "1" });
  });
  it("a span without a slot member keeps the work-free key", () => {
    expect(parseSamples(text(false)).every((x) => x.work === undefined)).toBe(true);
  });
});
