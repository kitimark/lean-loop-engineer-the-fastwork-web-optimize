import { mkdtempSync, mkdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { buildBase, chooseBase, parseReflog } from "../src/core/build-base.ts";

// the same table as the `#guard`s at the end of lean/Fw/Obs/Stale.lean (chooseBase)
const L = [{ sha: "new", time: 1030 }, { sha: "old", time: 100 }];
describe("chooseBase (table shared with lean/Fw/Obs/Stale.lean)", () => {
  it.each([
    [1000, null, L, { sha: "old" }],
    [1000, { sha: "ancient", time: 50 }, L, { sha: "old" }],
    [1000, { sha: "old", time: 1001 }, L, { sha: "old" }],
    [1000, null, [{ sha: "new", time: 1030 }], { unknown: "no move of main at or before the binary" }],
    [1000, null, [], { unknown: "no move of main at or before the binary" }],
    [1000, null, [{ sha: "b", time: 100 }, { sha: "a", time: 100 }], { unknown: "two moves of main in the same second as the binary's base" }],
    [1000, { sha: "rec", time: 1000 }, [], { sha: "rec" }],
  ] as const)("%j %j %j -> %j", (bin, rec, log, want) => expect(chooseBase(bin, rec, [...log])).toEqual(want));
});

describe("parseReflog", () => {
  it("parses `%H %gd` lines with --date=unix and drops the rest", () => {
    const a = "a".repeat(40), b = "b".repeat(40);
    expect(parseReflog(`${a} main@{1030}\n${b} main@{100}\nnoise\n`)).toEqual([{ sha: a, time: 1030 }, { sha: b, time: 100 }]);
  });
});

describe("buildBase (files)", () => {
  const dirs: string[] = [];
  afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
  it("a missing binary is unknown; a record not older than the binary is its commit", () => {
    const d = mkdtempSync(join(tmpdir(), "fwbb-")); dirs.push(d);
    const bin = join(d, "fwcore");
    expect(buildBase(d, bin)).toEqual({ unknown: "no fwcore binary" });
    writeFileSync(bin, "x"); writeFileSync(`${bin}.commit`, "c".repeat(40) + "\n");
    utimesSync(bin, 1000, 1000); utimesSync(`${bin}.commit`, 1000, 1000);
    expect(buildBase(d, bin)).toEqual({ sha: "c".repeat(40) });
    mkdirSync(join(d, "sub"));
    utimesSync(`${bin}.commit`, 900, 900); // older: falls to the reflog; d is no git repo, so unknown with a reason
    expect("unknown" in buildBase(d, bin)).toBe(true);
  });
});
