// The tests start fwcore and version-control child processes; vitest's 5 s default failed them under machine load (check-dag runs
// checks in parallel). No test asserts wall-clock time: the bound only catches a hung child.
import { defineConfig } from "vitest/config";
export default defineConfig({ test: { testTimeout: 120_000, hookTimeout: 120_000 } });
