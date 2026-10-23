import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { candidateChecks, checksWithReads, FWCORE_USERS, LOCAL_TESTS, selectChecks } from "../src/land.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
type Row = { name: string; request: { changed: string[]; tests: { id: string; reads: string[] }[] }; response: { select: string[] } };
const rows: Row[] = readFileSync(join(root, "packages/contracts/golden/console/land-tier-local.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("local test selection follows the Lean golden", () => {
  it("the declared tests are the Lean table", () => {
    for (const r of rows) expect(r.request.tests).toEqual(LOCAL_TESTS.map((t) => ({ id: t.id, reads: t.reads })));
  });
  it("has selecting and non-selecting cases", () => {
    expect(rows.some((r) => r.response.select.length > 0)).toBe(true);
    expect(rows.some((r) => r.response.select.length === 0)).toBe(true);
  });
  for (const r of rows) it(r.name, () => expect(selectChecks(r.request.tests, r.request.changed)).toEqual(r.response.select));
});

describe("fw land selects compose.test", () => {
  it("a changed part.json selects it, with its argv naming the test file", () => {
    const c = checksWithReads(root, ["apps/site/src/parts/nav/part.json"]).find((x) => x.id === "console-api:compose");
    expect(c?.argv.at(-1)).toBe("test/compose.test.ts");
  });
  it("a changed findings ledger selects it", () => {
    expect(checksWithReads(root, ["research/findings/ledger.json"]).map((x) => x.id)).toContain("console-api:compose");
  });
  it("it is a candidate check", () => {
    expect(candidateChecks(root).some((x) => x.id === "console-api:compose")).toBe(true);
  });
});

describe("a workflow change selects the overflow width test locally (incident 2026-10-24, task checkmap-workflow-widths-local)", () => {
  const ID = "runner:overflow-widths";
  it("every workflow file in the tree selects it; it is a fwcore user whose argv names the test file", () => {
    const workflows = readdirSync(join(root, ".github/workflows")).filter((f) => /\.ya?ml$/.test(f));
    expect(workflows).toContain("path-pix.yml");
    for (const f of workflows) expect(checksWithReads(root, [`.github/workflows/${f}`]).map((c) => c.id), f).toContain(ID);
    expect(candidateChecks(root).find((x) => x.id === ID)!.argv.at(-1)).toBe("test/land-overflow-widths.test.ts");
    expect(FWCORE_USERS).toContain(ID);
  });
});
