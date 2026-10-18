// ci-shape-obs: the collector turns recorded `gh run view` replies into ledger rows, fetches each finished run once
// (never a cancelled one), and the `ci.shape` alerts are fwcore's `obs.ciShape` (checked against the Lean golden).
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import {
  candidates, collect, finishedOf, lastRuns, readRows, rowsOf, shapeAlerts, shapeFor, timeoutsOf, type GhView, type ShapeReply,
} from "../src/ci-shape.ts";
import { coreCaller } from "../src/watch.ts";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");
const haveCore = existsSync(fwcore);
const core = coreCaller([fwcore]);
const fixture = (id: number) => readFileSync(join(here, "fixtures", "ci-shape", `run-${id}.json`), "utf8");
const golden = readFileSync(join(root, "packages/contracts/golden/obs/obs.ciShape.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });

const dirs: string[] = [];
const tmp = () => { const d = mkdtempSync(join(tmpdir(), "ci-shape-")); dirs.push(d); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

describe("rows of a recorded run view", () => {
  const rows = rowsOf(39101532038, JSON.parse(fixture(39101532038)) as GhView);
  it("one row per started job, epoch seconds, short sha", () => {
    expect(rows).toHaveLength(10);
    const j3 = rows.find((r) => r.job === "gate playwright-webkit j3")!;
    expect(j3.endS - j3.startS).toBe(2986);
    expect(j3).toMatchObject({ workflow: "breakpoint-gate", sha: "b35b541", branch: "ci/integrate-ports-3", attempt: 1 });
    expect(j3.startedS).toBe(j3.createdS);
  });
  it("a job that never started (zero time) has no row", () => {
    const v: GhView = { createdAt: "2026-10-18T00:00:00Z", workflowName: "w",
      jobs: [{ name: "a", conclusion: "skipped", startedAt: "0001-01-01T00:00:00Z", completedAt: "0001-01-01T00:00:00Z" },
        { name: "b", conclusion: "success", startedAt: "2026-10-18T00:00:10Z", completedAt: "2026-10-18T00:01:10Z" }] };
    expect(rowsOf(1, v).map((r) => [r.job, r.endS - r.startS])).toEqual([["b", 60]]);
  });
});

describe("collector", () => {
  it("fetches each finished, non-cancelled run once and appends its rows", async () => {
    const file = join(tmp(), "ci-shape.jsonl");
    const calls: string[][] = [];
    const gh = async (args: string[]) => { calls.push(args); return fixture(Number(args[2])); };
    const runs = [{ id: 39101532038, status: "completed", conclusion: "success" }, { id: 39102911533, status: "completed", conclusion: "failure" },
      { id: 5, status: "completed", conclusion: "cancelled" }, { id: 6, status: "in_progress", conclusion: null }];
    expect(await collect(runs, root, gh, file)).toBe(20);
    expect(calls.map((c) => c[2])).toEqual(["39101532038", "39102911533"]);
    expect(calls[0]!.slice(3)).toEqual(["--json", "createdAt,startedAt,attempt,event,headBranch,headSha,workflowName,conclusion,jobs"]);
    expect(await collect(runs, root, gh, file)).toBe(0); // deduped by run id: no second charged call
    expect(calls).toHaveLength(2);
    expect(readRows(file)).toHaveLength(20);
  });
  it("a budget wait (null reply) writes nothing and is retried next pass; at most `max` views per pass", async () => {
    const file = join(tmp(), "ci-shape.jsonl");
    expect(await collect([{ id: 39101532038, status: "completed", conclusion: "success" }], root, async () => null, file)).toBe(0);
    const ids = [1, 2, 3, 4, 5, 6].map((id) => ({ id, status: "completed", conclusion: "success" }));
    let n = 0;
    await collect(ids, root, async () => { n++; return null; }, file, 4);
    expect(n).toBe(4);
  });
  it("candidates skip seen, cancelled, skipped and unfinished runs", () => {
    expect(candidates([{ id: 1, status: "completed", conclusion: "success" }, { id: 1, status: "completed", conclusion: "success" },
      { id: 2, status: "completed", conclusion: "skipped" }, { id: 3, status: "queued", conclusion: null },
      { id: 4, status: "completed", conclusion: "failure" }], new Set([4]))).toEqual([1]);
  });
  it("finished runs from `fw ci wait` lines", () => {
    expect(finishedOf(["run 12 breakpoint-gate success", "x", "run 13 - cancelled"])).toEqual([
      { id: 12, status: "completed", conclusion: "success" }, { id: 13, status: "completed", conclusion: "cancelled" }]);
  });
  it("timeouts from the workflow files: job id -> timeout-minutes in seconds", () => {
    const t = timeoutsOf(root);
    expect(t).toContainEqual({ workflow: "breakpoint-gate", job: "gate", s: 3600 });
    expect(t).toContainEqual({ workflow: "breakpoint-gate", job: "merge", s: 900 });
    const d = tmp();
    const wf = join(d, ".github", "workflows");
    mkdirSync(wf, { recursive: true });
    writeFileSync(join(wf, "x.yml"), "name: x\non:\n  push:\njobs:\n  a:\n    runs-on: u\n    timeout-minutes: 7\n    steps:\n      - run: y\n        timeout-minutes: 3\n  b:\n    runs-on: u\n");
    expect(timeoutsOf(d)).toEqual([{ workflow: "x", job: "a", s: 420 }]);
  });
  it("lastRuns keeps the newest runs' rows", () => {
    const r = (run: number, createdS: number) => ({ run, workflow: "w", branch: "", sha: "", event: "", attempt: 1, createdS, startedS: createdS, job: "j", conclusion: "success", startS: 0, endS: 1 });
    expect(lastRuns([r(1, 30), r(2, 10), r(3, 20), r(1, 30)], 2).map((x) => x.run)).toEqual([1, 3, 1]);
  });
});

describe.skipIf(!haveCore)("obs.ciShape against the Lean golden", () => {
  it("has the golden cases", () => expect(golden.length).toBeGreaterThanOrEqual(12));
  for (const g of golden) {
    it(g.name, async () => {
      const { op, ...req } = g.request;
      const r = await core({ op, ...req }).catch((e: Error) => ({ error: e.message }));
      if ("error" in g.response) expect(String((r as { error: string }).error)).toContain(String(g.response.error));
      else { const { id: _id, ...reply } = r as Record<string, unknown>; expect(reply).toEqual(g.response); }
    });
  }
  it("the recorded run raises imbalance + nearTimeout and the watch alerts carry the witness", async () => {
    const file = join(tmp(), "ci-shape.jsonl");
    await collect([{ id: 39101532038, status: "completed", conclusion: "success" }], root, async (a) => fixture(Number(a[2])), file);
    const reply = (await shapeFor(file, root, core)) as ShapeReply;
    expect(reply.open.map((a) => a.cls)).toEqual(["imbalance", "nearTimeout"]);
    expect(shapeAlerts(reply)).toEqual([
      { code: "ci.shape", subject: "breakpoint-gate/imbalance", detail: "gate playwright-webkit 2986 vs 1698 (run 39101532038 b35b541 ci/integrate-ports-3)" },
      { code: "ci.shape", subject: "breakpoint-gate/nearTimeout", detail: "gate playwright-webkit j3 2986 vs 3600 (run 39101532038 b35b541 ci/integrate-ports-3)" }]);
  });
  it("no ledger, no alerts", async () => {
    expect(await shapeFor(join(tmp(), "none.jsonl"), root, core)).toBeNull();
    expect(shapeAlerts(null)).toEqual([]);
  });
});
