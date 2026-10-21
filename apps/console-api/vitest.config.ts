// The tests start fwcore and version-control child processes; vitest's 5 s default failed them under machine load (check-dag runs
// checks in parallel). No test asserts wall-clock time: the bound only catches a hung child.
import { readFileSync } from "node:fs";
import { defineConfig } from "vitest/config";
const budget = JSON.parse(readFileSync(new URL("../../packages/contracts/golden/sched/node-budget.gen.json", import.meta.url), "utf8")) as { workers: number };
export default defineConfig({ test: { testTimeout: 120_000, hookTimeout: 120_000, maxWorkers: budget.workers } });
