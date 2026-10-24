import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { claimLandWt, LAND_WT_INPUT_RE, landWtDist, pickLandWt, type WtSlot } from "../src/land.ts";

const here = dirname(fileURLToPath(import.meta.url));
const rows = readFileSync(join(here, "../../../packages/contracts/golden/console/land-wt.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: { slots?: WtSlot[]; path?: string }; response: { pick?: number | null; input?: boolean } });
const pickRows = rows.filter((r) => r.request.slots !== undefined);
const inputRows = rows.filter((r) => r.request.path !== undefined);

let dirs: string[] = [];
afterEach(() => { dirs.forEach((d) => rmSync(d, { recursive: true, force: true })); dirs = []; });

describe("pickLandWt against the Lean golden", () => {
  it("has the rows", () => { expect(pickRows.length).toBeGreaterThanOrEqual(8); });
  for (const r of pickRows) it(r.name, () => { expect(pickLandWt(r.request.slots!)).toBe(r.response.pick); });
});

describe("LAND_WT_INPUT_RE against the Lean input rule", () => {
  it("has the rows", () => { expect(inputRows.length).toBeGreaterThanOrEqual(8); });
  for (const r of inputRows) it(r.name, () => { expect(LAND_WT_INPUT_RE.test(r.request.path!)).toBe(r.response.input); });
});

describe("claimLandWt", () => {
  it("without a commit takes the lowest free number, as before", () => {
    const main = mkdtempSync(join(tmpdir(), "lwt-")); dirs.push(main);
    const a = claimLandWt(main), b = claimLandWt(main);
    expect([a.dir.endsWith("/0"), b.dir.endsWith("/1")]).toEqual([true, true]);
    a.free();
    const c = claimLandWt(main);
    expect(c.dir.endsWith("/0")).toBe(true);
    [b, c].forEach((x) => x.free());
  });
  it("a worktree with no lake state has no distance", () => {
    const d = mkdtempSync(join(tmpdir(), "lwt-")); dirs.push(d);
    mkdirSync(join(d, "lean"));
    expect(existsSync(join(d, "lean", ".lake"))).toBe(false);
    expect(landWtDist(d, "HEAD")).toBeNull();
  });
  it("a claim left by a dead process is taken over", () => {
    const main = mkdtempSync(join(tmpdir(), "lwt-")); dirs.push(main);
    mkdirSync(join(main, ".claude", "land-wt"), { recursive: true });
    writeFileSync(join(main, ".claude", "land-wt", "0.claim"), "2147483646\n");
    const a = claimLandWt(main);
    expect(a.dir.endsWith("/0")).toBe(true);
    a.free();
  });
});
