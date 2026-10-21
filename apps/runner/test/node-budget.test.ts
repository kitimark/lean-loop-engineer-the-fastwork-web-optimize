import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { NODE_BUDGET_GEN, testWorkersEnv } from "../src/land.ts";

const root = join(import.meta.dirname, "../../..");
type Room = { cores: number; freeMiB: number; workerMiB: number; pool: number };
const gen = JSON.parse(readFileSync(join(root, NODE_BUDGET_GEN), "utf8")) as { room: Room; workers: number };
const rows = readFileSync(join(root, "packages/contracts/golden/sched/node-budget.jsonl"), "utf8").split("\n").filter(Boolean)
  .map((l) => JSON.parse(l) as { room: Room; workers: number });
const today = rows.filter((r) => r.room.cores === gen.room.cores && r.room.freeMiB === gen.room.freeMiB && r.room.workerMiB === gen.room.workerMiB);

describe("testWorkersEnv replays Lean Fw.Sched.NodeBudget.workers of today's room", () => {
  it("the golden has today's room at several pools", () => expect(today.length).toBeGreaterThan(4));
  for (const r of today)
    it(`pool ${r.room.pool}: ${r.workers} workers`, () => expect(testWorkersEnv(root, r.room.pool)).toEqual({ VITEST_MAX_WORKERS: String(r.workers) }));
  it("the generated workers are those of today's pool", () => expect(today.find((r) => r.room.pool === gen.room.pool)?.workers).toBe(gen.workers));
  it("a tree without the generated file sets no env", () => expect(testWorkersEnv(join(root, "no-such-dir"), 4)).toEqual({}));
});
