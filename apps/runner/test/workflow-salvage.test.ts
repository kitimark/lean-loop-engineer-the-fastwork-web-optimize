import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { decide, salvageStage, type Effects } from "../src/workflow/salvage.ts";

const file = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "packages", "contracts", "golden", "ops", "salvage.jsonl");
const golden = readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("workflow salvage", () => {
  it("the TS stand-in equals every Lean golden line", () => {
    expect(golden.length).toBeGreaterThan(0);
    for (const g of golden) {
      const { task, hasResult, dirty, ahead } = g.request;
      expect(decide({ task, hasResult, dirty, ahead }), g.name).toEqual(g.response);
    }
  });

  const rec = (dirty: boolean, ahead: number) => {
    const calls: string[] = [];
    const fx: Effects = {
      facts: () => ({ dirty, ahead }),
      commitWip: (m, e) => (calls.push(`commit:${e}:${m}`), "abc1234"),
      handback: (t, tip, s) => calls.push(`handback:${t}:${tip}:${s}`),
    };
    return { calls, fx };
  };

  it("a result leaves the worktree alone", () => {
    const { calls, fx } = rec(true, 1);
    expect(salvageStage("t-1", { ok: true }, fx)).toEqual({ salvaged: false });
    expect(calls).toEqual([]);
  });

  it("a null result commits WIP then hands back", () => {
    const { calls, fx } = rec(true, 0);
    expect(salvageStage("gate-shard-balance", null, fx)).toEqual({ salvaged: true, tip: "abc1234", state: "dirty" });
    expect(calls).toEqual([
      "commit:false:WIP salvage gate-shard-balance: builder exited without a result",
      "handback:gate-shard-balance:abc1234:dirty",
    ]);
  });

  it("a clean tree gets an empty commit; undefined counts as no result", () => {
    const { calls, fx } = rec(false, 0);
    expect(salvageStage("t-1", undefined, fx).salvaged).toBe(true);
    expect(calls[0]).toMatch(/^commit:true:/);
  });
});
