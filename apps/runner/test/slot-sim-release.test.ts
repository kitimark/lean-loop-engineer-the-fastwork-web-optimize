import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { DEFAULT_PARAMS, DEFAULT_WPARAMS, type Mem, type Sample } from "../src/slot-core.ts";
import { type Deps, acquire, releaseToken, slotCli, withState } from "../src/slot.ts";

// A fake simctl: no real Simulator is ever booted or shut down here.
const mem = (freeMB: number): Mem =>
  ({ freeMB, specMB: 0, purgMB: 0, fileMB: 0, fileMinMB: 0, swapUsedMB: 0, swapTotalMB: 0, press: 1, comprMBPerMin: 0, swapOutMBPerMin: 0 });
const quiet = (): Sample => ({ time: Math.floor(Date.now() / 1000), loadCenti: 100, mem: mem(12000), ramMB: 16384, compressorMB: 0, cores: 8 });
const tmps: string[] = [];
afterEach(() => { for (const t of tmps.splice(0)) rmSync(t, { recursive: true, force: true }); });

function fake(booted: string[]) {
  const shut: string[] = [];
  const dir = mkdtempSync(join(tmpdir(), "fw-slot-sr-"));
  tmps.push(dir);
  const out: string[] = [];
  const d: Deps = {
    dir: join(dir, "slot"), cacheDir: join(dir, "cache"), eventsFile: join(dir, "locks.jsonl"), legacySimLock: join(dir, "sim"),
    owner: "wt-a", env: { PATH: process.env.PATH }, params: DEFAULT_PARAMS, wparams: DEFAULT_WPARAMS, history: () => [], pollMs: 1, probe: quiet,
    git: () => ({ tree: "t1", clean: true, mainSha: "m1" }),
    simctl: {
      booted: () => booted.filter((u) => !shut.includes(u.toUpperCase())).map((udid) => ({ udid, name: `dev-${udid}` })),
      shutdown: (u) => { shut.push(u); },
    },
    health: () => ({ time: Math.floor(Date.now() / 1000), live: 3 }),
    out: (s) => { out.push(s); }, err: () => {},
  };
  return { d, out, shut };
}

describe("a released sim lease shuts down the device it booted (fake simctl)", () => {
  it("shuts down only the device booted after the acquire, never one booted before the lease", async () => {
    const booted = ["PRE-1"];
    const { d, out, shut } = fake(booted);
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "900"], d)).toBe(0);
    const token = out.join("").trim();
    expect(withState(d, (st) => st.simBefore)).toEqual(["PRE-1"]);
    booted.push("lease-2");
    expect(await slotCli(["release", "--token", token], d)).toBe(0);
    expect(shut).toEqual(["LEASE-2"]);
    expect(withState(d, (st) => st.simBefore)).toBeUndefined();
  });

  it("a lease that booted nothing shuts nothing down", async () => {
    const { d, out, shut } = fake(["PRE-1", "PRE-2"]);
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "900"], d)).toBe(0);
    expect(await slotCli(["release", "--token", out.join("").trim()], d)).toBe(0);
    expect(shut).toEqual([]);
  });

  it("hands the device to the next queued sim holder; the last release shuts it down", async () => {
    const booted: string[] = [];
    const { d, shut } = fake(booted);
    const first = await acquire(d, "sim", 900, 0);
    booted.push("DEV-A");
    setTimeout(() => { releaseToken(d, first.token); }, 1500);
    const second = await acquire(d, "sim", 900, null);
    expect(second.verdict.verdict).toBe("admit");
    expect(shut).toEqual([]);
    expect(withState(d, (st) => st.simBefore)).toEqual([]);
    releaseToken(d, second.token);
    expect(shut).toEqual(["DEV-A"]);
  });

  it("a release of another kind shuts nothing down", async () => {
    const { d, out, shut } = fake(["X"]);
    expect(await slotCli(["acquire", "--kind", "test", "--wait", "0"], d)).toBe(0);
    expect(await slotCli(["release", "--token", out.join("").trim()], d)).toBe(0);
    expect(shut).toEqual([]);
  });
});
