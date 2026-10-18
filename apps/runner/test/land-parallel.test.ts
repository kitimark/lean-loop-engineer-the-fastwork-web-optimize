// Parallel check scheduling (Lean Fw.Console.LandSpeed.verdict_perm): same verdict as sequential, every failure listed.
import "./land-timeout.ts";
import { describe, expect, it } from "vitest";
import { checkDeps } from "../src/land.ts";

describe("checkDeps", () => {
  it("everything waits for install; fwcore users wait for check.sh; others are independent", () => {
    const list = [
      ["pnpm", "install", "--frozen-lockfile"],
      ["sh", "lean/scripts/check.sh"],
      ["pnpm", "--filter", "./apps/runner", "test"],
      ["pnpm", "--filter", "./packages/contracts", "test"],
    ];
    expect(checkDeps(list)).toEqual([[], [0], [0, 1], [0]]);
  });
  it("no install, no check.sh: no dependencies", () => {
    expect(checkDeps([["a"], ["b"]])).toEqual([[], []]);
  });
});
