import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { awaitRemote, circleciAdapter, githubAdapter, remoteDigest, type GhRunView, type GithubDeps, type Want } from "../src/land-remote.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const SHA = "a".repeat(40);
const MARKER = "b".repeat(40);
const CHECKS = ["apps/runner", "packages/gh-budget"];
const DIGEST = remoteDigest(call, CHECKS);
const want: Want = { sha: SHA, laneId: "land", laneDigest: DIGEST };
const LEGS = ["check-sh", "suites-a", "suites-b", "chromium", "playwright-webkit"];

const job = (leg: string, conclusion: string, bind = false) => ({
  name: `land (${leg})`, status: conclusion === "" ? "in_progress" : "completed", conclusion,
  steps: bind ? [{ name: `lane: sha=${SHA} digest=${DIGEST}`, conclusion: "success" }] : [],
});
const view = (status: string, conclusion: string, conclusions: string[]): GhRunView => ({
  workflowName: "land", headSha: MARKER, status, conclusion: conclusion === "" ? null : conclusion,
  createdAt: "2026-10-21T13:59:00Z", startedAt: "2026-10-21T14:05:30Z", updatedAt: "2026-10-21T14:09:07Z",
  jobs: [{ name: "guard", conclusion: "success", steps: [] }, ...conclusions.map((c, i) => job(LEGS[i]!, c, i === 0))],
});
const ALL_OK = ["success", "success", "success", "success", "success"];

type Wait = { code: number; out: string };
function deps(waits: Wait[], views: (GhRunView | Error)[]): { d: GithubDeps; polls: () => number; views: () => number } {
  let w = 0, v = 0;
  const d: GithubDeps = {
    git: () => "", call,
    wait: async () => waits[Math.min(w++, waits.length - 1)]!,
    gh: async (args) => {
      if (args[0] === "run" && args[1] === "list") return JSON.stringify([{ databaseId: 39612772041 }]);
      const x = views[Math.min(v++, views.length - 1)]!;
      if (x instanceof Error) throw x;
      return JSON.stringify(x);
    },
  };
  return { d, polls: () => w, views: () => v };
}
const adapter = (d: GithubDeps) => githubAdapter(d, async () => ({ branch: "ci/land-t", marker: MARKER }));
const run = (d: GithubDeps, o: { deadlineS?: number; waitsLeft?: number } = {}) => {
  const logs: string[] = [];
  const p = awaitRemote({ call, adapters: { github: adapter(d) }, allow: ["github"], ctx: { task: "t", mergeSha: SHA, want, checks: CHECKS }, local: Promise.resolve(true),
    log: (m) => logs.push(m), span: () => {}, sliceS: 0.02, deadlineS: o.deadlineS ?? 20, waitsLeft: o.waitsLeft ?? 0 });
  return p.then((out) => ({ out, logs }));
};
const SLICE_OUT: Wait = { code: 3, out: "wait: timed out after 540 s; run it again to keep waiting" };
const CRASH: Wait = { code: 1, out: "node:internal/process/promises: unhandled rejection: gh: HTTP 403" };

describe("incident 2 (run 39612772041): slice timeout, then the waiter crashes after the run concluded success", () => {
  it("accept: the run's record and its per-job conclusions decide, not the waiter's exit 1", async () => {
    const { d } = deps([SLICE_OUT, CRASH], [view("completed", "success", ALL_OK)]);
    const { out, logs } = await run(d);
    expect(logs.some((l) => /lane still running/.test(l))).toBe(true);
    expect(out.verdict).toMatchObject({ kind: "accept", reason: "remote-pass" });
    expect(out.runs.map((r) => r.state)).toEqual(["pass"]);
    expect(out.details).toEqual([]);
  });
});

describe("incident 1 (run 39576215019): the waiter errors while the run is still going", () => {
  it("keeps waiting on exit 1 / exit 2 with an in-progress record, then accepts when the run is green", async () => {
    const going = view("in_progress", "", ["success", "", "", "", ""]);
    const { d, polls } = deps([SLICE_OUT, CRASH, { code: 2, out: "wait: gh refused" }, { code: 0, out: "run 39576215019 land success -> pass" }],
      [going, going, view("completed", "success", ALL_OK)]);
    const { out } = await run(d);
    expect(polls()).toBe(4);
    expect(out.verdict).toMatchObject({ kind: "accept" });
    expect(out.runs.map((r) => r.state)).toEqual(["pass"]);
  });
  it("a waiter error with no readable record keeps waiting (polls again), never fail, never an early local run", async () => {
    const { d, polls } = deps([CRASH], [new Error("gh: HTTP 403")]);
    const { out } = await run(d, { deadlineS: 0.3 });
    expect(polls()).toBeGreaterThan(1);
    expect(out.verdict).toMatchObject({ kind: "local", reason: "remote-timeout-run-locally" });
    expect(out.runs.map((r) => r.state)).toEqual(["timeout"]);
  });
  it("a waiter error with no record, then a green record: accept", async () => {
    const { d, polls } = deps([CRASH], [new Error("gh: HTTP 403"), view("completed", "success", ALL_OK)]);
    const { out } = await run(d, { deadlineS: 5 });
    expect(polls()).toBeGreaterThan(1);
    expect(out.verdict).toMatchObject({ kind: "accept", reason: "remote-pass" });
  });
});

