import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { slowAlerts } from "../src/next.ts";
import { ownOf } from "../src/timing.ts";
import { parseSamples, pathsFor } from "../src/watch-collect.ts";
import { coreCaller, slowWith } from "../src/watch.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");
const haveCore = existsSync(fwcore);
const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

const wait = (startMs: number, durMs: number, phases: Record<string, unknown> | undefined) =>
  ({ tool: "fw", step: "ci wait", startMs, durMs, host: "local", load: 3, exit: 0, ...(phases ? { phases } : {}) });

describe("ownOf: the part of a fw ci wait span that is ours", () => {
  it("is the span end minus the remote run's updatedAt, only for a done wait", () => {
    expect(ownOf(wait(1000, 1377258, { how: "done", updMs: 1000 + 1377258 - 27294 }))).toEqual({ ownMs: 27294 });
    expect(ownOf(wait(1000, 316141, { how: "done", updMs: 1000 + 316141 - 20570 }))).toEqual({ ownMs: 20570 });
  });
  it("is absent without phases, without updMs, for another wait kind, for another step, or when the run ends after the span", () => {
    expect(ownOf(wait(0, 900000, undefined))).toEqual({});
    expect(ownOf(wait(0, 900000, { how: "done" }))).toEqual({});
    expect(ownOf(wait(0, 900000, { how: "timeout", updMs: 5 }))).toEqual({});
    expect(ownOf({ ...wait(0, 900000, { how: "done", updMs: 5 }), step: "ci state" })).toEqual({});
    expect(ownOf(wait(0, 10, { how: "done", updMs: 99 }))).toEqual({});
    expect(ownOf(null)).toEqual({});
  });
  it("parseSamples carries ownMs of a ci wait and of no other span", () => {
    const text = [
      JSON.stringify(wait(10, 1377258, { how: "done", updMs: 10 + 1377258 - 27294 })),
      JSON.stringify({ tool: "fw", step: "other", startMs: 20, durMs: 5, host: "local", load: 1, phases: { how: "done", updMs: 1 } }),
    ].join("\n");
    expect(parseSamples(text)).toEqual([
      { tool: "fw", step: "ci wait", durMs: 1377258, host: "local", load: 3, exit: 0, ownMs: 27294 },
      { tool: "fw", step: "other", durMs: 5, host: "local", load: 1 },
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
    expect(r.details[0]).toMatch(/^sample #\d+ took 51092 ms, against baseline \d+ ms \(p50 of the \d+ earlier samples/);
  });
  it("the same span gets no verdict once the step has keyed spans: the alert closes", async () => {
    const r = await run(landSpans(14));
    expect(r.slow).toEqual([]);
  });
  it("a 23 min fw ci wait is judged by its 27.3 s of our time: no alert; without phases it is not judged", async () => {
    const ws = [[316141, 20570], [440814, 16696], [179419, 26169], [335984, 25290], [387370, 27352], [293198, 12245], [1377258, 27294]]
      .map(([d, o], i) => wait(1_000_000 * (i + 1), d!, { how: "done", updMs: 1_000_000 * (i + 1) + d! - o! }));
    expect((await run(ws)).slow).toEqual([]);
    expect((await run([...ws.slice(0, 6), wait(9_000_000, 1377258, undefined)])).slow).toEqual([]);
  });
  it("a runner queue wait of 36 s is judged as 0 ms of our time: no alert", async () => {
    const q = [0, 0, 37079, 0, 0, 0, 36034].map((d, i) => ({ tool: "fw land", step: "remote queue", startMs: 1000 * (i + 1), durMs: d, host: "local", load: 3, exit: 0 }));
    expect((await run(q)).slow).toEqual([]);
  });
});
