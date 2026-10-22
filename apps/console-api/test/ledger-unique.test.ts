import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { badNs, badNsOfFile, candidateNs } from "../src/ledger-unique.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");
type G = { name: string; ns: number[]; bad: number[]; ok: boolean };
const golden: G[] = readFileSync(join(ROOT, "packages/contracts/golden/console/ledger-unique.jsonl"), "utf8")
  .split("\n").filter((l) => l !== "").map((l) => JSON.parse(l) as G);

describe("ledger candidate numbers are unique (Lean Fw.Console.LedgerUnique golden)", () => {
  it("has the cases", () => expect(golden.length).toBeGreaterThanOrEqual(8));
  for (const g of golden) {
    it(`golden ${g.name}`, () => {
      expect(badNs(g.ns)).toEqual(g.bad);
      expect(badNs(g.ns).length === 0).toBe(g.ok);
    });
  }
  it("candidate rows are those with an id and a candidate text", () => {
    expect(candidateNs({ findings: [{ n: 1, candidate: "a" }, { id: "x", n: 2, candidate: "b" }, { id: "y", n: 3 }] })).toEqual([2]);
  });
  it("research/findings/ledger.json has no duplicate candidate n", () => {
    expect(badNsOfFile(join(ROOT, "research/findings/ledger.json"))).toEqual([]);
  });
});
