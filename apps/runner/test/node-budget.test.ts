import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { NODE_BUDGET_GEN, candidateChecks, testWorkersEnv } from "../src/land.ts";

const root = join(import.meta.dirname, "../../..");
type Room = { cores: number; reserveCores: number; freeMiB: number; workerMiB: number; pool: number };
const gen = JSON.parse(readFileSync(join(root, NODE_BUDGET_GEN), "utf8")) as { room: Room; workers: number };
const rows = readFileSync(join(root, "packages/contracts/golden/sched/node-budget.jsonl"), "utf8").split("\n").filter(Boolean)
  .map((l) => JSON.parse(l) as { room: Room; workers: number });
const today = rows.filter((r) => r.room.cores === gen.room.cores && r.room.reserveCores === gen.room.reserveCores && r.room.freeMiB === gen.room.freeMiB && r.room.workerMiB === gen.room.workerMiB);

describe("testWorkersEnv replays Lean Fw.Sched.NodeBudget.workers of today's room", () => {
  it("the golden has today's room at several pools", () => expect(today.length).toBeGreaterThan(4));
  for (const r of today)
    it(`pool ${r.room.pool}: ${r.workers} workers`, () => expect(testWorkersEnv(root, r.room.pool)).toEqual({ VITEST_MAX_WORKERS: String(r.workers) }));
  it("the generated workers are those of today's pool", () => expect(today.find((r) => r.room.pool === gen.room.pool)?.workers).toBe(gen.workers));
  it("a tree without the generated file sets no env", () => expect(testWorkersEnv(join(root, "no-such-dir"), 4)).toEqual({}));
});

const FLAG = /node --test --test-concurrency=\$\{VITEST_MAX_WORKERS:-\$\(node -p "require\('([^']+)'\)\.workers"\)\} /;
const packageTests = candidateChecks(root).filter((c) => c.argv[1] === "--filter").map((c) => {
  const dir = c.argv[2]!.slice(2);
  return { dir, test: (JSON.parse(readFileSync(join(root, dir, "package.json"), "utf8")) as { scripts: { test: string } }).scripts.test };
});

describe("every node --test script fw land runs passes the Lean budget as --test-concurrency", () => {
  const nodeTests = packageTests.filter((p) => p.test.includes("node --test"));
  it("fw land runs node --test packages", () => expect(nodeTests.length).toBeGreaterThan(0));
  for (const p of nodeTests)
    it(p.dir, () => {
      expect(p.test.split("node --test").length - 1).toBe(p.test.match(new RegExp(FLAG.source, "g"))?.length);
      const rel = FLAG.exec(p.test)![1]!;
      expect(resolve(join(root, p.dir), rel)).toBe(resolve(root, NODE_BUDGET_GEN));
    });
});

describe("every vitest check fw land runs gets the Lean budget as VITEST_MAX_WORKERS", () => {
  for (const p of packageTests.filter((q) => q.test.includes("vitest")))
    it(p.dir, () => expect(testWorkersEnv(root, 4).VITEST_MAX_WORKERS).toBe(String(gen.workers)));
});
