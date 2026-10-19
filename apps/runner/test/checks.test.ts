// `fw checks` (task land-lane): the tier and the lane verdict are the Lean golden (land-tier.jsonl), the selection is the
// land.ts one; the real fwcore binary is required (a missing build fails, it does not skip).
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { checksCli, parseChecksArgs, planFor, runTier, skippedCount, type Runner } from "../src/checks.ts";
import { candidateChecks, FWCORE_USERS } from "../src/land.ts";
import { fwcoreCall } from "../src/run.ts";
import { UsageError } from "../src/lib.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const core = fwcoreCall(root);
const golden = readFileSync(join(root, "packages/contracts/golden/console/land-tier.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });
const REMOTE = ["apps/runner", "apps/console-api", "packages/gate-breakpoints", "packages/gh-budget", "packages/measure-chromium", "packages/engine-check"];

describe("fwcore reproduces the land-tier golden", () => {
  it("has tier and lane cases", () => {
    expect(golden.filter((c) => c.request.op === "console.landTier").length).toBeGreaterThan(10);
    expect(golden.filter((c) => c.request.op === "console.landLane").length).toBe(9);
  });
  for (const c of golden) it(c.name, () => expect(core(c.request)).toEqual(c.response));
});

describe("planFor: Lean selection, Lean tier", () => {
  const ids = (ps: { id: string }[]) => ps.map((c) => c.id);
  it("a Lean-only change selects check.sh, the fwcore users and the scan; the allowlisted suites are remote", () => {
    const p = planFor(root, ["lean/Fw/Console/LandTier.lean"], core);
    expect(ids(p.selected)).toEqual(expect.arrayContaining(["check.sh", "reads-scan", ...FWCORE_USERS]));
    expect(p.remote.sort()).toEqual(FWCORE_USERS.filter((u) => REMOTE.includes(u)).sort());
    expect(p.local).toEqual(expect.arrayContaining(["check.sh", "reads-scan", "packages/difftest", "packages/measure-webkit"]));
    expect([...p.local, ...p.remote].sort()).toEqual(ids(p.selected).sort());
  });
  it("a runner-only change selects the runner and what depends on it; engine-check is remote", () => {
    const p = planFor(root, ["apps/runner/src/checks.ts"], core);
    expect(p.remote).toContain("apps/runner");
    expect(p.remote).toContain("packages/engine-check");
    expect(p.local).toContain("reads-scan");
    expect(p.local).not.toContain("check.sh");
    expect(p.remote).not.toContain("packages/measure-chromium");
  });
  it("a docs-only change selects nothing", () => {
    expect(planFor(root, ["docs/team/handoffs/x.md"], core).selected).toEqual([]);
  });
  it("every candidate check lands in exactly one tier", () => {
    const all = candidateChecks(root).map((c) => c.id);
    const r = core({ op: "console.landTier", ids: all }) as { local: string[]; remote: string[] };
    expect([...r.local, ...r.remote].sort()).toEqual([...all].sort());
    expect(r.local.filter((x) => r.remote.includes(x))).toEqual([]);
    expect(r.remote.sort()).toEqual(REMOTE.filter((x) => all.includes(x)).sort());
  });
});

describe("skippedCount", () => {
  it("reads vitest and node:test summaries", () => {
    expect(skippedCount(" Tests  3 passed | 2 skipped (5)\n")).toBe(2);
    expect(skippedCount("# tests 4\n# pass 3\n# skipped 1\n")).toBe(1);
    expect(skippedCount("# skipped 0\n Tests  9 passed (9)\n")).toBe(0);
    expect(skippedCount(" Tests  3 passed | 2 skipped | 1 todo (6)\n")).toBe(3);
    expect(skippedCount("# tests 4\n# todo 2\n# skipped 1\n")).toBe(3);
    expect(skippedCount("ℹ tests 4\nℹ skipped 0\nℹ todo 1\n")).toBe(1);
    expect(skippedCount("nothing")).toBeNull();
    expect(skippedCount("# skipped 0")).toBeNull();
  });
  const fx = (n: string) => readFileSync(join(dirname(fileURLToPath(import.meta.url)), "fixtures", n), "utf8");
  it("reads the real captured outputs", () => {
    expect(skippedCount(fx("node-spec-ci-39249846030.txt"))).toBe(0); // CI run 39249846030, packages/gate-breakpoints, spec reporter
    expect(skippedCount(fx("node-spec-local.txt"))).toBe(2); // local `node --test` (Node 24) piped to a file, two skipped tests
    expect(skippedCount(fx("vitest-ci-39249846030.txt"))).toBe(1); // same run, apps/console-api, ANSI colours on
  });
  it("a node:test suite that skipped fails the lane for an fwcore user", async () => {
    const lines: string[] = [];
    const c = candidateChecks(root).find((x) => x.id === "packages/gate-breakpoints")!;
    const exit = await runTier([c], root, core, async () => ({ code: 0, out: fx("node-spec-local.txt") }), (s) => lines.push(s));
    expect(exit).toBe(1);
    expect(lines).toContain("VERDICT skipped packages/gate-breakpoints");
    expect(lines.some((l) => l.endsWith("skipped=2"))).toBe(true);
    expect(skippedCount("\u001b[2m      Tests \u001b[22m \u001b[1m\u001b[31m1 failed\u001b[39m\u001b[22m\u001b[2m | \u001b[22m\u001b[1m\u001b[32m360 passed\u001b[39m\u001b[22m\u001b[2m | \u001b[22m\u001b[33m1 skipped\u001b[39m\u001b[90m (362)\u001b[39m")).toBe(1);
  });
});

describe("runTier", () => {
  const mk = (id: string) => candidateChecks(root).find((c) => c.id === id)!;
  const run = (code: number, out: string): Runner => async () => ({ code, out });
  const go = async (id: string, code: number, out: string) => {
    const lines: string[] = [];
    const exit = await runTier([mk(id)], root, core, run(code, out), (s) => lines.push(s));
    return { exit, verdict: lines.find((l) => l.startsWith("VERDICT")) };
  };
  it("pass", async () => expect(await go("apps/runner", 0, "# tests 1\n# skipped 0")).toEqual({ exit: 0, verdict: "VERDICT pass apps/runner" }));
  it("failing exit", async () => expect(await go("apps/runner", 1, "")).toEqual({ exit: 1, verdict: "VERDICT fail apps/runner" }));
  it("a skipped test of an fwcore user fails the lane", async () =>
    expect(await go("packages/gate-breakpoints", 0, "# tests 2\n# skipped 1")).toEqual({ exit: 1, verdict: "VERDICT skipped packages/gate-breakpoints" }));
  it("an unrecognised summary is not a pass", async () =>
    expect(await go("apps/runner", 0, "nothing")).toEqual({ exit: 1, verdict: "VERDICT unknown apps/runner" }));
  it("a skipped test of a suite that does not run fwcore passes", async () =>
    expect(await go("packages/engine-check", 0, "# tests 2\n# skipped 1")).toEqual({ exit: 0, verdict: "VERDICT pass packages/engine-check" }));
});

describe("fw checks", () => {
  it("parses its flags and refuses the rest", () => {
    expect(parseChecksArgs(["--affected", "--base", "HEAD^", "--tier", "remote", "--list"])).toEqual({ base: "HEAD^", tier: "remote", list: true });
    expect(() => parseChecksArgs(["--base", "x"])).toThrow(UsageError);
    expect(() => parseChecksArgs(["--affected"])).toThrow(UsageError);
    expect(() => parseChecksArgs(["--affected", "--base", "x", "--tier", "nope"])).toThrow(UsageError);
  });
  it("--list --tier remote prints only the remote tier", async () => {
    const lines: string[] = [];
    const code = await checksCli(["--affected", "--base", "x", "--tier", "remote", "--list"], root, { core, changed: ["lean/Fw/A.lean"], log: (s) => lines.push(s) });
    expect(code).toBe(0);
    expect(lines.slice(1).sort()).toEqual(REMOTE.filter((r) => FWCORE_USERS.includes(r)).map((r) => `remote ${r}`).sort());
  });
  it("runs the remote tier only and prints one VERDICT per check", async () => {
    const lines: string[] = [];
    const ran: string[][] = [];
    const run: Runner = async (argv) => (ran.push(argv), { code: 0, out: "# tests 1\n# skipped 0" });
    const code = await checksCli(["--affected", "--base", "x", "--tier", "remote"], root, { core, run, changed: ["apps/runner/src/checks.ts"], log: (s) => lines.push(s) });
    expect(code).toBe(0);
    expect(lines.filter((l) => l.startsWith("VERDICT")).sort()).toEqual(["VERDICT pass apps/runner", "VERDICT pass packages/engine-check"]);
    expect(ran.length).toBe(2);
  });
});
