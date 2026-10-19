import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { begin, ciSpans, inputsKind, kindsFile, kindsOf, parseTimings, quantile, recordCiRun, recordRunKind, renderRows, span, summarize, whereIs } from "../src/timing.ts";
import { backfill, ingestRuns, runIdsOf } from "../src/timing-ci.ts";
import { parseSamples } from "../src/watch-collect.ts";

let dir: string, file: string;
beforeEach(() => { dir = mkdtempSync(join(tmpdir(), "fw-timing-")); file = join(dir, "sub", "timings.jsonl"); process.env.FW_TIMINGS_FILE = file; });
afterEach(() => { delete process.env.FW_TIMINGS_FILE; rmSync(dir, { recursive: true, force: true }); });
const lines = () => readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));

describe("span writer", () => {
  it("appends one schema-exact line per span, sync and async, with the exit code", async () => {
    expect(span("fw", "plan sync", () => 7, (r) => r)).toBe(7);
    await span("fw", "land", async () => 2, (r) => r);
    const l = lines();
    expect(l.map((s) => [s.tool, s.step, s.exit])).toEqual([["fw", "plan sync", 7], ["fw", "land", 2]]);
    expect(Object.keys(l[0]).sort()).toEqual(["commit", "durMs", "exit", "host", "load", "startMs", "step", "tool"]);
    expect(typeof l[0].load).toBe("number");
    expect(l[0].commit).toMatch(/^[0-9a-f]{7}$/);
  });
  it("records exit 1 and rethrows when the step throws", async () => {
    expect(() => span("fw", "x", () => { throw new Error("boom"); })).toThrow("boom");
    await expect(span("fw", "y", async () => { throw new Error("late"); })).rejects.toThrow("late");
    expect(lines().map((s) => s.exit)).toEqual([1, 1]);
  });
  it("never fails the step when the file cannot be written", () => {
    process.env.FW_TIMINGS_FILE = join(dir, "no", "such", "\0bad");
    expect(span("fw", "z", () => "ok")).toBe("ok");
  });
  it("begin/end records once", () => { const end = begin("fw", "once"); end(0); end(3); expect(lines()).toHaveLength(1); });
  it("holds no path or user name", () => { span("fw", "land", () => 0); expect(readFileSync(file, "utf8")).not.toMatch(/\/Users|\/home|@/); });
  it("reads HEAD of this repo without spawning git", () => {
    const w = whereIs(process.cwd())!;
    expect(execFileSync("git", ["rev-parse", "HEAD"], { cwd: process.cwd(), encoding: "utf8" }).startsWith(w.sha)).toBe(true);
  });
});

