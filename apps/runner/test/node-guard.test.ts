import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { nodePinRefusal, readNodePin } from "../src/node-guard.ts";

const goldenFile = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "packages", "contracts", "golden", "ci", "triggers.jsonl");

describe("node pin runtime guard", () => {
  it("decides exactly as Lean (Fw.Ci.Trigger nodePinRefusal, golden pinGuard lines)", () => {
    const lines = readFileSync(goldenFile, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)).filter((l) => l.kind === "pinGuard");
    expect(lines.length).toBeGreaterThanOrEqual(8);
    for (const l of lines) expect(nodePinRefusal(l.running, l.pinned), JSON.stringify(l)).toBe(l.refusal);
  });
  it("accepts the pinned version, with or without the v prefix", () => {
    expect(nodePinRefusal("v24.22.0", "24.22.0")).toBeNull();
    expect(nodePinRefusal("24.22.0", "24.22.0\n")).toBeNull();
  });
  it("refuses another version with one line naming both versions and the fix", () => {
    const m = nodePinRefusal("v24.14.0", "24.22.0");
    expect(m).toContain("24.14.0");
    expect(m).toContain("24.22.0");
    expect(m).toContain("nvm use");
    expect(m).not.toContain("\n");
  });
  it("refuses a newer version too (exact pin)", () => {
    expect(nodePinRefusal("v24.23.0", "24.22.0")).not.toBeNull();
  });
  it("enforces nothing when there is no pin", () => {
    expect(nodePinRefusal("v1.0.0", null)).toBeNull();
  });
  it("reads the repo-root .node-version", () => {
    const src = join(dirname(fileURLToPath(import.meta.url)), "..", "src");
    expect(readNodePin(src)).toBe(readFileSync(join(src, "..", "..", "..", ".node-version"), "utf8").trim());
  });
});
