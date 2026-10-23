import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { slowAlerts } from "../src/next.ts";
import { rawOf } from "../src/timing.ts";
import { parseSamples, pathsFor } from "../src/watch-collect.ts";
import { coreCaller, slowWith } from "../src/watch.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");
const haveCore = existsSync(fwcore);
const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

const wait = (startMs: number, durMs: number, phases: Record<string, unknown> | undefined) =>
  ({ tool: "fw", step: "ci wait", startMs, durMs, host: "local", load: 3, exit: 0, ...(phases ? { phases } : {}) });

describe("rawOf: the raw facts forwarded to Lean, which decides the own time (Fw.Obs.Timing.ownOfPhases)", () => {
  it("forwards startMs, a hex commit and well-formed phases", () => {
    expect(rawOf({ ...wait(1000, 5, { how: "done", updMs: 7 }), commit: "3d0d68a" })).toEqual({ startMs: 1000, commit: "3d0d68a", phases: { how: "done", updMs: 7 } });
    expect(rawOf(wait(1000, 5, { how: "done", updMs: 7, tickMs: 9, pollS: 10, readMs: 11 })))
      .toEqual({ startMs: 1000, phases: { how: "done", updMs: 7, tickMs: 9, pollS: 10 } });
    expect(rawOf(wait(1000, 5, { how: "done", updMs: 7, tickMs: -1, pollS: "10" }))).toEqual({ startMs: 1000, phases: { how: "done", updMs: 7 } });
  });
  it("drops malformed numbers and phases, so one bad line cannot make fwcore refuse the request", () => {
    expect(rawOf(wait(1.5, 5, { how: "done", updMs: -1 }))).toEqual({});
    expect(rawOf(wait(0, 5, { how: 3, updMs: 7 }))).toEqual({ startMs: 0 });
    expect(rawOf({ commit: "not a sha" })).toEqual({});
    expect(rawOf(null)).toEqual({});
  });
  it("parseSamples forwards the raw facts and decides nothing", () => {
    const text = [
      JSON.stringify(wait(10, 1377258, { how: "done", updMs: 10 + 1377258 - 27294 })),
      JSON.stringify({ tool: "fw", step: "other", startMs: 20, durMs: 5, host: "local", load: 1 }),
    ].join("\n");
    expect(parseSamples(text)).toEqual([
      { tool: "fw", step: "ci wait", durMs: 1377258, host: "local", load: 3, exit: 0, startMs: 10, phases: { how: "done", updMs: 10 + 1377258 - 27294 } },
      { tool: "fw", step: "other", durMs: 5, host: "local", load: 1, startMs: 20 },
    ]);
  });
});

describe("slowAlerts: the detail names the compared sample and baseline", () => {
  it("uses the line of fwcore when there is one, else the generic text", () => {
    const a = slowAlerts(["fw/x", "fw/y"], ["sample #3 took 9 ms, against baseline 1 ms"]);
    expect(a[0]!.detail).toBe("sample #3 took 9 ms, against baseline 1 ms; NEXT investigate step=fw/x");
    expect(a[1]!.detail).toContain("latest sample is slow");
    expect(slowAlerts(["fw/x"])[0]!.detail).toContain("latest sample is slow");
  });
});

const LAND: [number, number | null, number][] = [
  [44947, 24, 3], [26801, null, 4], [26410, null, 4], [30086, null, 3], [26599, 0, 3], [28357, null, 3], [28350, null, 3],
  [26396, null, 2], [26823, null, 3], [26490, null, 2], [28192, null, 5], [37163, 6, 4], [33250, 0, 5], [51092, null, 4],
];
const landSpans = (n: number) => LAND.slice(0, n).map(([d, m, l], i) => ({
  tool: "fw", step: "land dry lake", startMs: 1000 * (i + 1), durMs: d, host: "local", load: l, exit: 0, ...(m === null ? {} : { lake: { built: m } }),
}));