describe("incident 2, production read: the waiter's cached record (cachedLaneView shape) has no job conclusions", () => {
  it("a completed success hit plus a crashed waiter reads the full run view and accepts", async () => {
    const cached: GhRunView = { ...view("completed", "success", ALL_OK), jobs: [{ name: "guard", steps: [] }, { name: "lane", steps: [{ name: `lane: sha=${SHA} digest=${DIGEST}`, conclusion: "success" }] }] };
    const { d, views } = deps([CRASH], [view("completed", "success", ALL_OK)]);
    const { out } = await run({ ...d, cache: () => cached });
    expect(views()).toBe(1);
    expect(out.verdict).toMatchObject({ kind: "accept", reason: "remote-pass" });
    expect(out.runs.map((r) => r.state)).toEqual(["pass"]);
  });
});

describe("timeout: the run never ends inside the budget", () => {
  it("is the timeout verdict (run the tier locally), never remote-lane-failed", async () => {
    const { d } = deps([SLICE_OUT], [view("in_progress", "", ["", "", "", "", ""])]);
    const { out } = await run(d, { deadlineS: 0.2 });
    expect(out.runs.map((r) => r.state)).toEqual(["timeout"]);
    expect(out.verdict).toMatchObject({ kind: "local", reason: "remote-timeout-run-locally" });
  });
});

describe("failure: the verdict names the run, the failed legs and their check ids", () => {
  it("one failed job: refuse with run id, leg and checks", async () => {
    const bad = view("completed", "failure", ["success", "failure", "success", "success", "success"]);
    const { d } = deps([{ code: 1, out: "run 39612772041 land failure -> fail (a job failed)" }], [bad]);
    const { out } = await run(d);
    expect(out.verdict).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
    const ids = (call({ op: "console.landLeg", leg: "suites-a", ids: CHECKS }) as { ids: string[] }).ids;
    expect(out.details).toHaveLength(1);
    expect(out.details[0]).toContain("run 39612772041");
    expect(out.details[0]).toContain("suites-a failure");
    expect(out.details[0]).toContain(ids.length ? `[checks ${ids.join(" ")}]` : "suites-a");
  });
  it("a green run with one failed job record (waiter exit 0) still refuses, naming the leg", async () => {
    const odd = view("completed", "success", ["success", "success", "success", "failure", "success"]);
    const { d } = deps([{ code: 0, out: "run 7 land success -> pass" }], [odd]);
    const { out } = await run(d);
    expect(out.verdict.reason).toBe("remote-lane-failed");
    expect(out.details[0]).toContain("chromium failure");
  });
  it("an unknown conclusion refuses", async () => {
    const { d } = deps([{ code: 0, out: "run 8 land timed_out -> pass" }], [view("completed", "timed_out", ALL_OK)]);
    const { out } = await run(d);
    expect(out.verdict).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
});

describe("CircleCI refusal names the pipeline, the failed legs and their checks", () => {
  it("a failed overflow group: detail with pipeline id and leg", async () => {
    const cc = circleciAdapter({ call, push: async () => ({ branch: "ci/b", marker: MARKER }), trigger: async () => "pipe-1", wait: async () => 1,
      fetch: async () => ({ sha: MARKER, lanes: [{ job: "land-x", conclusion: "fail", leg: "chromium", sha: SHA, digest: DIGEST, engine: "chromium", rc: 1 }] }) });
    const ctx = { task: "t", mergeSha: SHA, want, checks: CHECKS, legs: { all: LEGS, gh: LEGS.slice(0, 4), cc: ["chromium"] } };
    const h = await cc.start(ctx);
    const p = await cc.poll(h, ctx, 1);
    expect(p.run.state).toBe("fail");
    expect(p.detail).toContain("pipeline pipe-1, failed legs: chromium");
  });
});

describe("golden rows are served by fwcore (console.landLaneState)", () => {
  const st = (o: Record<string, unknown>) => (call({ op: "console.landLaneState", ...o }) as { state: string }).state;
  it("all jobs success, waiter exit 1: pass; in progress, exit 1: running; no record, unsaid exit 1: running", () => {
    expect(st({ exit: 1, status: "completed", conclusion: "success", saidFail: false, jobs: [{ status: "completed", conclusion: "success" }, { status: "completed", conclusion: "success" }] })).toBe("pass");
    expect(st({ exit: 1, status: "in_progress", conclusion: "", saidFail: false })).toBe("running");
    expect(st({ exit: 1, status: "", conclusion: "", saidFail: false })).toBe("running");
    expect(st({ exit: 137, status: "", conclusion: "", saidFail: false })).toBe("unavailable");
    expect(st({ exit: 1, status: "", conclusion: "", saidFail: true })).toBe("fail");
  });
});
