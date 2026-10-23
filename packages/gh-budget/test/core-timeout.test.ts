// fwcoreCall must pass the Lean bound fwcoreCallMs as the spawnSync timeout (lockMarginMs assumes it).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { GH_BOUNDS } from "../src/bounds.gen.ts";

test("fwcoreCall spawnSync options carry timeout: GH_BOUNDS.fwcoreCallMs unless a load-tolerant caller sets FW_CORE_CALL_MS", () => {
  const src = readFileSync(new URL("../src/core.ts", import.meta.url), "utf8");
  assert.match(src, /spawnSync\(bin, \[\], \{[^\n]*timeout: Number\(process\.env\.FW_CORE_CALL_MS\) \|\| GH_BOUNDS\.fwcoreCallMs/);
  assert.equal(GH_BOUNDS.fwcoreCallMs, 10000);
});
