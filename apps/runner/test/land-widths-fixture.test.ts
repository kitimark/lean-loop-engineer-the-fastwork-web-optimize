import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { checksWithReads, OVERFLOW_WIDTHS_READS, overflowWidthsReadsFromGolden } from "../src/land.ts";
import { parseWorkflow, width } from "./workflow-widths.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const ID = "runner:overflow-widths";

const job = (n: number) => `  j${n}:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ${n}\n`;
function fixture(jobs: number): string {
  const dir = mkdtempSync(join(tmpdir(), "owr-"));
  mkdirSync(join(dir, ".github/workflows"), { recursive: true });
  writeFileSync(join(dir, ".github/workflows/path-pix.yml"), `name: path-pix\non: push\njobs:\n${Array.from({ length: jobs }, (_, i) => job(i + 1)).join("")}`);
  return dir;
}
const rowOf = (lean: string, name: string) => new Map([...(/def widths[\s\S]*?\]\n/.exec(lean)![0]).matchAll(/\("([a-z0-9-]+)", (\d+)\)/g)].map((m) => [m[1]!, Number(m[2])])).get(name)!;
const LEAN_ROW4 = `def widths : List (String × Nat) :=\n  [("path-pix", 4)]\n`;

describe("the width check on the path-pix 4 -> 6 case", () => {
  it("a 6-job parallel path-pix workflow derives width 6", () => {
    expect(width(parseWorkflow(fixture(6), "path-pix.yml"), () => 1)).toBe(6);
  });
  it("against a row of 4 the table check fails with the derived width in its message", () => {
    const derived = width(parseWorkflow(fixture(6), "path-pix.yml"), () => 1);
    const check = () => expect(rowOf(LEAN_ROW4, "path-pix"), `path-pix.yml: Lean widths row (derived ${derived})`).toBeGreaterThanOrEqual(derived);
    expect(check).toThrow(/derived 6/);
  });
  it("a 4-job workflow passes against the same row", () => {
    const derived = width(parseWorkflow(fixture(4), "path-pix.yml"), () => 1);
    expect(rowOf(LEAN_ROW4, "path-pix")).toBeGreaterThanOrEqual(derived);
  });
});

describe("every input the width planner reads selects the width test", () => {
  const PLANNER_INPUTS = ["packages/contracts/golden/gate/schedule.jsonl", "packages/contracts/golden/gate/shards.jsonl", "apps/site/src/breakpoints.gen.json",
    "packages/gate-breakpoints/src/anchors.json"];
  it("the planner reads exactly these files (gate-jobs.mjs)", () => {
    const src = readFileSync(join(root, ".github/scripts/gate-jobs.mjs"), "utf8");
    for (const p of PLANNER_INPUTS) expect(src, p).toContain(p.replace("packages/contracts/golden/gate/", "").replace("apps/site/src/", "").replace("packages/gate-breakpoints/src/", ""));
  });
  for (const p of PLANNER_INPUTS) it(`${p} selects ${ID}`, () => expect(checksWithReads(root, [p]).map((c) => c.id)).toContain(ID));
  it("the TS read set is the Lean golden's, and holds the workflow files and the planner inputs", () => {
    expect(OVERFLOW_WIDTHS_READS).toEqual(overflowWidthsReadsFromGolden());
    for (const p of [".github/workflows/**", ".github/scripts/**", ...PLANNER_INPUTS]) expect(OVERFLOW_WIDTHS_READS).toContain(p);
  });
});
