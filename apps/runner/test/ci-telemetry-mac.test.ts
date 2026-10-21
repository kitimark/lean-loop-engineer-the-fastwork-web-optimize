// `fw ci telemetry macos-window` (apps/runner/src/ci-telemetry-mac.ts): the collector of the 7-day macOS dataset. The sample, the
// macOS-job test and every table are fwcore; this test checks the I/O glue (time conversion, list and view calls, the three providers)
// with a fake gh and fake provider replies, and that the dataset it writes reduces through the real `obs.macReduce`.
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { fwcoreCall, type Gh } from "../src/run.ts";
import {
  circleMac, circleRows, codemagicRow, collectMac, isoMs, jobRows, MAC_WORKFLOWS, parseMacArgs, runRows, type CircleIo, type MacArgs,
} from "../src/ci-telemetry-mac.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const haveCore = existsSync(join(root, "lean/.lake/build/bin/fwcore"));

const NOW = Date.UTC(2026, 9, 22, 12, 0, 0);
const iso = (ms: number) => new Date(ms).toISOString();

describe("arguments and times", () => {
  it("has defaults and reads the flags", () => {
    expect(parseMacArgs([])).toEqual({ days: 7, sample: 200, circleci: true, codemagic: true });
    expect(parseMacArgs(["--days", "3", "--sample", "50", "--out", "x.jsonl", "--no-circleci", "--no-codemagic"]))
      .toEqual({ days: 3, sample: 50, out: "x.jsonl", circleci: false, codemagic: false });
  });
  it("refuses a bad number, a missing file and an unknown flag", () => {
    expect(() => parseMacArgs(["--days", "0"])).toThrow(/positive whole number/);
    expect(() => parseMacArgs(["--sample", "x"])).toThrow(/positive whole number/);
    expect(() => parseMacArgs(["--out"])).toThrow(/--out needs a file/);
    expect(() => parseMacArgs(["--bogus"])).toThrow(/unknown argument/);
  });
  it("reads ISO times and turns GitHub's zero time into null", () => {
    expect(isoMs("2026-10-22T12:00:00Z")).toBe(NOW);
    expect(isoMs("0001-01-01T00:00:00Z")).toBeNull();
    expect(isoMs(undefined)).toBeNull();
    expect(isoMs("not a time")).toBeNull();
  });
});

describe("run and job rows", () => {
  const T = NOW - 3 * 86400000;
  it("keeps completed runs inside the window, with the start defaulting to the creation", () => {
    const rows = runRows("wktr", [
      { databaseId: 1, createdAt: iso(T), startedAt: iso(T + 5000), updatedAt: iso(T + 65000), status: "completed", conclusion: "success", event: "push" },
      { databaseId: 2, createdAt: iso(T), status: "in_progress", event: "push" },
      { databaseId: 3, createdAt: iso(NOW - 9 * 86400000), startedAt: iso(NOW - 9 * 86400000), updatedAt: iso(NOW - 9 * 86400000 + 1000), status: "completed", conclusion: "success" },
      { databaseId: 4, createdAt: iso(T), updatedAt: iso(T + 9000), status: "completed", conclusion: "failure", event: "workflow_dispatch" },
    ], NOW - 7 * 86400000);
    expect(rows.map((r) => r.id)).toEqual(["1", "4"]);
    expect(rows[0]).toEqual({ wf: "wktr", id: "1", event: "push", createdMs: T, startMs: T + 5000, endMs: T + 65000, concl: "success" });
    expect(rows[1]).toMatchObject({ startMs: T, endMs: T + 9000, concl: "failure" });
  });
  it("keeps steps for macOS jobs only and falls back to the run creation for a job that never started", () => {
    const run = { wf: "webkit-sim", id: "9", event: "push", createdMs: T, startMs: T, endMs: T + 1, concl: "success" };
    const steps = [{ name: "Set up job", startedAt: iso(T + 1000), completedAt: iso(T + 3000) }, { name: "never", startedAt: "0001-01-01T00:00:00Z", completedAt: "0001-01-01T00:00:00Z" }];
    const rows = jobRows(run, [
      { name: "sim (webkit)", conclusion: "success", startedAt: iso(T + 500), completedAt: iso(T + 9000), steps },
      { name: "plan", conclusion: "skipped", startedAt: "0001-01-01T00:00:00Z", completedAt: "0001-01-01T00:00:00Z", steps },
    ], (_wf, names) => names.map((n) => n.startsWith("sim")));
    expect(rows[0]!.steps).toEqual([{ name: "Set up job", startMs: T + 1000, endMs: T + 3000 }]);
    expect(rows[1]).toMatchObject({ steps: [], startMs: T, endMs: T, createdMs: T, concl: "skipped", prov: "github" });
  });
});

