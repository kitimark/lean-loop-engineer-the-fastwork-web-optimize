import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { DEFAULT_PARAMS, DEFAULT_WPARAMS, type Sample } from "../src/slot-core.ts";
import { type Deps, acquire, releaseToken } from "../src/slot.ts";
import { simSlotFacts } from "../src/reap.ts";

const tmps: string[] = [];
afterEach(() => { for (const t of tmps.splice(0)) rmSync(t, { recursive: true, force: true }); });

const quiet = (): Sample => ({
  time: Math.floor(Date.now() / 1000), loadCenti: 100, ramMB: 16384, compressorMB: 0, cores: 8,
  mem: { freeMB: 12000, specMB: 0, purgMB: 0, fileMB: 0, fileMinMB: 0, swapUsedMB: 0, swapTotalMB: 0, press: 1, comprMBPerMin: 0, swapOutMBPerMin: 0 },
});

function deps(booted: () => { udid: string; name: string }[]): Deps {
  const dir = mkdtempSync(join(tmpdir(), "reap-slot-"));
  tmps.push(dir);
  return {
    dir: join(dir, "slot"), cacheDir: join(dir, "cache"), eventsFile: join(dir, "locks.jsonl"), legacySimLock: join(dir, "sim"),
    owner: "wt-a", env: { PATH: process.env.PATH }, params: DEFAULT_PARAMS, wparams: DEFAULT_WPARAMS, history: () => [], pollMs: 1, probe: quiet,
    git: () => ({ tree: "t1", clean: true, mainSha: "m1" }),
    simctl: { booted, shutdown: () => { throw new Error("no shutdown in a test"); } },
    health: () => ({ time: Math.floor(Date.now() / 1000), live: 3 }),
    out: () => {}, err: () => {},
  };
}

describe("a sim slot release records the booted udids", () => {
  it("state.json keeps the upper-case udids of the devices booted since the acquire (a device booted before it is not the run's); fw reap reads them (no name prefix)", async () => {
    let up = false;
    const d = deps(() => (up ? [{ udid: "aaaa-1", name: "iPhone 17e" }, { udid: "bbbb-2", name: "other" }, { udid: "cccc-3", name: "was up" }] : [{ udid: "cccc-3", name: "was up" }]));
    const g = await acquire(d, "sim", 900, null);
    expect(g).not.toBeNull();
    up = true;
    expect(releaseToken(d, g!.token)).toBe(true);
    const st = JSON.parse(readFileSync(join(d.dir, "state.json"), "utf8")) as { simUdids?: string[]; simAcquired?: number };
    expect(st.simUdids).toEqual(["AAAA-1", "BBBB-2"]);
    expect(simSlotFacts(d.dir, Math.floor(Date.now() / 1000)).simUdids).toEqual(["AAAA-1", "BBBB-2"]);
  });
  it("a failing simctl records no udid and the release still works", async () => {
    let calls = 0;
    const d = deps(() => { if (calls++ < 2) return []; throw new Error("simctl down"); });
    const g = await acquire(d, "sim", 900, null);
    expect(releaseToken(d, g!.token)).toBe(true);
    expect((JSON.parse(readFileSync(join(d.dir, "state.json"), "utf8")) as { simUdids?: string[] }).simUdids).toEqual([]);
  });
});
