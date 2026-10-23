// checkmap workflow kind (task checkmap-workflow-scripts): `.claude/workflows/*.js` are workflow bodies (top-level
// return and await), parsed as an AsyncFunction after stripping `export const meta = `; `node --check` is not used.
//   node --test scripts/checkmap.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("./checkmap.mjs", import.meta.url));
const real = fileURLToPath(new URL("../.claude/workflows/build-review.js", import.meta.url));
const node2422 = join(homedir(), ".nvm/versions/node/v24.22.0/bin/node");
const nodes = [["current node", process.execPath], ...(existsSync(node2422) ? [["node 24.22", node2422]] : [])];

const check = (node, f) => spawnSync(node, [script, "file", "workflow", f], { encoding: "utf8" });

for (const [label, node] of nodes) {
  test(`${label}: build-review.js is accepted`, () => {
    const r = check(node, real);
    assert.equal(r.status, 0, r.stderr);
  });
  test(`${label}: a body with a syntax error is refused`, () => {
    const dir = mkdtempSync(join(tmpdir(), "wf-"));
    try {
      const f = join(dir, "bad.js");
      writeFileSync(f, "export const meta = { name: 'x' }\nconst a = await agent('p'\nreturn a\n");
      const r = check(node, f);
      assert.equal(r.status, 1);
      assert.match(r.stderr, /bad\.js/);
      assert.doesNotMatch(r.stderr, /ENOENT/);  // refused for the syntax error, not for a missing file
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
}
