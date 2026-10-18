// land-verdict.ts (TS stand-in) against the Lean golden packages/contracts/golden/console/land-dry.jsonl
// (Fw.Console.LandVerdict, Fw.Console.LandDry). Marked for replacement by an fwcore op.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";
import { dryKind, exitCode, handbackAllowed, parseVerdict, retryable, isOk, verdictLine, type Kind } from "../src/land-verdict.ts";

const file = join(dirname(new URL(import.meta.url).pathname), "../../../packages/contracts/golden/console/land-dry.jsonl");
type G = { name: string; request: Record<string, unknown> & { op: string }; response: Record<string, unknown> };
const rows: G[] = readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("land verdict vs Lean golden", () => {
  it("has rows", () => expect(rows.length).toBeGreaterThanOrEqual(40));
  for (const g of rows) it(g.name, () => {
    const q = g.request;
    if (q.op === "landVerdict.kind") {
      const k = q.kind as Kind;
      expect(g.response).toEqual({ exit: exitCode(k), line: verdictLine(k, q.task as string), ok: isOk(k), retry: retryable(k) });
    } else if (q.op === "landDry.verdict") {
      expect(g.response).toEqual({ kind: dryKind({ containsMain: q.containsMain as boolean, scope: q.scope as boolean, merges: q.merges as boolean, readsSelected: q.readsSelected as boolean, readsTest: q.readsTest as boolean, own: q.own as boolean, lints: q.lints as boolean }) });
    } else if (q.op === "landDry.handback") {
      expect(g.response).toEqual({ allowed: handbackAllowed(q.kind as Kind) });
    } else throw new Error(`unknown op ${q.op}`);
  });
  it("parseVerdict reads the last VERDICT line only", () => {
    expect(parseVerdict("x\nVERDICT busy t1\nnoise VERDICT done t1\nVERDICT dry t1\n")).toEqual({ kind: "dry", task: "t1" });
    expect(parseVerdict("VERDICT nope t1")).toBeNull();
    expect(parseVerdict("VERDICT done -")).toEqual({ kind: "done", task: "" });
  });
});
