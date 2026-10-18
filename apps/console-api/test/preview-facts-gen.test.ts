import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const script = fileURLToPath(new URL("../scripts/gen-preview-facts.ts", import.meta.url));

describe("lean/Fw/Console/PreviewFacts.lean", () => {
  it("matches what the git glue reads at the pinned commits (skipped when the clone lacks them)", (ctx) => {
    const r = spawnSync(process.execPath, [script, "--check"], { encoding: "utf8", timeout: 120_000 });
    if (r.status === 2) ctx.skip(); // pinned objects missing (pin includes local-only refs): reported as skipped
    expect(r.stderr + r.stdout).toContain("matches git at the pin");
    expect(r.status).toBe(0);
  }, 130_000);
});