describe("Codemagic and CircleCI rows", () => {
  it("lays the Codemagic steps end to end from the start", () => {
    const row = codemagicRow({ id: "b1", status: "finished", instanceType: "mac_mini_m2", createdAt: 1000, startedAt: 2000, finishedAt: 20000, steps: [{ name: "a", durMs: 3000 }, { name: "b", durMs: 4000 }] })!;
    expect(row).toMatchObject({ prov: "codemagic", wf: "webkit-sim", run: "b1", runner: "mac_mini_m2", createdMs: 1000, startMs: 2000, endMs: 20000, concl: "finished" });
    expect(row.steps).toEqual([{ name: "a", startMs: 2000, endMs: 5000 }, { name: "b", startMs: 5000, endMs: 9000 }]);
    expect(codemagicRow({ id: "x", status: "finished", createdAt: null, startedAt: null, finishedAt: null, steps: [] })).toBeNull();
  });
  it("knows the macOS resource classes", () => {
    expect(circleMac("m4pro-medium")).toBe(true);
    expect(circleMac("macos.m1.medium.gen1")).toBe(true);
    expect(circleMac("arm-medium-gen2")).toBe(false);
    expect(circleMac(undefined)).toBe(false);
  });
  it("walks pipelines, keeps the webkit-sim macOS jobs only, and never puts the project slug in an error or a row", async () => {
    const seen: string[] = [];
    const T = NOW - 86400000;
    const io: CircleIo = {
      get: async (url) => {
        seen.push(url);
        if (url === "https://x/pipelines") return { items: [{ id: "p1", created_at: iso(T), trigger: { type: "api" } }, { id: "p2", created_at: iso(T), trigger: { type: "webhook" } }, { id: "p0", created_at: iso(NOW - 20 * 86400000), trigger: { type: "api" } }] };
        if (url === "https://x/p1/workflows") return { items: [{ id: "w1", name: "webkit-sim" }, { id: "w2", name: "land" }] };
        if (url === "https://x/w1/jobs") return { items: [{ name: "webkit-sim", status: "success", job_number: 41 }, { name: "notrun", status: "blocked" }] };
        if (url === "https://x/job/41") return { queued_at: iso(T + 1000), started_at: iso(T + 60000), stopped_at: iso(T + 360000), executor: { resource_class: "m4pro-medium" } };
        if (url === "https://x/steps/41") return { steps: [{ actions: [{ name: "Spin up environment", start_time: iso(T + 60000), end_time: iso(T + 61000) }] }] };
        throw new Error(`unexpected ${url}`);
      },
      urls: { pipelines: "https://x/pipelines", workflows: (p) => `https://x/${p}/workflows`, jobs: (w) => `https://x/${w}/jobs`, job: (n) => `https://x/job/${n}`, jobSteps: (n) => `https://x/steps/${n}` },
      log: () => {},
    };
    const rows = await circleRows(io, NOW - 7 * 86400000);
    expect(rows).toEqual([{ prov: "circleci", wf: "webkit-sim", run: "41", name: "webkit-sim", runner: "m4pro-medium", event: "", createdMs: T + 1000, startMs: T + 60000, endMs: T + 360000, concl: "success", steps: [{ name: "Spin up environment", startMs: T + 60000, endMs: T + 61000 }] }]);
    expect(seen).not.toContain("https://x/p2/workflows");
  });
});

