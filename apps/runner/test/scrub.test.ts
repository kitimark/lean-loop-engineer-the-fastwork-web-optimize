// The privacy scrub's own tests (scripts/scrub.mjs rules, invented names only), run at every land that touches the
// runner read set (PACKAGE_EXTRA_READS["apps/runner"] lists the scrub files). Node stdlib only.
import "./land-timeout.ts";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";

const root = join(dirname(new URL(import.meta.url).pathname), "../../..");
const node = (...args: string[]) => {
  const r = spawnSync("node", args, { cwd: root, encoding: "utf8" });
  return { status: r.status, out: `${r.stdout ?? ""}${r.stderr ?? ""}` };
};

describe("privacy scrub tests", () => {
  it("node --test scripts/scrub.test.mjs exits 0", () => {
    const r = node("--test", "scripts/scrub.test.mjs");
    expect(r.out).toMatch(/fail 0/);
    expect(r.status).toBe(0);
  });
  it("node scripts/test-scrub.mjs exits 0", () => {
    const r = node("scripts/test-scrub.mjs");
    expect(r.status).toBe(0);
  });
});
