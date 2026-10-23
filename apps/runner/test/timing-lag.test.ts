// task ci-wait-lag: the wait span carries its phases, the lag splits into components that add up, `fw timings --lag` reads them.
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { WaitPhases } from "@fw/gh-budget";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { begin, parseTimings, seenRuns, type Span } from "../src/timing.ts";
import { lagParts, lagView, waitSpanExtra } from "../src/timing-ci.ts";
import { parseSamples } from "../src/watch-collect.ts";

let dir: string, file: string;
beforeEach(() => { dir = mkdtempSync(join(tmpdir(), "fw-lag-")); file = join(dir, "timings.jsonl"); process.env.FW_TIMINGS_FILE = file; });
afterEach(() => { delete process.env.FW_TIMINGS_FILE; rmSync(dir, { recursive: true, force: true }); });
const lines = () => readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as Span);

const ph = (o: Partial<WaitPhases> = {}): WaitPhases => ({
  how: "done", holder: false, regMs: 1_000, runIds: [900], updMs: 10_000, prevTickMs: 9_000, tickMs: 40_000, readMs: 41_000,
  viewEndMs: 43_000, doneMs: 43_500, retMs: 44_000, views: 1, cached: 0, lockMs: 200, ghMs: 900, loops: 12, ...o,
});
const noPoll = () => undefined;
const span = (p: WaitPhases, extra: [number, number] = [44_100, 46_000], load = 5): Span => ({
  tool: "fw", step: "ci wait", startMs: 1_000, durMs: 47_000 - 1_000, exit: 0, host: "local", load, commit: "abc1234", ...waitSpanExtra(p, extra[0], extra[1], noPoll),
} as Span);

describe("wait span extras", () => {
  it("begin(...)(exit, extra) writes runIds and phases on the one line", () => {
    begin("fw", "ci wait")(0, waitSpanExtra(ph(), 44_100, 46_000, noPoll));
    const [s] = lines();
    expect(s!.runIds).toEqual([900]);
    expect(s!.phases).toMatchObject({ how: "done", tickMs: 40_000, ingestStartMs: 44_100, ingestEndMs: 46_000 });
    expect(JSON.stringify(s)).not.toMatch(/"runId":/);
  });
  it("a wait span with runIds is not a CI-run span: seenRuns ignores it and parseSamples still reads it", () => {
    begin("fw", "ci wait")(0, waitSpanExtra(ph(), 44_100, 46_000, noPoll));
    expect(seenRuns(file).size).toBe(0);
    expect(parseSamples(readFileSync(file, "utf8")).length).toBeGreaterThanOrEqual(0);
  });
  it("no phases: no extra fields", () => { expect(waitSpanExtra(null, 1, 2, noPoll)).toEqual({}); });
  it("undefined phase fields are dropped", () => {
    const e = waitSpanExtra(ph({ prevTickMs: undefined }), 1, 2, noPoll);
    expect(Object.keys(e.phases!)).not.toContain("prevTickMs");
  });
  it("a done wait carries the poll interval; other waits do not ask for it", () => {
    expect(waitSpanExtra(ph(), 1, 2, () => 10).phases).toMatchObject({ how: "done", pollS: 10 });
    expect(Object.keys(waitSpanExtra(ph(), 1, 2, noPoll).phases!)).not.toContain("pollS");
    let asked = 0;
    const e = waitSpanExtra(ph({ how: "timeout" }), 1, 2, () => { asked++; return 10; });
    expect(asked).toBe(0);
    expect(Object.keys(e.phases!)).not.toContain("pollS");
  });
});

