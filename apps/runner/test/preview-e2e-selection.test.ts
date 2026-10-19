// Task preview-e2e: the land lane runs the browser-free tests of packages/e2e-preview only when a file of its declared read
// set changes (a change outside does not select it, a change inside does). The browser suite itself is the preview-e2e.yml lane
// (selection: scripts/ci-paths.test.mjs). Reads: PACKAGE_EXTRA_READS["packages/e2e-preview"] in src/land.ts.
import "./land-timeout.ts";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";
import { candidateChecks, checksWithReads, FWCORE_USERS } from "../src/land.ts";

const root = join(dirname(new URL(import.meta.url).pathname), "../../..");
const ID = "packages/e2e-preview";
const selected = (changed: string[]) => checksWithReads(root, changed).map((c) => c.id);

describe("packages/e2e-preview is selected by its read set only", () => {
  it("is a candidate check on the CI tier and reads the fwcore binary", () => {
    expect(candidateChecks(root).map((c) => c.id)).toContain(ID);
    expect(FWCORE_USERS).toContain(ID); // console-api decides through fwcore
    const golden = readFileSync(join(root, "packages/contracts/golden/console/land-tier.jsonl"), "utf8");
    expect(golden).toContain(`"${ID}"`);
    expect(readFileSync(join(root, "lean/land-filter.txt"), "utf8")).toContain("@fw/e2e-preview...");
  });
  it("a change inside the read set selects it", () => {
    for (const f of ["packages/e2e-preview/src/suite.mjs", "packages/e2e-preview/fixture/site/index.html", "apps/console-api/src/preview/proxy.ts",
      "apps/console-api/src/app.ts", "lean/Fw/Console/PreviewOwner.lean", "packages/contracts/golden/console/preview-owner.jsonl", "snapshot/site/index.html"]) {
      expect(selected([f]), f).toContain(ID);
    }
  });
  it("a change outside the read set does not", () => {
    for (const f of ["apps/console-web/src/main.tsx", "apps/site/src/index.ts", "docs/team/handoffs/x.md", "packages/measure-chromium/src/a.mjs", "packages/visual-diff/src/a.mjs"]) {
      expect(selected([f]), f).not.toContain(ID);
    }
  });
});
