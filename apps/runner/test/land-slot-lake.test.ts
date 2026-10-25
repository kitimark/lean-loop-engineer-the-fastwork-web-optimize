import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { run } from "../src/slot.ts";

function heldDeps(dir: string): never {
  const slot = join(dir, "slot");
  mkdirSync(slot, { recursive: true });
  writeFileSync(join(slot, "state.json"), JSON.stringify({ ctl: { n: 4, lastChange: 0, prev: null }, queue: [], simIdleSince: 0,
    holders: [{ owner: "o", token: "T1", kind: "land", since: 1, till: Math.floor(Date.now() / 1000) + 600, foot: 0, leaseS: 600 }] }));
  return { dir: slot, owner: "o", env: { FW_SLOT_HELD: "1", FW_SLOT_TOKEN: "T1", PATH: process.env.PATH }, out: () => {}, err: () => {} } as never;
}

describe("slot run land hands the child's lake member up to its span", () => {
  it("the span line carries it; a child that writes none, and a run of another kind, leave none", async () => {
    const dir = mkdtempSync(join(tmpdir(), "land-slot-lake-"));
    const file = join(dir, "timings.jsonl");
    process.env.FW_TIMINGS_FILE = file;
    try {
      const d = heldDeps(dir);
      const put = `printf '{"built":41}' > "$FW_SLOT_LAKE_FILE"`;
      expect(await run(d, "land", ["sh", "-c", `${put}; exit 0`], false)).toBe(0);
      expect(await run(d, "land", ["sh", "-c", "exit 0"], false)).toBe(0);
      expect(await run(d, "check", ["sh", "-c", `test -z "$FW_SLOT_LAKE_FILE"`], false)).toBe(0);
      const rows = readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l) as { step: string; lake?: { built: number } });
      expect(rows.map((r) => [r.step, r.lake])).toEqual([["slot run land", { built: 41 }], ["slot run land", undefined], ["slot run check", undefined]]);
    } finally {
      delete process.env.FW_TIMINGS_FILE;
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