// Golden timing-own.jsonl is Lean `Fw.Obs.Timing.ownCases`: the own time of a `fw ci wait` span net of the poll interval.
describe.skipIf(!haveCore)("the own time of a wait replays the Lean golden through fwcore obs.timing", () => {
  const golden = readFileSync(join(root, "packages/contracts/golden/obs/timing-own.jsonl"), "utf8").trim().split("\n")
    .map((l) => JSON.parse(l) as { name: string; span: Record<string, unknown>; ownMs: number | null });
  const params = { budgetMs: 1, budgets: [], ceilings: [], kDen: 1, kNum: 1, loadMax: 1000, nMin: 1, stages: [] };
  const input = golden.map((g, id) => JSON.stringify({ id, op: "obs.timing", params, samples: parseSamples(JSON.stringify(g.span)) })).join("\n") + "\n";
  const out = spawnSync(fwcore, [], { input, encoding: "utf8", timeout: 120_000, maxBuffer: 64 << 20 }).stdout ?? "";
  const byId = new Map(out.split("\n").filter(Boolean).map((l) => JSON.parse(l) as { id: number; verdicts?: { kind: string; durMs: number }[] })
    .map((r) => [r.id, r] as const));
  it("has the Lean cases", () => expect(golden.length).toBe(8));
  golden.forEach((g, id) => it(g.name, () => {
    const v = byId.get(id)?.verdicts?.filter((x) => x.kind === "sample") ?? [];
    expect(v[0]?.durMs ?? null).toBe(g.ownMs);
  }));
});

describe.skipIf(!haveCore)("obs.slow with detail against fwcore", () => {
  const run = async (spans: object[]) => {
    const dir = mkdtempSync(join(tmpdir(), "fw-own-")); dirs.push(dir);
    writeFileSync(join(dir, "timings.jsonl"), spans.map((s) => JSON.stringify(s)).join("\n") + "\n");
    return slowWith(pathsFor(dir, { FW_CONSOLE_DIR: dir } as NodeJS.ProcessEnv), coreCaller([fwcore]));
  };
  it("the 51.1 s span of ffb7792 without a lake member alerts while the step has no keyed span, with the compared sample in its detail", async () => {
    const unkeyedOnly = landSpans(14).filter((s) => !("lake" in s));
    const r = await run(unkeyedOnly);
    expect(r.slow).toEqual(["fw/land dry lake"]);
    expect(r.details[0]).toMatch(/^local sample \(startMs \d+, commit [0-9a-f]*\) took 51092 ms, against baseline \d+ ms \(p50 of the \d+ earlier samples/);
  });
  it("the same span gets no verdict once the step has keyed spans: the alert closes", async () => {
    const r = await run(landSpans(14));
    expect(r.slow).toEqual([]);
  });
  it("a 23 min fw ci wait is judged by its 27.3 s of our time: no alert; without phases it is not judged", async () => {
    const ws = [[316141, 20570], [440814, 16696], [179419, 26169], [335984, 25290], [387370, 27352], [293198, 12245], [1377258, 27294]]
      .map(([d, o], i) => { const u = 1_000_000 * (i + 1) + d! - o!; return wait(1_000_000 * (i + 1), d!, { how: "done", updMs: u, tickMs: u, pollS: 10 }); });
    expect((await run(ws)).slow).toEqual([]);
    expect((await run([...ws.slice(0, 6), wait(9_000_000, 1377258, undefined)])).slow).toEqual([]);
    expect((await run([...ws.slice(0, 6), wait(9_000_000, 1377258, { how: "timeout", updMs: 9_000_000 })])).slow).toEqual([]);
  });
  it("a runner queue wait of 36 s is judged as 0 ms of our time: no alert", async () => {
    const q = [0, 0, 37079, 0, 0, 0, 36034].map((d, i) => ({ tool: "fw land", step: "remote queue", startMs: 1000 * (i + 1), durMs: d, host: "local", load: 3, exit: 0 }));
    expect((await run(q)).slow).toEqual([]);
  });
});
