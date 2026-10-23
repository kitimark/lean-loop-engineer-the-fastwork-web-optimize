import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { GH_BOUNDS } from "@fw/gh-budget";
import { describe, expect, it } from "vitest";
import { recordStateParts, stateStep } from "../src/ci.ts";
import { GhClock, ciStateParts } from "../src/run-phases.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

describe("fw ci state: which list to read next (Lean Fw.Ci.StateList golden)", () => {
  const rows = readFileSync(join(root, "packages/contracts/golden/ci/state-list.jsonl"), "utf8").split("\n").filter(Boolean)
    .map((l) => JSON.parse(l) as { name: string; narrowed: boolean; limit: number; id: number; ids: number[]; response: unknown });
  it("has a row for every outcome", () => {
    expect(new Set(rows.map((r) => (r.response as { step: string }).step))).toEqual(new Set(["found", "ended", "older", "absent", "grow", "exhausted"]));
  });
  for (const r of rows) it(r.name, () => expect(stateStep(r.narrowed, r.limit, r.id, r.ids)).toEqual(r.response));
});

describe("fw ci state spans", () => {
  it("the state read inside the lock is its own part, carved out of the lock wait", () => {
    let t = 0;
    const c = new GhClock(undefined, () => t);
    c.start();
    t = 50; c.on("loadStart");
    t = 58; c.on("loadEnd");
    t = 60; c.on("reserve");
    t = 70; c.on("issue");
    t = 170; c.on("ghEnd");
    expect(c.loadMs).toBe(8);
    expect(c.ms).toEqual({ lock: 52, reserve: 10, call: 100, backoff: 0 });
    expect(ciStateParts(c, 175).map((p) => [p.step, p.durMs])).toEqual([
      ["ci state gh lock", 52], ["ci state gh load", 8], ["ci state gh reserve", 10], ["ci state gh call", 100], ["ci state reduce", 5]]);
  });
  it("every part span carries the real exit of the command, 2 included", () => {
    const seen: (number | null)[] = [];
    recordStateParts([{ step: "ci state gh lock", durMs: 1 }, { step: "ci state reduce", durMs: 2 }], 5, 2, (s) => seen.push(s.exit));
    expect(seen).toEqual([2, 2]);
  });
});

describe("bounds and tools of this task", () => {
  it("land.ts reads its gh timeout from GH_BOUNDS, not a literal", () => {
    const src = readFileSync(join(root, "apps/runner/src/land.ts"), "utf8");
    expect(src).toContain("GH_BOUNDS.landCallTimeoutMs");
    expect(src).not.toMatch(/ghCost\(args\) \}\), \(\) => args, \d/);
    expect(GH_BOUNDS.landCallTimeoutMs).toBe(20000);
  });
  it("timings.md lists the ci state step names", () => {
    const md = readFileSync(join(root, "docs/team/tools/timings.md"), "utf8");
    for (const s of ["ci state", "ci state gh lock", "ci state gh load", "ci state gh reserve", "ci state gh call", "ci state gh backoff", "ci state reduce"]) expect(md).toContain("`" + s + "`");
  });
  it("gh-hung-probe removes its temp directory", () => {
    const mine = () => readdirSync(tmpdir()).filter((n) => n.startsWith("gh-hung-probe-"));
    const before = mine();
    const r = spawnSync(process.execPath, [join(root, "scripts/gh-hung-probe.mjs"), "--sleep", "3", "--timeout-ms", "500", "--lock-wait-ms", "3000", "--waiter-delay", "0.2"], { encoding: "utf8" });
    expect(r.status).toBe(0);
    expect(mine()).toEqual(before);
  });
});
