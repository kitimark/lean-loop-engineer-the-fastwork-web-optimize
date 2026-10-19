// land-verdict.ts (TS stand-in) against the Lean golden packages/contracts/golden/console/land-dry.jsonl
// (Fw.Console.LandVerdict, Fw.Console.LandDry). Marked for replacement by an fwcore op.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";
import { checkFailKind, dryKind, dryRun, exitCode, failedStages, handbackAllowed, lintPlan, outcomeKind, parseVerdict, retryable, isOk, verdictLine, type Kind, type Outcome } from "../src/land-verdict.ts";

const file = join(dirname(new URL(import.meta.url).pathname), "../../../packages/contracts/golden/console/land-dry.jsonl");
type G = { name: string; request: Record<string, unknown> & { op: string }; response: Record<string, unknown> };
const rows: G[] = readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("land verdict vs Lean golden", () => {
  it("has rows", () => expect(rows.length).toBeGreaterThanOrEqual(187));
  for (const g of rows) it(g.name, () => {
    const q = g.request;
    if (q.op === "landVerdict.kind") {
      const k = q.kind as Kind;
      expect(g.response).toEqual({ exit: exitCode(k), line: verdictLine(k, q.task as string), ok: isOk(k), retry: retryable(k) });
    } else if (q.op === "landDry.verdict") {
      expect(g.response).toEqual({ kind: dryKind({ containsMain: q.containsMain as boolean, scope: q.scope as boolean, merges: q.merges as boolean, readsSelected: q.readsSelected as boolean, readsTest: q.readsTest as boolean, own: q.own as boolean, lints: q.lints as boolean }) });
    } else if (q.op === "landDry.handback") {
      expect(g.response).toEqual({ allowed: handbackAllowed(q.kind as Kind) });
    } else if (q.op === "landDry.run") {
      // the whole dry output as a function of the seven stage outcomes: lines, kind, exit code (Lean `dryRun`)
      const oc = { threw: q.threw, fresh: q.fresh, own: q.own, scope: q.scope, merges: q.merges, reads: q.reads, lints: q.lints } as Outcome;
      const lines = dryRun(oc, q.task as string);
      expect(g.response).toEqual({ lines, kind: outcomeKind(oc), exit: exitCode(outcomeKind(oc)) });
      expect(lines.filter((l) => l.startsWith("VERDICT ")).length).toBe(1);
    } else if (q.op === "landDry.lintPlan") {
      expect(g.response).toEqual({ argv: lintPlan(q.changed as string[], q.hasCiPaths as boolean, q.hasAxioms as boolean) });
    } else if (q.op === "landDry.checkKind") {
      expect(g.response).toEqual({ kind: checkFailKind(q.failed as { reads: boolean; stages: string[] }[]) });
    } else throw new Error(`unknown op ${q.op}`);
  });
  it("failedStages reads the check.sh stage names (parsing only)", () => {
    expect(failedStages("x\ncheck: FAILED stage: axiom check\ncheck: FAILED: \n  - axiom check\n  - lake test\nrest")).toEqual(["axiom check", "lake test"]);
    expect(failedStages("  - not a stage\nnothing")).toEqual([]);
  });
  it("parseVerdict reads the last VERDICT line only", () => {
    expect(parseVerdict("x\nVERDICT busy t1\nnoise VERDICT done t1\nVERDICT dry t1\n")).toEqual({ kind: "dry", task: "t1" });
    expect(parseVerdict("VERDICT nope t1")).toBeNull();
    expect(parseVerdict("VERDICT done -")).toEqual({ kind: "done", task: "" });
  });
});
