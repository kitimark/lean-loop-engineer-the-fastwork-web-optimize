import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { landLint } from "../src/land-lint.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

test("a land with no changed note or handoff runs no lint", async () => {
  assert.deepEqual(await landLint(root, ["apps/runner/src/land.ts", "docs/team/handoffs/x/y.md"]), ["claims lint: no changed note or handoff"]);
});

test("a land lints its changed notes present in the tree and ends with the summary line", async () => {
  const out = await landLint(root, ["research/notes/2026/10-30-claim-lint.md", "research/notes/2026/gone.md", "apps/runner/src/land.ts"]);
  assert.match(out.at(-1)!, /^claims lint: \d+ warnings in [01] of 1 files/);
  assert.ok(out.slice(0, -1).every((l) => l.startsWith("WARN research/notes/2026/10-30-claim-lint.md:")));
});

test("a tree without the CLI gives a not-run line instead of an exception", async () => {
  const dir = mkdtempSync(join(tmpdir(), "land-lint-"));
  mkdirSync(join(dir, "docs/team/handoffs"), { recursive: true });
  writeFileSync(join(dir, "docs/team/handoffs/a.md"), "MEASURED 1 MB.\n");
  const out = await landLint(dir, ["docs/team/handoffs/a.md"]);
  assert.equal(out.length, 1);
  assert.match(out[0]!, /^claims lint: not run \(exit 1\): /);
});
