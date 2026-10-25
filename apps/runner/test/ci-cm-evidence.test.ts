// A Codemagic build id as review evidence: Lean `Fw.Plan.ReviewReady.runIdOf` takes `cm:` and 24 lowercase hex digits.
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { coreCandidates, coreCaller } from "../src/watch.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: root, encoding: "utf8" }).trim();
const bins = coreCandidates(root, join(common, "..")).filter((b) => {
  try { return execFileSync(b, ["--ops"], { encoding: "utf8" }).includes("plan.reviewReady"); } catch { return false; }
});
const call = coreCaller(bins);
const CM = "0123456789abcdef01234567";
const ready = async (evidence: string, runs: unknown[] = []) => JSON.stringify(await call({ op: "plan.reviewReady", items: [{ id: "x", status: "pending", evidence }], runs, task: "t", dry: "VERDICT dry t" }));

describe("plan.reviewReady with Codemagic build ids", () => {
  it("fwcore with the ops is built", () => expect(bins.length).toBeGreaterThan(0));
  it("a pending item citing cm:<24 hex> needs that run complete, like a GitHub run id", async () => {
    expect(await ready(`cm:${CM}`, [{ id: `cm:${CM}`, state: "complete" }])).toContain("review");
    expect(await ready(`cm:${CM}`, [])).toContain("returnToBuilder");
  });
  it("a malformed build id is not evidence", async () => {
    for (const bad of [`cm:${CM}0`, `cm:${CM.slice(1)}`, `cm:${CM.toUpperCase()}`, `cm:${CM.slice(0, 23)}g`]) expect(await ready(bad, [{ id: bad, state: "complete" }])).toContain("returnToBuilder");
  });
});
