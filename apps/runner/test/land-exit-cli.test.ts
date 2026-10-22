import "./land-timeout.ts";
import { existsSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { checkoutLandWt, dryLandReport, landExit } from "../src/land.ts";
import { exitCode, outcome, parseVerdict } from "../src/land-verdict.ts";

describe("dry land CLI report (item 1)", () => {
  it("a failed dry install prints the stage lines up to the install, then VERDICT install, exit 19", () => {
    const rep = dryLandReport({ lines: ["REFUSED: install failed in /d"], outcome: outcome({ installs: false }) }, "t1");
    expect(rep.err).toEqual(["REFUSED: install failed in /d"]);
    expect(rep.out).toContain("dry: conflict ok");
    expect(rep.out).not.toContain("dry: install ok");
    expect(rep.out.at(-1)).toBe("VERDICT install t1");
    expect(parseVerdict(rep.out.join("\n"))?.kind).toBe("install");
    expect(rep.code).toBe(19);
  });
  it("a dry land that threw has no outcome: threw verdict from the same Lean mapping", () => {
    const rep = dryLandReport({ lines: ["REFUSED: x"] }, "t1");
    expect(rep.out.at(-1)).toMatch(/^VERDICT /);
    expect(rep.code).toBe(exitCode(parseVerdict(rep.out.join("\n"))!.kind));
  });
  it("an all-green outcome ends in VERDICT dry, exit 0", () => {
    const rep = dryLandReport({ lines: [], outcome: outcome({}) }, "t1");
    expect(rep.out.at(-1)).toBe("VERDICT dry t1");
    expect(rep.code).toBe(0);
  });
});

describe("real land exit (item 2)", () => {
  it("landExit maps kind, and falls back to done/unknown from ok", () => {
    expect(landExit({ ok: false, kind: "install" })).toBe(19);
    expect(landExit({ ok: true })).toBe(0);
    expect(landExit({ ok: false })).toBe(exitCode("unknown"));
  });
});

describe("checkoutLandWt clean count (item 3)", () => {
  it("a reused worktree keeps what prep wrote (no trailing clean); a new one is still cleaned", () => {
    const fx = makeRepo();
    const dir = join(fx.root, "..", "land-wt-clean");
    const head = fx.git(fx.root, "rev-parse", "HEAD").trim();
    const prep = (d: string) => { writeFileSync(join(d, "prep-out.txt"), "x"); };
    checkoutLandWt(fx.root, dir, head, prep);
    expect(existsSync(join(dir, "prep-out.txt"))).toBe(false);
    checkoutLandWt(fx.root, dir, head, prep);
    expect(existsSync(join(dir, "prep-out.txt"))).toBe(true);
  });
});
