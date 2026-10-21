import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { Target } from "@fw/gh-budget";
import { parseRunArgs, runMain, type FwCall, type Gh } from "../src/run.ts";
import { UsageError } from "../src/lib.ts";
import { ALLOWED_WIDTHS, dispatch, dispatchIn, enginesOf, legsOf, type Decision, type Engine, type Mark } from "../src/run-pick.ts";

// The scope of a trajectory dispatch is Lean's (lean/Fw/Gate/Trajectory/Dispatch.lean); every golden line is replayed against the TS stand-in.
const root = join(process.cwd(), "..", "..");
type Line =
  | { kind: "in"; mark: Mark; input: string; decision: string; why: string | null; widths: number[] | null; legs: Record<Engine, number[][]> | null }
  | { kind: "list"; mark: Mark; in: number[]; decision: string; why: string | null; widths: number[] | null; legs: Record<Engine, number[][]> | null }
  | { kind: "engines"; input: string; engines: Engine[] | null };
const lines = readFileSync(join(root, "packages", "contracts", "golden", "gate", "trajectory-dispatch.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as Line);

const asDecision = (l: { decision: string; why: string | null; widths: number[] | null }): Decision =>
  l.decision === "accepted" ? { kind: "accepted", widths: l.widths as number[] } : { kind: "refused", why: l.why as never };

describe("the dispatch scope equals Lean Fw.Gate.Trajectory.Dispatch", () => {
  it("has lines of every kind, mark and decision", () => {
    expect(new Set(lines.map((l) => l.kind))).toEqual(new Set(["in", "list", "engines"]));
    const ins = lines.filter((l) => l.kind !== "engines") as Extract<Line, { mark: Mark }>[];
    expect(new Set(ins.map((l) => `${l.mark} ${l.decision} ${l.why}`))).toEqual(new Set([
      "verdict accepted null", "verdict refused scopedVerdict", "verdict refused badInput", "verdict refused emptyWidths",
      "diagnostic accepted null", "diagnostic refused badInput", "diagnostic refused emptyWidths"]));
  });
  lines.forEach((l, i) => {
    if (l.kind === "engines") {
      it(`engines ${JSON.stringify(l.input)}`, () => { expect(enginesOf(l.input)).toEqual(l.engines); });
      return;
    }
    const d = l.kind === "in" ? dispatchIn(l.mark, l.input) : dispatch(l.mark, l.in);
    it(`${l.kind} ${l.mark} ${JSON.stringify(l.kind === "in" ? l.input : l.in)} (line ${i + 1})`, () => {
      expect(d).toEqual(asDecision(l));
      if (d.kind === "accepted") {
        for (const e of ["chromium", "linux-webkit", "mac-webkit"] as Engine[]) expect(legsOf(e, d.widths)).toEqual(l.legs?.[e]);
      } else {
        expect(l.legs).toBeNull();
      }
    });
  });
});

describe("the rules the Lean theorems state, on the twin", () => {
  it("a verdict dispatch that is accepted walks all four widths", () => {
    for (const l of lines) {
      if (l.kind === "engines" || l.mark !== "verdict" || l.decision !== "accepted") continue;
      expect([...(l.widths as number[])].sort()).toEqual([...ALLOWED_WIDTHS].sort());
    }
  });
  it("a diagnostic dispatch is never empty", () => {
    for (const l of lines) {
      if (l.kind === "engines" || l.mark !== "diagnostic" || l.decision !== "accepted") continue;
      expect((l.widths as number[]).length).toBeGreaterThan(0);
    }
  });
  it("one macOS leg exactly when the widths fall within {390,641} or within {640,1280}", () => {
    for (const l of lines) {
      if (l.kind !== "in" || l.mark !== "diagnostic" || l.decision !== "accepted") continue;
      const ws = l.widths as number[];
      const within = (s: number[]) => ws.every((w) => s.includes(w));
      expect(legsOf("mac-webkit", ws).length === 1).toBe(within([390, 641]) || within([640, 1280]));
    }
  });
});

describe("fw run --trajectory enforces the scope", () => {
  const SHA = "0123456789abcdef0123456789abcdef01234567";
  const call: FwCall = () => ({ fw: [], job: { blocked: null, inputs: { engines: "both", fw: "", preset: "", widths: "" }, workflow: "trajectory-probe.yml" }, problems: [] });
  const gh: Gh = async () => { throw new Error("a dry run or a refusal runs no gh"); };
  const run = async (argv: string[]) => {
    const logs: string[] = [];
    const code = await runMain(parseRunArgs(argv), { nonce: () => "n0nce1234", now: () => 1_800_000_000, wait: async (_t: Target) => ({ code: 0 as const, lines: [] }),
      call, gh, store: "", sha: SHA, branch: "main", tmp: "", log: (l: string) => logs.push(l) });
    return { code, logs: logs.join("\n") };
  };

  it("refuses a scoped verdict dispatch with a clear message, before any fwcore call or gh", async () => {
    for (const argv of [["--trajectory", "--widths", "390,1280"], ["--trajectory", "--widths", "390", "--dry"]]) {
      const r = await run(argv);
      expect(r.code).toBe(2);
      expect(r.logs).toMatch(/refused: --widths .* is a scoped dispatch.*verdict run.*all four widths \(390,640,641,1280\).*--diagnostic/);
    }
  });
  it("accepts a scoped --diagnostic dispatch and names the mark and the legs", async () => {
    const r = await run(["--trajectory", "--widths", "390,641", "--diagnostic", "--dry"]);
    expect(r.code).toBe(0);
    expect(r.logs).toMatch(/trajectory diagnostic, widths 390,641, legs chromium 2, linux-webkit 2, mac-webkit 1/);
  });
  it("sends the mark to the workflow as the diagnostic input, only for a diagnostic dispatch", async () => {
    const dia = await run(["--trajectory", "--widths", "390,641", "--diagnostic", "--dry"]);
    expect(dia.logs).toMatch(/trajectory-probe\.yml\s+inputs .*diagnostic=true/);
    const ver = await run(["--trajectory", "--dry"]);
    expect(ver.logs).not.toMatch(/diagnostic=/);
  });
  it("accepts a verdict dispatch over all four widths, given or default", async () => {
    for (const argv of [["--trajectory", "--dry"], ["--trajectory", "--widths", "1280,641,640,390", "--dry"]]) {
      const r = await run(argv);
      expect(r.code).toBe(0);
      expect(r.logs).toMatch(/trajectory verdict, widths .*legs chromium 4, linux-webkit 4, mac-webkit 2/);
    }
  });
  it("refuses a width outside the lane, diagnostic or not", async () => {
    for (const argv of [["--trajectory", "--widths", "800", "--diagnostic", "--dry"], ["--trajectory", "--widths", "800", "--dry"]]) {
      const r = await run(argv);
      expect(r.code).toBe(2);
      expect(r.logs).toMatch(/refused: --widths 800 must be a comma list/);
    }
  });
  it("--diagnostic belongs to --trajectory", () => {
    expect(() => parseRunArgs(["--gate", "--diagnostic"])).toThrow(UsageError);
    expect(parseRunArgs(["--trajectory", "--widths", "390", "--diagnostic"])).toMatchObject({ diagnostic: true, widths: "390" });
    expect(parseRunArgs(["--trajectory"]).diagnostic).toBeUndefined();
  });
});
