import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { awaitRemote, failureDetail, githubAdapter, laneRead, laneStateOf, legRecords, remoteDigest, type GhRunView, type GithubDeps, type Want } from "../src/land-remote.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const SHA = "a".repeat(40);
const MARKER = "b".repeat(40);
const CHECKS = ["apps/runner", "packages/gh-budget"];
const DIGEST = remoteDigest(call, CHECKS);
const want: Want = { sha: SHA, laneId: "land", laneDigest: DIGEST };

type Golden = { name: string; request: Record<string, unknown>; response: Record<string, unknown> };
const golden: Golden[] = readFileSync(join(root, "packages/contracts/golden/console/land-remote.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Golden);
const line = (name: string): Golden => {
  const g = golden.find((x) => x.name === name);
  if (!g) throw new Error(`no golden line ${name}`);
  return g;
};
const BOUND = line("run 39792901389 at land time, reads used up: unavailable, not fail").request.reads as number;

type J = { status: string; conclusion: string };
const OPEN: J = { status: "in_progress", conclusion: "" };
const OK: J = { status: "completed", conclusion: "success" };
const record = (legs: [J, J, J, J, J]): GhRunView => ({
  workflowName: "land", headSha: MARKER, status: "completed", conclusion: "success",
  createdAt: "2026-10-22T13:20:00Z", startedAt: "2026-10-22T13:20:10Z", updatedAt: "2026-10-22T13:58:00Z",
  jobs: [{ name: "guard", status: "completed", conclusion: "success", steps: [] },
    ...["playwright-webkit", "check-sh", "chromium", "suites-a", "suites-b"].map((leg, k) => ({
      name: `land (${leg})`, ...legs[k]!,
      steps: leg === "check-sh" ? [{ name: `lane: sha=${SHA} digest=${DIGEST}`, conclusion: "success" }] : [],
    }))],
});
const AT_LAND = record([OPEN, OK, OPEN, OPEN, OPEN]);
const FINAL = record([OK, OK, OK, OK, OK]);

type Wait = { code: number; out: string };
function deps(waits: Wait[], views: GhRunView[]): { d: GithubDeps; views: () => number } {
  let w = 0, v = 0;
  const d: GithubDeps = {
    git: () => "", call,
    wait: async () => waits[Math.min(w++, waits.length - 1)]!,
    gh: async (args) => {
      if (args[0] === "run" && args[1] === "list") return JSON.stringify([{ databaseId: 39792901389 }]);
      return JSON.stringify(views[Math.min(v++, views.length - 1)]!);
    },
  };
  return { d, views: () => v };
}
const run = (d: GithubDeps, waitsLeft = 0) => {
  const logs: string[] = [];
  return awaitRemote({ call, adapters: { github: githubAdapter(d, async () => ({ branch: "ci/land-t", marker: MARKER })) }, allow: ["github"],
    ctx: { task: "t", mergeSha: SHA, want, checks: CHECKS }, local: Promise.resolve(true), log: (m) => logs.push(m), span: () => {},
    sliceS: 0.02, deadlineS: 20, waitsLeft }).then((out) => ({ out, logs }));
};
const PASS: Wait = { code: 0, out: "run 39792901389 land success -> pass" };
const SAID_FAIL: Wait = { code: 1, out: "run 39792901389 land success -> fail (jobs not concluded)" };

describe("the record of run 39792901389 is the Lean golden", () => {
  it("legRecords of the record is the golden request; fwcore answers the golden response", () => {
    for (const name of ["run 39792901389 at land time, waiter exit 0: running, read again", "run 39792901389 at land time, waiter exit 1 said fail: running, read again"]) {
      const g = line(name);
      expect(legRecords(AT_LAND)).toEqual(g.request.jobs);
      expect(call(g.request)).toEqual(g.response);
    }
    expect(laneStateOf(call, 0, PASS.out, AT_LAND)).toBe("running");
    expect(laneRead(call, 1, SAID_FAIL.out, AT_LAND)).toEqual({ state: "running", reread: true });
    expect(laneRead(call, 0, PASS.out, AT_LAND, BOUND)).toEqual({ state: "unavailable", reread: true });
    expect(laneRead(call, 0, PASS.out, FINAL, 1)).toEqual({ state: "pass", reread: false });
  });
  it("legStates of the record: four pending legs, check-sh ok", () => {
    const g = line("run 39792901389 at land time");
    expect(legRecords(AT_LAND)).toEqual(g.request.jobs);
    expect(call(g.request)).toEqual({ legs: ["pending", "ok", "pending", "pending", "pending"] });
  });
  it("a job record without a status (the poller's cached facts) says nothing", () => {
    expect(legRecords({ ...AT_LAND, jobs: [{ name: "lane", conclusion: "success" }] })).toBeNull();
  });
});

describe("the land re-reads a completed run with a pending leg", () => {
  it("waiter pass, record unfinished, then finalised: accept after one re-read", async () => {
    const { d, views } = deps([PASS], [AT_LAND, FINAL]);
    const { out, logs } = await run(d);
    expect(views()).toBe(2);
    expect(out.verdict).toMatchObject({ kind: "accept", reason: "remote-pass" });
    expect(logs.some((l) => /has not finalised \(read 1\); the record is read again/.test(l))).toBe(true);
  });
  it("waiter said fail on the unfinished record: still re-read, then accept", async () => {
    const { d, views } = deps([SAID_FAIL, PASS], [AT_LAND, FINAL]);
    const { out } = await run(d);
    expect(views()).toBe(2);
    expect(out.verdict).toMatchObject({ kind: "accept", reason: "remote-pass" });
  });
  it("a record that never settles is read 1 + rereadBound times, then unavailable: run locally, never refused as failed", async () => {
    const { d, views } = deps([PASS], [AT_LAND]);
    const { out, logs } = await run(d);
    expect(views()).toBe(BOUND + 1);
    expect(out.runs.map((r) => r.state)).toEqual(["unavailable"]);
    expect(out.verdict.kind).toBe("local");
    expect(out.details).toEqual([]);
    expect(logs.some((l) => /the reads are used up, the run counts as unavailable/.test(l))).toBe(true);
  });
  it("with degraded waits left the unavailable run is read once more and passes when finalised", async () => {
    const views = [...Array.from({ length: BOUND + 1 }, () => AT_LAND), FINAL];
    const { d, views: n } = deps([PASS], views);
    const { out } = await run(d, 1);
    expect(n()).toBe(BOUND + 2);
    expect(out.verdict).toMatchObject({ kind: "accept", reason: "remote-pass" });
  });
});

describe("a refusal names only completed failed legs", () => {
  it("a failed run with unfinished legs names the failed leg, not the pending ones", () => {
    const v = { ...record([OPEN, OK, { status: "completed", conclusion: "failure" }, OPEN, OPEN]), conclusion: "failure" };
    const detail = failureDetail(call, "39792901389", v, CHECKS);
    expect(detail).toContain("failed legs: chromium failure");
    expect(detail).not.toMatch(/playwright-webkit|suites-a|suites-b/);
  });
});
