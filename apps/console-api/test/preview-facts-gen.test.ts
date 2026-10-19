import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const script = fileURLToPath(new URL("../scripts/gen-preview-facts.ts", import.meta.url));

describe("lean/Fw/Console/PreviewFacts.lean", () => {
  it("matches what the git glue reads at the pinned commits (skipped locally when the clone lacks them; on CI they must be there)", (ctx) => {
    const r = spawnSync(process.execPath, [script, "--check"], { encoding: "utf8", timeout: 120_000 });
    // Pinned objects missing: a Mac clone may lack them (reported as skipped). On CI they come from origin/ci/preview-pin, an
    // octopus commit over the pinned commits that only local branches held (no file changes, runs no lane); a missing one fails.
    if (r.status === 2 && !process.env.GITHUB_ACTIONS) ctx.skip();
    expect(r.stderr + r.stdout).toContain("matches git at the pin");
    expect(r.status).toBe(0);
  }, 130_000);
});
