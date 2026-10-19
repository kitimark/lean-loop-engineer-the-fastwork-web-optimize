// Land gate for task land-wallclock-off-gate: no unlisted literal wall-clock bound in the land-selected tests
// (scripts/lint-wallclock.mjs; decision Lean Fw.Console.WallClock).
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { expect, it } from "vitest";

const root = join(dirname(new URL(import.meta.url).pathname), "../../..");
it("the land-selected tests carry no unlisted absolute ms bound", () => {
  const r = spawnSync(process.execPath, [join(root, "scripts/lint-wallclock.mjs")], { encoding: "utf8" });
  expect(r.stderr).toBe("");
  expect(r.status).toBe(0);
});
