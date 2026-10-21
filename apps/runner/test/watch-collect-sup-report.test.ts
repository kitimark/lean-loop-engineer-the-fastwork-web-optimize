// The note generator of the resource baseline (apps/runner/src/sup-report.ts, task sup-baseline): the reducers on fixed
// samples and lock events, and the rendered note's shape (generated header, tables, no paths).
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { dedupe, maxConcurrent, pairHolds, parseJsonl, pct, reduce, render, reportMain, type LockEv } from "../src/sup-report.ts";
import { buildSample, PROC_KINDS, type SupSample } from "../src/watch-collect.ts";

const dirs: string[] = [];
const tmp = () => { const d = mkdtempSync(join(tmpdir(), "fw-supr-")); dirs.push(d); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

const T0 = Date.UTC(2026, 9, 21, 12, 0, 0);
const sample = (ts: number, over: Partial<Record<(typeof PROC_KINDS)[number], [number, number, number]>> = {}, extra: Partial<SupSample> = {}): SupSample => {
  const kinds = Object.fromEntries(PROC_KINDS.map((k) => [k, { n: over[k]?.[0] ?? 0, memMB: over[k]?.[1] ?? 0, cmprsMB: over[k]?.[2] ?? 0 }])) as SupSample["kinds"];
  return { ts, verdict: "quiet", loadCenti: 50, ramMB: 16384, swapUsedMB: 1000, swapTotalMB: 6144, compressorMB: 2000, freePct: 60, kinds, costMs: 1000, partial: [], ...extra };
};
const ev = (ts: number, lock: string, e: string, kind: string, pid: number, extra: Partial<LockEv> = {}): LockEv => ({ ts, lock, ev: e, kind, pid, start: 1, ...extra });

describe("reducers", () => {
  it("pct is the nearest rank", () => {
    expect(pct([], 0.5)).toBe(0);
    expect(pct([5], 0.9)).toBe(5);
    expect(pct([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.5)).toBe(5);
    expect(pct([10, 9, 8, 7, 6, 5, 4, 3, 2, 1], 0.9)).toBe(9);
  });
  it("dedupe drops a sample within 10 s of the previous kept one", () => {
    const d = dedupe([sample(T0 + 20_000), sample(T0), sample(T0 + 3_000), sample(T0 + 40_000)]);
    expect(d.kept.map((s) => s.ts - T0)).toEqual([0, 20_000, 40_000]);
    expect(d.dropped).toBe(1);
  });
  it("pairHolds pairs a release with its acquire by lock, pid and start; an unmatched one is open or an orphan", () => {
    const { holds, orphans } = pairHolds([ev(1000, "heavy", "acquire", "k", 5), ev(1500, "heavy", "acquire", "k", 6), ev(2000, "heavy", "release", "k", 5),
      ev(2500, "heavy", "release", "k", 99), ev(3000, "sim", "acquire", "sim", 5)]);
    expect(holds.map((h) => [h.lock, h.pid, h.from, h.to])).toEqual([["heavy", 5, 1000, 2000], ["heavy", 6, 1500, null], ["sim", 5, 3000, null]]);
    expect(orphans).toBe(1);
  });
  it("maxConcurrent counts overlapping holds, a release at the same instant first", () => {
    const h = (from: number, to: number | null) => ({ lock: "l", kind: "k", pid: 1, start: 1, from, to });
    expect(maxConcurrent([h(0, 10), h(5, 15), h(10, 20)], 30)).toBe(2);
    expect(maxConcurrent([h(0, 10), h(10, 20)], 30)).toBe(1);
    expect(maxConcurrent([h(0, null), h(5, null)], 30)).toBe(2);
    expect(maxConcurrent([], 0)).toBe(0);
  });
  it("reduce: verdict counts, per-kind percentiles, the machine rows and the simulator hours", () => {
    const samples = [
      sample(T0, { lean: [2, 4000, 500], node: [3, 600, 100] }, { verdict: "busy" }),
      sample(T0 + 20_000, { simulator: [4, 2048, 100] }, { verdict: "busy" }),
      sample(T0 + 40_000, { simulator: [4, 2048, 100] }, { verdict: "busy" }),
      sample(T0 + 60_000, {}, { verdict: null, partial: ["swap"], swapUsedMB: null, swapTotalMB: null }),
      sample(T0 + 80_000, {}, { verdict: "pressured", freePct: 10 })];
    const evs = [ev(T0 + 10_000, "sim", "acquire", "sim", 7, { waitMs: 0 }), ev(T0 + 30_000, "sim", "release", "sim", 7, { holdMs: 20_000 })];
    const r = reduce(samples, evs);
    expect(r.verdicts).toEqual({ quiet: 0, busy: 3, pressured: 1, unknown: 1 });
    expect(r.partial).toBe(1);
    expect(r.kinds.lean.memMB.max).toBe(4000);
    expect(r.kinds.lean.present).toBe(1);
    expect(r.kinds.node.n.max).toBe(3);
    expect(r.sys.freePct.p50).toBe(60);
    expect(r.sys.swapUsedMB.max).toBe(1000);
    // simulator samples at +20 s (held) and +40 s (not held): 2 GB for 20 s each
    expect(r.sim.samples).toBe(2);
    expect(r.sim.idleSamples).toBe(1);
    expect(r.sim.gbHours).toBeCloseTo((2 * 2 * 20) / 3600, 6);
    expect(r.sim.idleGbHours).toBeCloseTo((2 * 20) / 3600, 6);
    expect(r.locks).toMatchObject([{ lock: "sim", kind: "sim", acquires: 1, refuses: 0, open: 0, maxConc: 1, hold: { p50: 20_000 } }]);
  });
  it("reduce on no data is all zeros", () => {
    const r = reduce([], []);
    expect(r.samples).toBe(0);
    expect(r.locks).toEqual([]);
    expect(render(r)).toContain("No lock event was logged");
  });
});

describe("render", () => {
  const r = reduce([sample(T0), sample(T0 + 20_000, { chromium: [5, 900, 10] }, { verdict: "busy" })], [ev(T0, "heavy", "acquire", "check", 3, { waitMs: 1200 }), ev(T0 + 5000, "heavy", "release", "check", 3, { holdMs: 5000 })]);
  const md = render(r);
  it("has the status line with the date, the first-day and continuing-collection statements, and the tables", () => {
    expect(md).toMatch(/^# Resource baseline of the dev Mac, first-day tables/);
    expect(md).toContain("Status: MEASURED 2026-10-21");
    expect(md).toContain("The 3-day collection continues");
    expect(md).toContain("shared between processes");
    for (const h of ["## Samples", "## Verdict share", "## Footprint per kind", "## Machine", "## Simulator", "## Locks", "## Limits"]) expect(md).toContain(h);
    expect(md).toMatch(/\| heavy \| check \| 1 \| 0 \| 0 \| 1 \| 1200 /);
  });
  it("says so when the summed footprint exceeds RAM (the double counting), and not otherwise", () => {
    expect(md).not.toContain("shows the double counting");
    const big = render(reduce([sample(T0, { other: [500, 20_000, 0] })], []));
    expect(big).toContain("exceeds the 16.0 GB of RAM, which shows the double counting");
  });
  it("states the span, warns when it is under 6 h, and not otherwise", () => {
    expect(md).toContain("(a span of 0.3 min)");
    expect(md).toContain("The window is 0.3 min, under 6 h");
    const long = render(reduce([sample(T0), sample(T0 + 7 * 3_600_000)], []));
    expect(long).toContain("(a span of 420 min)");
    expect(long).not.toContain("under 6 h");
  });
  it("carries no home path, email or LAN address", () => {
    expect(md).not.toMatch(/\/Users\/|\/home\/|@[a-z]+\.|\b192\.168\.|\b10\.\d+\.\d+\.\d+\b/);
  });
});

describe("reportMain", () => {
  it("reads the two jsonl files, writes the note, and --check compares", () => {
    const d = tmp(); const out = join(d, "note.md");
    writeFileSync(join(d, "sup-samples.jsonl"), `${JSON.stringify(sample(T0))}\nnot json\n${JSON.stringify(buildSample(T0 + 20_000, { top: null, ps: null, swap: null, free: null }, 1, 16384, 5))}\n`);
    writeFileSync(join(d, "locks.jsonl"), `${JSON.stringify(ev(T0, "lake-slot", "acquire", "build", 3, { slot: 0, waitMs: 0 }))}\n`);
    expect(reportMain(["--dir", d, "--out", out])).toBe(0);
    expect(existsSync(out)).toBe(true);
    expect(readFileSync(out, "utf8")).toContain("| lake-slot | build | 1 |");
    expect(reportMain(["--dir", d, "--out", out, "--check"])).toBe(0);
    writeFileSync(out, "edited");
    expect(reportMain(["--dir", d, "--out", out, "--check"])).toBe(1);
    expect(reportMain(["--dir", d])).toBe(2);
  });
  it("parseJsonl skips half-written and foreign lines", () => {
    const isN = (o: unknown): o is { a: number } => typeof o === "object" && o !== null && typeof (o as { a: unknown }).a === "number";
    expect(parseJsonl('{"a":1}\n{"a":\n{"b":2}\n{"a":3}', isN)).toEqual([{ a: 1 }, { a: 3 }]);
  });
});
