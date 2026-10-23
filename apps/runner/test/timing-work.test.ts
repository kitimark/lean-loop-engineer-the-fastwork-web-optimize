import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { slotWork } from "../src/timing.ts";
import { parseSamples } from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const golden = readFileSync(join(root, "packages/contracts/golden/obs/timing-work.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; span: Record<string, unknown>; work: Record<string, string> });
const dir = mkdtempSync(join(tmpdir(), "fw-timing-work-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

describe("span slot -> sample work against Fw.Obs.Timing.slotWork (golden/obs/timing-work.jsonl)", () => {
  it("has the golden rows, one without a slot member", () => {
    expect(golden.length).toBeGreaterThanOrEqual(4);
    expect(golden.some((g) => g.span.slot === undefined)).toBe(true);
  });
  for (const g of golden) {
    it(`parseSamples: ${g.name}`, () => {
      const [s] = parseSamples(JSON.stringify(g.span));
      expect(s!.work ?? {}).toEqual(g.work);
      expect(s!.durMs).toBe(g.span.durMs);
    });
  }
  it("a slot member without an integer width gives no work dimensions", () => {
    expect([slotWork(undefined), slotWork(null), slotWork({ jobs: 30 }), slotWork({ width: "2" }), slotWork({ width: 1.5 }), slotWork({ width: -1 })])
      .toEqual([{}, {}, {}, {}, {}, {}]);
  });
});

describe("scripts/span.sh span_more", () => {
  it("adds the slot member to the line of the command that sets it, and to no later line", () => {
    const file = join(dir, "timings.jsonl");
    const sh = join(root, "scripts/span.sh");
    writeFileSync(join(dir, "t.sh"), `. "${sh}"\ngroup() { span_more=",\\"slot\\":{\\"width\\":2,\\"jobs\\":30}"; }\nspan lean/check "parallel group" group\nspan lean/check "after" true\n`);
    execFileSync("sh", [join(dir, "t.sh")], { env: { ...process.env, FW_TIMINGS_FILE: file } });
    const text = readFileSync(file, "utf8");
    const l = text.split("\n").filter(Boolean).map((x) => JSON.parse(x) as { slot?: unknown });
    expect(l.map((x) => x.slot)).toEqual([{ width: 2, jobs: 30 }, undefined]);
    expect(parseSamples(text).map((s) => s.work)).toEqual([{ width: "2" }, undefined]);
  });
});
