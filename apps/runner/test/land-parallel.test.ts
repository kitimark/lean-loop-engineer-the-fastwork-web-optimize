// Dependency rule of the one-wave dry land: Lean Fw.Ops.LandDry.deps (lake_serial, core_after_builds, install_first).
// The golden packages/contracts/golden/ops/land-dry-deps.jsonl holds kind lists and the deps Lean computes for them.
import "./land-timeout.ts";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { BUILD_ARGV } from "../src/land-remote.ts";
import { checkDeps, checkKind, FWCORE_USERS, type CheckKind } from "../src/land.ts";
import { LINT_ARGV } from "../src/land-verdict.ts";

const golden = readFileSync(join(import.meta.dirname, "..", "..", "..", "packages/contracts/golden/ops/land-dry-deps.jsonl"), "utf8")
  .split("\n").filter(Boolean).map((l) => JSON.parse(l) as { kinds: CheckKind[]; deps: number[][] });

/** One command line per kind, built from the constants the land uses; the n-th use of coreUser takes the n-th fwcore user. */
const exemplar = (k: CheckKind, n: number): string[] => {
  switch (k) {
    case "install": return ["pnpm", "install", "--frozen-lockfile"];
    case "lakeLint": return LINT_ARGV.axioms;
    case "fwcoreBuild": return BUILD_ARGV;
    case "coreUser": return ["pnpm", "--filter", `./${FWCORE_USERS[n % FWCORE_USERS.length]}`, "test"];
    default: return ["node", "scripts/ci-paths.mjs", "--check", String(n)];
  }
};
const argvOf = (kinds: CheckKind[]): string[][] => kinds.map((k, i) => exemplar(k, i));

describe("checkDeps vs the Lean golden (land-dry-deps.jsonl)", () => {
  it("the golden has rows", () => expect(golden.length).toBeGreaterThan(8));
  for (const [n, row] of golden.entries()) {
    it(`row ${n}: ${row.kinds.join(",") || "empty"}`, () => {
      const list = argvOf(row.kinds);
      expect(list.map(checkKind)).toEqual(row.kinds);
      expect(checkDeps(list)).toEqual(row.deps);
    });
  }
});

describe("checkKind classifies by identity", () => {
  it("the reads test and compose-style filters are core users; lints that do not read lean/.lake are other", () => {
    expect(checkKind(["pnpm", "--filter", "./apps/runner", "exec", "vitest", "run", "test/land-inputs.test.ts"])).toBe("coreUser");
    expect(checkKind(["pnpm", "--filter", "./packages/contracts", "test"])).toBe("other");
    expect(checkKind(["sh", "scripts/check-workflows.sh"])).toBe("other");
    expect(checkKind(["sh", "lean/scripts/check.sh"])).toBe("other");
    expect(checkKind(["pnpm", "install"])).toBe("install");
  });
});
