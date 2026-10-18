// Land check for the CI push triggers (task ci-trigger-lean). The Lean decision is lean/Fw/Ci/Trigger.lean (golden
// packages/contracts/golden/ci/triggers.jsonl); scripts/ci-paths.mjs expands it. This fails when a workflow's `on.push`
// differs from the decision, when a workflow has no guard job, or when a job does not wait for it. Fix: `node scripts/ci-paths.mjs --write`.
import "./land-timeout.ts";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";

const root = join(dirname(new URL(import.meta.url).pathname), "../../..");
const node = (...args: string[]) => {
  try { return { ok: true, out: execFileSync("node", args, { cwd: root, encoding: "utf8" }) }; }
  catch (e) { const x = e as { stdout?: string; stderr?: string }; return { ok: false, out: `${x.stdout ?? ""}${x.stderr ?? ""}` }; }
};

describe("CI push triggers equal the Lean decision", () => {
  it("every workflow: on.push, guard job, needs", () => {
    const r = node("scripts/ci-paths.mjs");
    expect(r.out).toContain("equals the Lean decision");
    expect(r.ok).toBe(true);
  });
  it("the replay cases and the lint's own tests pass", () => {
    const r = node("--test", "scripts/ci-paths.test.mjs", ".github/scripts/changed-inputs.test.mjs", "scripts/ci-push.test.mjs");
    expect(r.out).toMatch(/fail 0/);
    expect(r.ok).toBe(true);
  });
});
