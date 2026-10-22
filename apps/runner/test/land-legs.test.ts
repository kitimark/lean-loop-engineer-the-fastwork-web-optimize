import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { checksCli, parseChecksArgs, type Runner } from "../src/checks.ts";
import { laneStateOf, legsPass, type GhRunView } from "../src/land-remote.ts";
import { fwcoreCall } from "../src/run.ts";
import { UsageError } from "../src/lib.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const core = fwcoreCall(root);
const golden = readFileSync(join(root, "packages/contracts/golden/console/land-legs.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });
const legNames = readFileSync(join(root, "lean/land-legs.txt"), "utf8").trim().split(" ");

describe("fwcore reproduces the land-legs golden", () => {
  it("has a case per leg and selection, and the verdict cases", () => {
    expect(golden.filter((c) => c.request.op === "console.landLeg").length).toBe(legNames.length * 6);
    expect(golden.filter((c) => c.request.op === "console.landLegs").length).toBe(6);
    expect(golden.filter((c) => c.request.op === "console.landLegsVeto").length).toBe(7);
  });
  for (const c of golden) it(c.name, () => expect(core(c.request)).toEqual(c.response));
});

describe("land.yml runs exactly the legs Lean names", () => {
  const yml = readFileSync(join(root, ".github/workflows/land.yml"), "utf8");
  it("the matrix is lean/land-legs.txt, in order", () => {
    const m = /matrix:\s*\n\s*leg:\s*\[([^\]]*)\]/.exec(yml);
    expect(m).not.toBeNull();
    expect(m![1]!.split(",").map((s) => s.trim())).toEqual(legNames);
  });
  it("every leg passes its name to fw checks", () => {
    expect(yml).toContain("--leg \"$LEG\"");
  });
});

describe("fw checks --leg", () => {
  const ALL = ["apps/runner/src/checks.ts"];
  const legRun = async (leg: string, changed: string[]) => {
    const lines: string[] = [];
    const ran: string[][] = [];
    const run: Runner = async (argv) => (ran.push(argv), { code: 0, out: "# tests 1\n# skipped 0" });
    const code = await checksCli(["--affected", "--base", "x", "--tier", "remote", "--leg", leg], root, { core, run, changed, log: (s) => lines.push(s) });
    return { code, lines, ran };
  };
  it("--leg needs --tier remote", () => {
    expect(() => parseChecksArgs(["--affected", "--base", "x", "--leg", "suites-a"])).toThrow(UsageError);
  });
  it("every leg prints the digest of the whole remote tier", async () => {
    const digests = new Set<string>();
    for (const l of legNames) digests.add((await legRun(l, ALL)).lines.find((x) => x.startsWith("LANE digest="))!);
    expect(digests.size).toBe(1);
  });
  it("the check-sh leg runs the Lean script and only it, when the change selects it", async () => {
    const r = await legRun("check-sh", ["lean/Fw/Console/LandTier.lean"]);
    expect(r.ran).toEqual([["sh", "lean/scripts/check.sh"]]);
    expect(r.lines).toContain("VERDICT pass check.sh");
    expect(r.lines.filter((x) => x.startsWith("VERDICT")).length).toBe(1);
    const other = await legRun("check-sh", ALL);
    expect(other.ran).toEqual([]);
  });
  it("the suites legs together run the remote checks once; the engine legs run none", async () => {
    const verdicts: string[] = [];
    for (const l of legNames) {
      const r = await legRun(l, ALL);
      expect(r.code).toBe(0);
      const v = r.lines.filter((x) => x.startsWith("VERDICT"));
      if (l.startsWith("suites")) verdicts.push(...v); else expect(v).toEqual([]);
    }
    expect(verdicts.sort()).toEqual(["VERDICT pass apps/runner", "VERDICT pass packages/engine-check"]);
  });
  it("the engine legs report engine=false without the browser check and engine=true with it", async () => {
    const none = await legRun("chromium", ALL);
    expect(none.lines).toContain("LANE leg=chromium engine=false checks=0");
    const withBrowser = await legRun("playwright-webkit", ["packages/e2e-preview/src/run.mjs"]);
    expect(withBrowser.lines).toContain("LANE leg=playwright-webkit engine=true checks=0");
    const suites = await legRun("suites-a", ["packages/e2e-preview/src/run.mjs"]);
    expect(suites.lines.find((x) => x.startsWith("LANE leg=suites-a"))).toMatch(/engine=false/);
  });
});

describe("the verdict over all legs (Lean legsOk) vetoes a pass", () => {
  const view = (conclusions: (string | null)[], over: Partial<GhRunView> = {}): GhRunView => ({
    headSha: "a".repeat(40), status: "completed", conclusion: "success", ...over,
    jobs: [{ name: "guard", conclusion: "success" }, ...conclusions.map((c, i) => ({ name: `land (${legNames[i] ?? i})`, conclusion: c, ...(c === null ? {} : { status: "completed" }) }))],
  });
  it("all legs passed: the run passes", () => {
    expect(legsPass(core, view(["success", "success", "success", "success"]))).toBe(true);
    expect(laneStateOf(core, 0, "", view(["success", "success", "success", "success"]))).toBe("pass");
  });
  it("a run that says success while one leg did not pass is a fail", () => {
    expect(legsPass(core, view(["success", "skipped", "success", "success"]))).toBe(false);
    expect(laneStateOf(core, 0, "", view(["success", "success", "success", "cancelled"]))).toBe("fail");
  });
  it("a record without leg conclusions does not veto (the cached facts)", () => {
    expect(legsPass(core, view(["success", null]))).toBe(true);
    expect(legsPass(core, null)).toBe(true);
  });
});