describe("lag components", () => {
  it("add up to the total, which is the span end minus the run's updatedAt", () => {
    const s = span(ph());
    const p = lagParts(s)!;
    expect(p).toMatchObject({ list: 30_000, pickup: 1_000, view: 2_000, verdict: 500, cleanup: 500, ingest: 1_900, exit: 1_100, total: 37_000, stale: 0, gap: 31_000 });
    expect(p.list + p.pickup + p.view + p.verdict + p.cleanup + p.ingest + p.exit).toBe(p.total);
  });
  it("the partition holds for any ordered times", () => {
    for (let i = 0; i < 50; i++) {
      const t = Array.from({ length: 8 }, () => Math.floor(Math.random() * 1000)).reduce<number[]>((a, d) => [...a, (a[a.length - 1] ?? 0) + d], []);
      const [upd, tick, read, viewEnd, done, ret, i0, i1] = t as [number, number, number, number, number, number, number, number];
      const s = { startMs: 0, durMs: i1 + 5, phases: { how: "done", updMs: upd, tickMs: tick, readMs: read, viewEndMs: viewEnd, doneMs: done, retMs: ret, ingestStartMs: i0, ingestEndMs: i1 } };
      const p = lagParts(s)!;
      expect(p.list + p.pickup + p.view + p.verdict + p.cleanup + p.ingest + p.exit).toBe(p.total);
    }
  });
  it("is null for a wait that is not `done` or lacks a time", () => {
    expect(lagParts(span(ph({ how: "timeout" })))).toBeNull();
    expect(lagParts(span(ph({ how: "grace" })))).toBeNull();
    expect(lagParts(span(ph({ viewEndMs: undefined })))).toBeNull();
  });
  it("staleness is the time past updatedAt that the previous list still showed the run unfinished", () => {
    expect(lagParts(span(ph({ prevTickMs: 12_000 })))!.stale).toBe(2_000);
    expect(lagParts(span(ph({ prevTickMs: undefined })))!.stale).toBeNull();
  });
});

describe("fw timings --lag", () => {
  it("parses the flag", () => { expect(parseTimings(["--lag"]).lag).toBe(true); expect(parseTimings([]).lag).toBeFalsy(); });
  it("says so when no span has phases", () => { expect(lagView("")).toMatch(/no `fw ci wait` spans with phases/); });
  it("prints a row per component with shares that cover the total, the gap and the load buckets", () => {
    const text = [span(ph(), undefined, 5), span(ph({ tickMs: 70_000, readMs: 71_000, viewEndMs: 73_000, doneMs: 73_500, retMs: 74_000 }), [74_100, 76_000], 130), span(ph({ how: "timeout" }))]
      .map((s) => JSON.stringify(s)).join("\n");
    const out = lagView(text);
    expect(out).toMatch(/waits with phases: 3 \(done 2, timeout 1\)/);
    for (const c of ["list", "pickup", "view", "verdict", "cleanup", "ingest", "exit", "total"]) expect(out).toMatch(new RegExp(`^${c} `, "m"));
    expect(out).toMatch(/tick gap around the finish: n 2/);
    expect(out).toMatch(/load 0-20: n 1/);
    expect(out).toMatch(/load 120-up: n 1/);
  });
});

// The partition of the lag is Lean's (`Fw.Ci.Lag.parts`, golden ci-budget/lag.jsonl): lagParts only subtracts the recorded marks the same way.
describe("lag partition replays the Lean golden", () => {
  const golden = readFileSync(join(__dirname, "..", "..", "..", "packages", "contracts", "golden", "ci-budget", "lag.jsonl"), "utf8").split("\n").filter(Boolean)
    .map((l) => JSON.parse(l) as { name: string; marks: Record<string, number>; prev?: number; parts: Record<string, number>; gap?: number; stale?: number });
  it("has the Lean cases", () => expect(golden.length).toBe(4));
  for (const g of golden) {
    it(g.name, () => {
      const m = g.marks;
      const p = lagParts({ startMs: 0, durMs: m.end!, phases: { how: "done", holder: false, regMs: 0, runIds: [1], updMs: m.upd, tickMs: m.tick, readMs: m.read, viewEndMs: m.viewEnd, doneMs: m.done,
        retMs: m.ret, ingestStartMs: m.i0, ingestEndMs: m.i1, ...(g.prev === undefined ? {} : { prevTickMs: g.prev }) } as unknown as Span["phases"] })!;
      expect(p).toMatchObject({ ...g.parts, stale: g.stale ?? null, gap: g.gap ?? null });
    });
  }
});
