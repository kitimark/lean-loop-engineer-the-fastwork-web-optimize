import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { newNonce, parseRunRows, pickRun, titleOf, validNonce, type Pick, type RunRow } from "../src/run-pick.ts";

// The pick of a dispatch's run is Lean's (lean/Fw/Ci/Dispatch.lean); every golden case is replayed against the TS stand-in.
const root = join(process.cwd(), "..", "..");
const cases = readFileSync(join(root, "packages", "contracts", "golden", "ci", "dispatch.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; nonce: string; rows: RunRow[]; title: string; valid: boolean; result: Pick });

describe("pickRun equals Lean Fw.Ci.Dispatch.pick", () => {
  it("has cases of every outcome", () => {
    expect(new Set(cases.map((c) => c.result.kind))).toEqual(new Set(["found", "absent", "ambiguous", "badNonce"]));
  });
  for (const c of cases) {
    it(c.name, () => {
      expect(titleOf(c.nonce)).toBe(c.title);
      expect(validNonce(c.nonce)).toBe(c.valid);
      expect(pickRun(c.nonce, c.rows)).toEqual(c.result);
    });
  }
});

describe("run list handling", () => {
  it("two parallel dispatches each pick their own run, never the newest", () => {
    const a = newNonce();
    const b = newNonce();
    expect(a).not.toBe(b);
    const rows = parseRunRows(JSON.stringify([
      { databaseId: 39508421419, displayTitle: titleOf(b), event: "workflow_dispatch" },
      { databaseId: 39508414669, displayTitle: titleOf(a), event: "workflow_dispatch" },
      { databaseId: 39505172794, displayTitle: "ci: x [ci:trajectory-probe]", event: "push" },
    ]));
    expect(pickRun(a, rows)).toEqual({ kind: "found", id: 39508414669 });
    expect(pickRun(b, rows)).toEqual({ kind: "found", id: 39508421419 });
  });
  it("a fresh nonce is valid", () => { expect(validNonce(newNonce())).toBe(true); });
});