// A fake gh over three workflows: run lists by workflow, job views by run id.
const T1 = NOW - 2 * 86400000;
const simSteps = (at: number) => [
  { name: "Set up job", startedAt: iso(at), completedAt: iso(at + 5000) },
  { name: "Boot the Simulator (kept booted for the whole job)", startedAt: iso(at + 5000), completedAt: iso(at + 65000) },
  { name: "Determinism sessions", startedAt: iso(at + 65000), completedAt: iso(at + 365000) },
  { name: "Run ./.github/actions/telemetry", startedAt: iso(at + 365000), completedAt: iso(at + 385000) },
  { name: "Delete the Simulator device", startedAt: iso(at + 385000), completedAt: iso(at + 400000) },
];
const fakeGh = (log: string[]): Gh => async (args) => {
  log.push(args.slice(0, 3).join(" "));
  if (args[0] === "run" && args[1] === "list") {
    const wf = args[args.indexOf("--workflow") + 1];
    if (wf !== "webkit-sim") return "[]";
    return JSON.stringify([
      { databaseId: 101, createdAt: iso(T1), startedAt: iso(T1 + 1000), updatedAt: iso(T1 + 500000), status: "completed", conclusion: "success", event: "push" },
      { databaseId: 102, createdAt: iso(T1 + 90000000 / 1000), startedAt: iso(T1 + 91000), updatedAt: iso(T1 + 100000), status: "completed", conclusion: "success", event: "push" },
    ]);
  }
  if (args[0] === "run" && args[1] === "view") {
    return JSON.stringify({ jobs: [
      { name: "plan", conclusion: "success", startedAt: iso(T1 + 1000), completedAt: iso(T1 + 21000), steps: [{ name: "Set up job", startedAt: iso(T1 + 1000), completedAt: iso(T1 + 2000) }] },
      { name: "sim (webkit)", conclusion: "success", startedAt: iso(T1 + 21000), completedAt: iso(T1 + 421000), steps: simSteps(T1 + 21000) },
    ] });
  }
  throw new Error(`unexpected gh ${args.join(" ")}`);
};

describe.skipIf(!haveCore)("collectMac through fwcore", () => {
  const args: MacArgs = { days: 7, sample: 200, circleci: true, codemagic: true };
  it("lists the seven workflows, reads only the sampled runs of 120 s or more, and writes ids, names and times only", async () => {
    const log: string[] = [], said: string[] = [];
    const lines = await collectMac(args, {
      call: fwcoreCall(root), gh: fakeGh(log), now: NOW, log: (l) => said.push(l),
      codemagic: async () => [codemagicRow({ id: "cm1", status: "finished", instanceType: "mac_mini_m2", createdAt: T1, startedAt: T1 + 1000, finishedAt: T1 + 301000, steps: [{ name: "Preparing build machine", durMs: 40000 }] })!],
      circleci: async () => [],
    });
    expect(log.filter((l) => l === "run list --workflow")).toHaveLength(MAC_WORKFLOWS.length);
    expect(log.filter((l) => l === "run view 101")).toHaveLength(1);
    expect(log.filter((l) => l === "run view 102")).toHaveLength(0);
    const rows = lines.map((l) => JSON.parse(l) as Record<string, unknown>);
    expect(rows[0]).toEqual({ kind: "window", fromMs: NOW - 7 * 86400000, toMs: NOW, minRunMs: 120000, cap: 200, days: 7 });
    expect(rows.filter((r) => r.kind === "run").map((r) => r.id)).toEqual(["101", "102"]);
    const jobs = rows.filter((r) => r.kind === "job");
    expect(jobs.map((j) => `${j.prov}:${j.name}`)).toEqual(["github:plan", "github:sim (webkit)", "codemagic:sim"]);
    expect((jobs[0]!.steps as unknown[]).length).toBe(0);
    expect((jobs[1]!.steps as unknown[]).length).toBe(5);
    const keys = new Set(rows.flatMap((r) => Object.keys(r)));
    for (const bad of ["branch", "headBranch", "author", "email", "url", "sha", "title", "displayTitle", "actor"]) expect(keys.has(bad)).toBe(false);
    expect(said.some((l) => /stratum/.test(l))).toBe(true);
  });
  it("the dataset reduces through obs.macReduce into tables that name the Codemagic row", async () => {
    const lines = await collectMac(args, { call: fwcoreCall(root), gh: fakeGh([]), now: NOW, log: () => {},
      codemagic: async () => [codemagicRow({ id: "cm1", status: "finished", instanceType: "mac_mini_m2", createdAt: T1, startedAt: T1 + 1000, finishedAt: T1 + 301000, steps: [{ name: "Preparing build machine", durMs: 40000 }] })!] });
    const rows = lines.map((l) => JSON.parse(l) as { kind: string });
    const win = rows.find((r) => r.kind === "window") as unknown as Record<string, unknown>;
    const reply = fwcoreCall(root)({ op: "obs.macReduce", fromMs: win.fromMs, toMs: win.toMs, minRunMs: win.minRunMs, cap: win.cap,
      runs: rows.filter((r) => r.kind === "run"), jobs: rows.filter((r) => r.kind === "job") }) as unknown as { md: string; tables: Record<string, string> };
    expect(reply.md).toContain("<!-- mt:begin providers -->");
    expect(reply.tables.providers).toMatch(/codemagic/i);
    expect(reply.tables.providers).toMatch(/github/i);
  });
});
