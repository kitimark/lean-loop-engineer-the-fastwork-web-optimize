import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { dispatchPlan, fillFacts, stepLine, tierMain, tierRequest, type Io } from "../src/ci-pool-tier.ts";
import { UsageError } from "../src/lib.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
type Line = { op: string; name: string; request: Record<string, unknown>; response: Record<string, unknown> };
const lines = readFileSync(join(root, "packages/contracts/golden/ci/pool-tier.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as Line);
const seven = lines.find((l) => l.name.startsWith("seven requests"))!;

describe("the Lean pool-tier golden, replayed through fwcore", () => {
  it("has rows for all six ops", () => {
    expect(new Set(lines.map((l) => l.op))).toEqual(new Set(["ci.poolTier", "ci.poolTierConsts", "ci.poolCell", "ci.cellMerged", "ci.poolRows", "ci.reroute"]));
  });
  for (const l of lines) {
    it(`${l.op}: ${l.name}`, () => {
      let got: Record<string, unknown>;
      try { got = call({ op: l.op, ...l.request }); } catch (e) { got = { error: (e as Error).message.replace(/^fwcore [\w.]+: /, "") }; }
      expect(got).toEqual(l.response);
    });
  }
  it("seven idle requests: GitHub 5, Codemagic 1, CircleCI 1, all seven in flight", () => {
    expect(seven.response.counts).toEqual({ github: 5, codemagic: 1, circleci: 1, bitrise: 0 });
    expect(seven.response.inflight).toBe(7);
  });
});

describe("fw ci pool tier and dispatch", () => {
  const facts = { cmUsed: 46, cmBusy: 0, ccSpent: 3575, ccStorage: 30 };
  const fake = (out: string[], ran: string[][], code = 0): Io => ({
    call: (req) => call(req), facts: async () => facts, run: (cmd) => { ran.push(cmd); return code; }, log: (l) => out.push(l) });

  it("builds the tier and consts requests", () => {
    const req = tierRequest(["tier", "--state", JSON.stringify(seven.request.state), "--reqs", JSON.stringify(seven.request.reqs)], root);
    expect(req).toEqual({ op: "ci.poolTier", ...seven.request });
    expect(tierRequest(["tier-consts", "--over", "{\"cmOn\":false}"], root)).toEqual({ op: "ci.poolTierConsts", over: { cmOn: false } });
  });
  it("refuses a tier without state or reqs and an unknown verb", () => {
    expect(() => tierRequest(["tier", "--state", "{}"], root)).toThrow(UsageError);
    expect(() => tierRequest(["nope"], root)).toThrow(UsageError);
  });
  it("fills only the facts the caller left out", () => {
    expect(fillFacts({ ghMacBusy: 0, ccSpent: 9000 }, facts)).toEqual({ ghMacBusy: 0, ccSpent: 9000, cmUsed: 46, cmBusy: 0, ccStorage: 30 });
  });
  it("plans one Codemagic trigger and one CircleCI trigger for the seven-request golden", () => {
    const plan = dispatchPlan(seven.response.log as never, "ci/macos-pool-7");
    expect(plan.filter((s) => s.cmd).map((s) => s.cmd)).toEqual([
      ["scripts/codemagic.mjs", "trigger", "--pool", "--branch", "ci/macos-pool-7"],
      ["scripts/circleci.mjs", "trigger", "--lane", "webkit-sim", "--branch", "ci/macos-pool-7"],
    ]);
    expect(plan.filter((s) => s.via === "github" && !s.cmd)).toHaveLength(5);
    expect(stepLine(plan[5]!)).toBe("webkit-sim rep 5: codemagic mac_mini_m2, cap 40 min -> node scripts/codemagic.mjs trigger --pool --branch ci/macos-pool-7");
  });
  it("dispatch --go fills the facts, runs the two commands and passes a stop-rule refusal on", async () => {
    const out: string[] = [];
    const ran: string[][] = [];
    const state = { ghMacBusy: 0, ghTotalBusy: 0 };
    const code = await tierMain(["dispatch", "--branch", "ci/macos-pool-7", "--state", JSON.stringify(state), "--reqs", JSON.stringify(seven.request.reqs), "--go"], root, fake(out, ran, 5));
    expect(code).toBe(5);
    expect(ran).toHaveLength(2);
    expect(out.filter((l) => l.endsWith("(the provider's stop rule refused)"))).toHaveLength(2);
    expect(out.find((l) => l.startsWith("counts "))).toContain("\"codemagic\":1");
  });
  it("dispatch without --go only prints, and needs a ci/ branch", async () => {
    const out: string[] = [];
    const ran: string[][] = [];
    const args = ["--state", "{\"ghMacBusy\":5,\"ghTotalBusy\":5}", "--reqs", JSON.stringify([(seven.request.reqs as unknown[])[0]])];
    expect(await tierMain(["dispatch", "--branch", "ci/macos-pool-7", ...args], root, fake(out, ran))).toBe(0);
    expect(ran).toEqual([]);
    expect(out[0]).toContain("codemagic mac_mini_m2");
    await expect(tierMain(["dispatch", "--branch", "main", ...args], root, fake(out, ran))).rejects.toThrow(UsageError);
  });
});