describe("CI spans", () => {
  const run = { workflowName: "breakpoint-gate", headSha: "abcdef0123456789", jobs: [
    { name: "shard 1", startedAt: "2026-10-18T00:00:00Z", completedAt: "2026-10-18T00:02:00Z", conclusion: "success",
      steps: [{ name: "Run gate", startedAt: "2026-10-18T00:00:10Z", completedAt: "2026-10-18T00:01:50Z", conclusion: "failure" },
              { name: "never ran", startedAt: "0001-01-01T00:00:00Z", completedAt: "0001-01-01T00:00:00Z", conclusion: "skipped" }] }] };
  it("one span per job and per step, host ci, skipping steps that never ran", () => {
    const s = ciSpans(42, run);
    expect(s.map((x) => [x.tool, x.step, x.durMs, x.exit, x.host, x.runId, x.commit])).toEqual([
      ["breakpoint-gate", "shard 1", 120000, 0, "ci", 42, "abcdef0"], ["breakpoint-gate", "shard 1/Run gate", 100000, 1, "ci", 42, "abcdef0"]]);
  });
  it("dedupes by run id: the second call neither fetches nor writes", async () => {
    let calls = 0;
    const gh = async () => { calls++; return JSON.stringify(run); };
    expect(await ingestRuns([42, 43], process.cwd(), gh)).toBe(4);
    expect(await ingestRuns([42, 43], process.cwd(), gh)).toBe(0);
    expect(calls).toBe(2);
    expect(recordCiRun(42, run)).toBe(0);
  });
  it("the run kind round-trips: fw run records the inputs digest, the CI spans of that run carry it, parseSamples reads it as runKind", () => {
    const a = { profile: "swipe-v1", runs: "3", target: "both" }, b = { ...a, runs: "1" };
    expect(inputsKind(a)).toBe(inputsKind({ target: "both", runs: "3", profile: "swipe-v1" })); // key order is not part of the kind
    expect(inputsKind(a)).not.toBe(inputsKind(b));
    expect(recordRunKind(42, a)).toBe(inputsKind(a));
    expect(recordRunKind(43, b)).toBe(inputsKind(b));
    expect(kindsOf(kindsFile(file)).get(42)).toBe(inputsKind(a));
    expect(recordCiRun(42, run)).toBe(2);
    expect(recordCiRun(43, run)).toBe(2);
    expect(recordCiRun(44, run)).toBe(2); // not dispatched by fw run: no kind line
    const ls = lines();
    expect(ls.filter((l) => l.runId === 42).every((l) => l.kind === inputsKind(a))).toBe(true);
    expect(ls.filter((l) => l.runId === 44).every((l) => !("kind" in l))).toBe(true);
    const samples = parseSamples(readFileSync(file, "utf8"));
    expect(new Set(samples.map((s) => s.runKind ?? ""))).toEqual(new Set([inputsKind(a), inputsKind(b), ""]));
  });
  it("reads run ids from `fw ci wait` output", () => { expect(runIdsOf(["run 7 lean success", "wait: x", "run 9 - failure"])).toEqual([7, 9]); });
  it("backfill takes the named runs plus up to --per completed runs per workflow", async () => {
    const gh = async (a: string[]) => a[1] === "list"
      ? JSON.stringify([1, 2, 3, 4].map((i) => ({ databaseId: i, workflowName: "w", status: "completed" })).concat([{ databaseId: 9, workflowName: "w", status: "in_progress" }]))
      : JSON.stringify({ ...run, jobs: [run.jobs[0]], workflowName: "w" });
    const msg = await backfill(["--backfill", "50", "--per", "2"], process.cwd(), gh);
    expect(msg).toBe("backfill: 3 runs considered, 6 span lines written");
  });
});

describe("view", () => {
  const mk = (tool: string, step: string, durMs: number, startMs = 1) => JSON.stringify({ tool, step, startMs, durMs, exit: 0, commit: "", load: 0, host: "local" });
  it("quantiles are nearest-rank", () => { expect(quantile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.5)).toBe(5); expect(quantile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.9)).toBe(9); expect(quantile([], 0.5)).toBe(0); });
  it("groups per (tool, step), sorts by p90 descending, filters tool and since, skips junk", () => {
    const ls = [mk("a", "s", 100, 1), mk("a", "s", 300, 5), mk("a", "s", 200, 3), mk("b", "t", 5000, 4), "not json", "{}"];
    const rows = summarize(ls);
    expect(rows.map((r) => [r.tool, r.step, r.n, r.p50, r.p90, r.last, r.max])).toEqual([["b", "t", 1, 5000, 5000, 5000, 5000], ["a", "s", 3, 200, 300, 300, 300]]);
    expect(summarize(ls, { tool: "a" })).toHaveLength(1);
    expect(summarize(ls, { sinceMs: 4 }).map((r) => r.n)).toEqual([1, 1]);
    expect(renderRows(rows).split("\n")[0]).toMatch(/^tool\s+step\s+n\s+p50\s+p90\s+last\s+max$/);
  });
  it("parses flags", () => { expect(parseTimings(["--tool", "fw", "--since", "2"])).toMatchObject({ tool: "fw", sinceH: 2 }); expect(() => parseTimings(["--wat"])).toThrow(); });
});

describe("scripts/span.sh", () => {
  it("returns the command status and appends one line", () => {
    const sh = join(process.cwd(), "../../scripts/span.sh");
    writeFileSync(join(dir, "t.sh"), `. "${sh}"\nspan t "ok step" true\nspan t "bad step" false || echo rc=$?\n`);
    const out = execFileSync("sh", [join(dir, "t.sh")], { encoding: "utf8", env: { ...process.env, FW_TIMINGS_FILE: file } });
    expect(out).toContain("rc=1");
    expect(lines().map((s) => [s.tool, s.step, s.exit])).toEqual([["t", "ok step", 0], ["t", "bad step", 1]]);
  });
});
