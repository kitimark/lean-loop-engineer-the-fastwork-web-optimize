import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { GH_BOUNDS } from "@fw/gh-budget";
import type { GhOut } from "../../../packages/gh-budget/src/core.ts";
import { loadState } from "../../../packages/gh-budget/src/state.ts";
import { mkWorld } from "../../../packages/gh-budget/test/util.ts";
import { chargedGh, downloadPieces, fwcoreCall, GhTimedOut, type FwCall, type Gh } from "../src/run.ts";

const hasCore = (() => { try { fwcoreCall(process.cwd()); return true; } catch { return false; } })();
const T0 = 1_800_000_000;

describe.skipIf(!hasCore)("the download pieces of fw run", () => {
  const call: FwCall = hasCore ? fwcoreCall(process.cwd()) : () => ({});
  const dir = () => mkdtempSync(join(tmpdir(), "fw-dl-"));

  it("the lock hold bound of fwcore is the default gh timeout of the budget wrapper", () => {
    expect((call({ op: "store.download", engine: "webkit", runs: 1 }) as { maxHoldMs: number }).maxHoldMs).toBe(GH_BOUNDS.defaultCallTimeoutMs);
  });

  it("a 3-VM original webkit run names its VMs v1..v3 and takes the class directories", async () => {
    const seen: string[][] = [];
    const gh: Gh = async (args) => { seen.push(args); return ""; };
    expect(await downloadPieces({ gh, call, log: () => {} }, "1", dir(), "webkit", "original", 3)).toBe(5);
    expect(seen.map((a) => a[a.indexOf("--pattern") + 1])).toEqual(["webkit-sim-v1", "webkit-sim-v2", "webkit-sim-v3", "webkit-classes", "telemetry-*"]);
  });

  it("a 3-VM webkit run is four calls, one per VM and the telemetry, none of them the build outputs", async () => {
    const seen: { args: string[]; timeoutMs?: number; cost?: number }[] = [];
    const gh: Gh = async (args, o) => { seen.push({ args, ...(o?.timeoutMs !== undefined ? { timeoutMs: o.timeoutMs } : {}), ...(o?.cost !== undefined ? { cost: o.cost } : {}) }); return ""; };
    expect(await downloadPieces({ gh, call, log: () => {} }, "40153925235", dir(), "webkit", "rewrite", 3)).toBe(4);
    expect(seen.map((s) => s.args[s.args.indexOf("--pattern") + 1])).toEqual(["webkit-sim-r1", "webkit-sim-r2", "webkit-sim-r3", "telemetry-*"]);
    expect(seen.map((s) => s.timeoutMs)).toEqual([40000, 40000, 40000, 15200]);
    expect(seen.every((s) => s.cost === 2 && s.args.slice(0, 3).join(" ") === "run download 40153925235")).toBe(true);
    expect(JSON.stringify(seen)).not.toMatch(/fwcore|site-dist|chromium-image/);
  });

  it("a piece that times out is tried once more with the same bound and the retry charge; a second timeout is the caller's", async () => {
    const seen: { p: string; timeoutMs?: number; cost?: number }[] = [];
    const logs: string[] = [];
    let first = true;
    const gh: Gh = async (args, o) => {
      const p = args[args.indexOf("--pattern") + 1]!;
      seen.push({ p, ...(o?.timeoutMs !== undefined ? { timeoutMs: o.timeoutMs } : {}), ...(o?.cost !== undefined ? { cost: o.cost } : {}) });
      if (p === "webkit-sim-r2" && first) { first = false; throw new GhTimedOut("gh run download 1 failed: gh timed out after 40 s and was killed", 1); }
      return "";
    };
    await downloadPieces({ gh, call, log: (l) => logs.push(l) }, "1", dir(), "webkit", "rewrite", 2);
    expect(seen).toEqual([
      { p: "webkit-sim-r1", timeoutMs: 40000, cost: 2 }, { p: "webkit-sim-r2", timeoutMs: 40000, cost: 2 },
      { p: "webkit-sim-r2", timeoutMs: 40000, cost: 1 }, { p: "telemetry-*", timeoutMs: 15200, cost: 2 },
    ]);
    expect(logs.join("\n")).toMatch(/webkit-sim-r2: timed out after 40 s \(1 responses seen\); trying once more, charged 1/);
    let n = 0;
    const always: Gh = async () => { n++; throw new GhTimedOut("timed out", 0); };
    await expect(downloadPieces({ gh: always, call, log: () => {} }, "1", dir(), "webkit", "rewrite", 1)).rejects.toThrow(/timed out/);
    expect(n).toBe(2);
    n = 0;
    const broken: Gh = async () => { n++; throw new Error("gh run download 1 failed: HTTP 404: Not Found"); };
    await expect(downloadPieces({ gh: broken, call, log: () => {} }, "1", dir(), "chromium", "rewrite", 1)).rejects.toThrow(/404/);
    expect(n).toBe(1);
  });

  it("through the budget: a timed-out call is charged once at its reservation, its retry at retryCost", async () => {
    const w = mkWorld(T0, { fastGh: true });
    const outs: GhOut[] = [
      { status: null, stdout: "", stderr: "< HTTP/2.0 200 OK\n< x-ratelimit-remaining: 4990\n< x-ratelimit-resource: core\n< x-ratelimit-reset: 1800003600\n", error: { code: "ETIMEDOUT" } } as GhOut,
      { status: 0, stdout: "", stderr: "< HTTP/2.0 200 OK\n< x-ratelimit-remaining: 4989\n< x-ratelimit-resource: core\n< x-ratelimit-reset: 1800003600\n" },
    ];
    const env = { ...w.env, exec: () => { return outs.shift() ?? { status: 0, stdout: "", stderr: "" }; } };
    const gh = chargedGh(env);
    const charge = () => (loadState(env.dir) as { ledger?: unknown[] } | null)?.ledger ?? [];
    const base = charge().length;
    const err = await gh(["run", "download", "1", "-D", dir(), "--pattern", "webkit-sim-r1"], { timeoutMs: 40000, cost: 2 }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(GhTimedOut);
    expect((err as GhTimedOut).served).toBe(1);
    const afterFirst = charge().length;
    await gh(["run", "download", "1", "-D", dir(), "--pattern", "webkit-sim-r1"], { timeoutMs: 40000, cost: 1 });
    const state = loadState(env.dir) as { ledger: { cost: number; charged: boolean }[] };
    expect(afterFirst - base).toBe(1);
    expect(state.ledger.length - base).toBe(2);
    expect(state.ledger.slice(base).map((e) => [e.cost, e.charged])).toEqual([[2, true], [1, true]]);
  });
});
