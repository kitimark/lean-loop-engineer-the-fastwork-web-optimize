import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { DRY_ORDER, DRY_WAVES, dryRecordLake, dryVerdict, type DryPhase } from "../src/land-dry.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
type Row = { reads: boolean; lints: boolean; ledger: boolean; local: boolean; ranOld: DryPhase[]; verdict: DryPhase | null; waves: DryPhase[][] };
const rows = readFileSync(join(root, "packages/contracts/golden/ops/land-dry.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Row);

describe("the dry land's phase rules equal the Lean decision (Fw.Ops.LandDry)", () => {
  it("has the rows", () => expect(rows.length).toBeGreaterThanOrEqual(8));
  for (const [i, r] of rows.entries()) {
    it(`golden row ${i}`, () => {
      expect(dryVerdict(r)).toBe(r.verdict);
      expect(DRY_WAVES).toEqual(r.waves);
    });
  }
  it("no check dropped: every phase the old protocol ran is in a wave or is the ledger read", () => {
    for (const r of rows) for (const p of r.ranOld) if (p !== "ledger") expect(DRY_WAVES.flat()).toContain(p);
  });
  it("the verdict is the old short-circuit order", () => {
    for (const r of rows) expect(dryVerdict(r)).toBe(DRY_ORDER.find((p) => !r[p]) ?? null);
  });
  it("the lake pass record needs reads and lints", () => {
    expect(dryRecordLake({ reads: false, lints: true, ledger: true, local: true }, true)).toBe(false);
    expect(dryRecordLake({ reads: true, lints: false, ledger: true, local: true }, true)).toBe(false);
    expect(dryRecordLake({ reads: true, lints: true, ledger: true, local: true }, false)).toBe(false);
    expect(dryRecordLake({ reads: true, lints: true, ledger: true, local: true }, true)).toBe(true);
  });
});
