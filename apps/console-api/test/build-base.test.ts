import { createHash } from "node:crypto";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { binIn, buildBase, chooseBase, parseRecord, readRecord } from "../src/core/build-base.ts";

const sha256 = (t: string) => createHash("sha256").update(t).digest("hex");
const C = "c".repeat(40);

// the same table as the `#guard`s and theorems at the end of lean/Fw/Obs/Stale.lean (chooseBase)
describe("chooseBase (table shared with lean/Fw/Obs/Stale.lean)", () => {
  it("an accepted record is the base (chooseBase_accepted, chooseBase_at_iff)", () => {
    expect(chooseBase("H1", { sha: "c1", hash: "H1" })).toEqual({ sha: "c1" });
  });
  it("a record of another binary is unknown (chooseBase_mismatch)", () => {
    expect("unknown" in chooseBase("H2", { sha: "c1", hash: "H1" })).toBe(true);
  });
  it("no record is unknown (chooseBase_none)", () => {
    expect("unknown" in chooseBase("H1", null)).toBe(true);
  });
});

describe("parseRecord", () => {
  it("reads `<sha> <sha256>` and rejects anything else", () => {
    expect(parseRecord(`${C} ${sha256("x")}\n`)).toEqual({ sha: C, hash: sha256("x") });
    for (const bad of ["", C, `${C}\n`, `${C} short`, `zz ${sha256("x")}`, `${C} ${sha256("x")} extra`]) expect(parseRecord(bad)).toBeNull();
  });
});

describe("buildBase (files)", () => {
  const dirs: string[] = [];
  afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
  const checkout = () => {
    const d = mkdtempSync(join(tmpdir(), "fwbb-")); dirs.push(d);
    mkdirSync(join(d, "lean/.lake/build/bin"), { recursive: true });
    return { d, bin: binIn(d) };
  };
  it("a missing binary is unknown", () => {
    const { d, bin } = checkout();
    expect("unknown" in buildBase(d, bin)).toBe(true);
  });
  it("accepted only when the recorded sha256 is the binary's: identity, whatever the file times", () => {
    const { d, bin } = checkout();
    writeFileSync(bin, "built");
    expect(buildBase(d, bin)).toEqual({ unknown: "no build record: build with scripts/fwcore-build.sh" });
    writeFileSync(`${bin}.commit`, `${C} ${sha256("built")}\n`);
    expect(buildBase(d, bin)).toEqual({ sha: C });
    expect(readRecord(bin)).toEqual({ sha: C, hash: sha256("built") });
    writeFileSync(bin, "rebuilt by a plain lake build"); // the record is left behind, of another binary
    const b = buildBase(d, bin);
    expect("unknown" in b && b.unknown).toContain("does not match the binary");
  });
  it("a binary that is not the checkout's own build (FW_CORE_BIN, another checkout) without a matching record is unknown and says so; with a matching record it is accepted", () => {
    const mine = checkout(); const other = checkout();
    writeFileSync(other.bin, "x");
    const b = buildBase(mine.d, other.bin);
    expect("unknown" in b && b.unknown).toContain("not lean/.lake/build/bin/fwcore of the checkout this code runs from");
    writeFileSync(`${other.bin}.commit`, `${C} ${sha256("x")}\n`);
    expect(buildBase(mine.d, other.bin)).toEqual({ sha: C });
    // main's data is never used for another checkout: mine has a matching record, the other binary does not
    writeFileSync(mine.bin, "y"); writeFileSync(`${mine.bin}.commit`, `${C} ${sha256("y")}\n`);
    writeFileSync(other.bin, "z");
    expect("unknown" in buildBase(mine.d, other.bin)).toBe(true);
  });
});
