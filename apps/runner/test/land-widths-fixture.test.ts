import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { checksWithReads, OVERFLOW_WIDTHS_READS, overflowWidthsReadsFromGolden } from "../src/land.ts";
import { checkRow, parseWorkflow, width, widthTable } from "./workflow-widths.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const ID = "runner:overflow-widths";

const job = (n: number) => `  j${n}:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ${n}\n`;
const made: string[] = [];
afterAll(() => { for (const d of made) rmSync(d, { recursive: true, force: true }); });
function fixture(jobs: number): string {
  const dir = mkdtempSync(join(tmpdir(), "owr-"));
  made.push(dir);
  mkdirSync(join(dir, ".github/workflows"), { recursive: true });
  writeFileSync(join(dir, ".github/workflows/path-pix.yml"), `name: path-pix\non: push\njobs:\n${Array.from({ length: jobs }, (_, i) => job(i + 1)).join("")}`);
  return dir;
}
const LEAN_ROW4 = `def widths : List (String × Nat) :=\n  [("path-pix", 4)]\n`;

describe("the width check on the path-pix 4 -> 6 case", () => {
  it("a 6-job parallel path-pix workflow derives width 6", () => {
    expect(width(parseWorkflow(fixture(6), "path-pix.yml"), () => 1)).toBe(6);
  });
  it("against a row of 4 the table check fails with the derived width in its message", () => {
    const w = parseWorkflow(fixture(6), "path-pix.yml");
    expect(() => checkRow(widthTable(LEAN_ROW4), w, width(w, () => 1))).toThrow(/derived 6/);
  });
  it("a 4-job workflow passes against the same row", () => {
    const w = parseWorkflow(fixture(4), "path-pix.yml");
    expect(() => checkRow(widthTable(LEAN_ROW4), w, width(w, () => 1))).not.toThrow();
  });
});

describe("every input the width planner reads selects the width test", () => {
  const PLANNER_INPUTS = ["packages/contracts/golden/gate/schedule.jsonl", "packages/contracts/golden/gate/shards.jsonl", "apps/site/src/breakpoints.gen.json",
    "packages/gate-breakpoints/src/anchors.json"];
  const PLANNER_CODE = ["packages/gate-breakpoints/src/spec.mjs", "packages/gate-breakpoints/src/serve.mjs"];
  it("gate-jobs.mjs names each of these data files", () => {
    const src = readFileSync(join(root, ".github/scripts/gate-jobs.mjs"), "utf8");
    for (const p of PLANNER_INPUTS) expect(src, p).toContain(p.replace("packages/contracts/golden/gate/", "").replace("apps/site/src/", "").replace("packages/gate-breakpoints/src/", ""));
  });
  for (const p of [...PLANNER_INPUTS, ...PLANNER_CODE]) it(`${p} selects ${ID}`, () => expect(checksWithReads(root, [p]).map((c) => c.id)).toContain(ID));
  it("gate-jobs.mjs imports spec.mjs, which imports serve.mjs", () => {
    expect(readFileSync(join(root, ".github/scripts/gate-jobs.mjs"), "utf8")).toContain("packages/gate-breakpoints/src/spec.mjs");
    expect(readFileSync(join(root, "packages/gate-breakpoints/src/spec.mjs"), "utf8")).toContain("./serve.mjs");
  });
  it("the TS read set is the Lean golden's, and holds the workflow files and the planner inputs", () => {
    expect(OVERFLOW_WIDTHS_READS).toEqual(overflowWidthsReadsFromGolden());
    for (const p of [".github/workflows/**", ".github/scripts/**", ...PLANNER_INPUTS, ...PLANNER_CODE]) expect(OVERFLOW_WIDTHS_READS).toContain(p);
  });
});
