import { describe, expect, it } from "vitest";
import type { Target } from "@fw/gh-budget";
import { join } from "node:path";
import { downloadPieces, fwcoreCall, parseRunArgs, runMain, type FwCall, type Gh, type RouteDeps } from "../src/run.ts";

const SHA = "0123456789abcdef0123456789abcdef01234567";
const job = { engine: "webkit", workflow: "webkit-sim.yml", inputs: { vms: "3", sessions: "1", target: "original" }, key: [["runs", "3"]], image: "xcode-27", blocked: null, cache: "miss", digest: "d".repeat(64) };
const plan: FwCall = () => ({ fw: [], jobs: [job], problems: [] });

describe("runMain with the pool route", () => {
  const drive = async (argv: string[], route: RouteDeps | undefined) => {
    const ghCalls: string[][] = [];
    const gh: Gh = async (a) => { ghCalls.push(a); if (a[1] === "view") throw new Error("stop after dispatch"); return ""; };
    const d = { nonce: () => "n0nce1234", now: () => 1_800_000_000, wait: async (_t: Target) => ({ code: 0 as const, lines: ["run 55 webkit-sim success"] }),
      call: plan, gh, store: "/nonexistent-store", sha: SHA, branch: "ci/x", tmp: "", log: () => {}, ...(route ? { route } : {}) };
    await expect(runMain(parseRunArgs(argv), d)).rejects.toThrow(/stop after dispatch/);
    return ghCalls.find((a) => a[0] === "workflow")!;
  };
  const argv = ["--engines", "webkit", "--target", "original", "--ref", "ci/x", "--sha", SHA];

  it("dispatches only the cells the route keeps on GitHub, and waits for the Codemagic cells", async () => {
    let settled = false;
    const route: RouteDeps = { split: async (j) => { expect(j.inputs.vms).toBe("3"); return { github: 2, cm: Promise.resolve([]).then(() => { settled = true; return []; }) }; }, place: async () => {} };
    const dispatched = await drive(argv, route);
    expect(dispatched).toContain("vms=2");
    expect(settled).toBe(true);
  });
  it("--no-route and a missing route dispatch every cell", async () => {
    const route: RouteDeps = { split: async () => { throw new Error("must not route"); }, place: async () => {} };
    expect(await drive([...argv, "--no-route"], route)).toContain("vms=3");
    expect(await drive(argv, undefined)).toContain("vms=3");
  });
  it("a Codemagic failure fails the run", async () => {
    const route: RouteDeps = { split: async () => ({ github: 2, cm: Promise.reject(new Error("Codemagic build failed")) }), place: async () => {} };
    const ghCalls: string[][] = [];
    const gh: Gh = async (a) => { ghCalls.push(a); return ""; };
    const d = { nonce: () => "n", now: () => 1_800_000_000, wait: async (_t: Target) => ({ code: 0 as const, lines: ["run 55 x"] }), call: plan, gh, store: "/nonexistent-store", sha: SHA, branch: "ci/x", tmp: "", log: () => {}, route };
    await expect(runMain(parseRunArgs(argv), d)).rejects.toThrow(/Codemagic build failed/);
  });
});

describe("downloadPieces with a local merge", () => {
  it("skips the GitHub webkit-classes piece, which would miss the Codemagic VMs", async () => {
    const got: string[] = [];
    const gh: Gh = async (a) => { got.push(a[a.indexOf("--pattern") + 1]!); return ""; };
    const call = fwcoreCall(join(process.cwd(), "..", ".."));
    await downloadPieces({ gh, call, log: () => {} }, "9", "/d", "webkit", "original", 1, true);
    expect(got).toEqual(["webkit-sim-v1", "telemetry-*"]);
    got.length = 0;
    await downloadPieces({ gh, call, log: () => {} }, "9", "/d", "webkit", "original", 1);
    expect(got).toEqual(["webkit-sim-v1", "webkit-classes", "telemetry-*"]);
  });
});
