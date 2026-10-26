// `fw ci telemetry`: the collector of the CI job telemetry artifacts (apps/runner/src/ci-telemetry.ts). Every verdict is
// fwcore's `ci.telemetry`; this test replays the Lean golden (packages/contracts/golden/ci/telemetry.jsonl) through the
// same TS entry point, then checks the I/O around it with a fake gh and a fake CircleCI.
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, afterEach, describe, expect, it, vi } from "vitest";
import { fwcoreCall } from "../src/run.ts";
import {
  backfillExits, circleHttp, circleRecords, fillFromGhJobs, loadStore, mergeStore, parseLoose, parseTelArgs, readRecords, recordKey, tableLines,
  telemetryMain, type GhJob, type Http, type TelRecord,
} from "../src/ci-telemetry.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const haveCore = existsSync(join(root, "lean/.lake/build/bin/fwcore"));
const golden = readFileSync(join(root, "packages/contracts/golden/ci/telemetry.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });

const dirs: string[] = [];
const tmp = () => { const d = mkdtempSync(join(tmpdir(), "fw-tel-")); dirs.push(d); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
afterEach(() => vi.unstubAllGlobals());

const T0 = 1_760_000_000_000;
// A record whose run starts at T0 + runId s (numeric ids order the runs), one `install` step, optional queue time.
const rec = (runId: string, job: string, installMs: number, queueMs?: number): TelRecord => {
  const at = T0 + (Number(runId) || 0) * 1000;
  return {
  schema: 1,
  ident: { provider: "github", lane: "lean", job, runId, commit: "abc1234", class: "ubuntu24-arm64-4c" },
  machine: { os: "linux", arch: "arm64", cpu: "c", cores: 4, memMb: 16000 },
  times: { startedMs: at, endedMs: at + installMs + 1000, ...(queueMs === undefined ? {} : { createdMs: at - queueMs }) },
  steps: [{ name: "install", startMs: at, endMs: at + installMs, exit: 0 }],
  probes: [{ atMs: at + 5, cpuPct: 10, memUsedMb: 100, loadCenti: 5, diskFreeMb: 9 }],
  cache: [],
  };
};

// One fwcore process for all golden requests (it takes a while to start); each reply is compared as fwcoreCall would return it.
describe.skipIf(!haveCore)("the Lean golden through fwcore", () => {
  it("has the golden cases", () => expect(golden.length).toBeGreaterThanOrEqual(9));
  const input = golden.map((g, i) => JSON.stringify({ id: i, ...g.request })).join("\n") + "\n";
  const out = haveCore ? spawnSync(join(root, "lean/.lake/build/bin/fwcore"), [], { input, encoding: "utf8", maxBuffer: 64 << 20, env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" } }) : null;
  const replies = new Map<number, Record<string, unknown>>();
  for (const l of (out?.stdout ?? "").split("\n").filter(Boolean)) { const { id, ...rest } = JSON.parse(l) as { id: number }; replies.set(id, rest); }
  golden.forEach((g, i) => it(`replays: ${g.name}`, () => expect(replies.get(i)).toEqual(g.response)));
});

describe("the producer", () => {
  it("passes its own tests (scripts/ci-telemetry/cli.test.mjs, node --test)", () => {
    const r = spawnSync(process.execPath, ["--test", join(root, "scripts/ci-telemetry/cli.test.mjs")], { encoding: "utf8" });
    expect(r.status, (r.stdout ?? "").slice(-2000)).toBe(0);
  });
  it("passes the upload tick tests (scripts/ci-telemetry/tick.test.mjs, node --test)", () => {
    const r = spawnSync(process.execPath, ["--test", join(root, "scripts/ci-telemetry/tick.test.mjs")], { encoding: "utf8" });
    expect(r.status, (r.stdout ?? "").slice(-2000)).toBe(0);
  });
});

describe("arguments", () => {
  it("takes a provider and an id", () => {
    expect(parseTelArgs(["github", "123"])).toEqual({ provider: "github", id: "123" });
    expect(parseTelArgs(["circleci", "0a1b2c3d-1111-2222-3333-444455556666", "--slug", "gh/o/r", "--store", "/x"])).toMatchObject({ slug: "gh/o/r", store: "/x" });
  });
  it("refuses an unknown provider, a missing id and a stray flag", () => {
    expect(() => parseTelArgs(["gitlab", "1"])).toThrow(/provider/);
    expect(() => parseTelArgs(["github"])).toThrow(/run id/);
    expect(() => parseTelArgs(["github", "1", "--x"])).toThrow(/unexpected/);
  });
});

describe("parseLoose", () => {
  it("accepts strict JSON and escapes raw control characters inside strings only", () => {
    expect(parseLoose("{\"a\": 1}")).toEqual({ a: 1 });
    expect(parseLoose("{\"a\": \"x\ny\",\n \"b\": 2}")).toEqual({ a: "x\ny", b: 2 });
  });
});

describe("store and GitHub fill", () => {
  it("mergeStore replaces a record with the same key and appends new keys", () => {
    const a = rec("1", "j", 10), b = rec("2", "j", 20), a2 = rec("1", "j", 99);
    const m = mergeStore([a, b], [a2, rec("3", "j", 5)]);
    expect(m.map(recordKey)).toEqual(["github|1|j", "github|2|j", "github|3|j"]);
    expect(m[0]!.steps[0]!.endMs - m[0]!.steps[0]!.startMs).toBe(99);
  });

  it("fillFromGhJobs adds the steps of the same-named job when the record has no created time, and leaves one with it alone", () => {
    const jobs: GhJob[] = [{ name: "engine (chromium)", startedAt: new Date(T0 - 7000).toISOString(), steps: [
      { name: "Checkout", conclusion: "success", startedAt: new Date(T0 - 7000).toISOString(), completedAt: new Date(T0 - 4000).toISOString() },
      { name: "Telemetry finish", conclusion: "success", startedAt: new Date(T0).toISOString(), completedAt: new Date(T0 + 1000).toISOString() },
      { name: "Skipped", conclusion: "skipped", startedAt: new Date(T0).toISOString(), completedAt: new Date(T0).toISOString() },
    ] }];
    const r = fillFromGhJobs(rec("1", "engine-chromium", 10), jobs);
    expect(r.steps.map((s) => s.name)).toEqual(["Checkout", "install"]);
    expect(r.times.startedMs).toBe(T0 - 7000);
    const withCreated = rec("1", "engine-chromium", 10, 9000);
    expect(fillFromGhJobs(withCreated, jobs)).toBe(withCreated);
  });

  it("backfillExits sets the exit of a failed step and of the last open step from gh run view, and keeps the record's own times (run 39314718340, job gate playwright-webkit j0)", () => {
    const at = (s: number) => new Date(T0 + s * 1000).toISOString();
    // gh run view --json jobs: the failing smoke test is conclusion=failure, the artifact upload was skipped, the download ran twice
    const jobs: GhJob[] = [{ name: "gate playwright-webkit j0", startedAt: at(0), steps: [
      { name: "Run actions/download-artifact@x", conclusion: "success", startedAt: at(1), completedAt: at(2) },
      { name: "Run ./.github/actions/gate-engine", conclusion: "success", startedAt: at(2), completedAt: at(32) },
      { name: "Smoke test the engine (fails in under two minutes instead of burning the job budget)", conclusion: "failure", startedAt: at(32), completedAt: at(72) },
      { name: "Run actions/download-artifact@x", conclusion: "success", startedAt: at(72), completedAt: at(73) },
      { name: "Run actions/upload-artifact@x", conclusion: "skipped", startedAt: at(73), completedAt: at(73) },
    ] }];
    const base = rec("1", "gate-playwright-webkit-j0", 10, 9000);
    const r: TelRecord = { ...base, times: { ...base.times, startedMs: T0 }, steps: [
      { name: "Run actions/download-artifact@x", startMs: T0 + 1000, endMs: T0 + 2000, exit: 0 },
      { name: "Run ./.github/actions/gate-engine", startMs: T0 + 2000, endMs: T0 + 32000, exit: 0 },
      { name: "Smoke test the engine (fails in under two minutes instead of burning the job budget)", startMs: T0 + 32000, endMs: T0 + 73500 }, // exit undefined, end = finish time
      { name: "Run actions/download-artifact@x", startMs: T0 + 72000, endMs: T0 + 73500 }, // second step of that name: matched with the second one
    ] };
    const out = backfillExits(r, jobs);
    expect(out.steps.map((s) => s.exit)).toEqual([0, 0, 1, 0]);
    expect(out.steps[2]!.endMs).toBe(T0 + 72000); // the open end is replaced by the settled one
    expect(out.steps[3]!.endMs).toBe(T0 + 73000);
    expect(out.times).toEqual(r.times); // the in-job times are kept
    expect(out.steps[0]).toBe(r.steps[0]); // a step with an exit is left alone
    const none = { ...r, steps: [r.steps[0]!] };
    expect(backfillExits(none, jobs)).toBe(none);
    expect(backfillExits(r, [])).toBe(r);
  });

  it("readRecords reads telemetry.json of every artifact directory and refuses a file that is no record", () => {
    const d = tmp();
    mkdirSync(join(d, "telemetry-a"));
    writeFileSync(join(d, "telemetry-a", "telemetry.json"), JSON.stringify(rec("1", "a", 1)));
    expect(readRecords(d).map((r) => r.ident.job)).toEqual(["a"]);
    mkdirSync(join(d, "telemetry-b"));
    writeFileSync(join(d, "telemetry-b", "telemetry.json"), "{\"schema\":2}");
    expect(() => readRecords(d)).toThrow(/not a telemetry record/);
  });
});

describe.skipIf(!haveCore)("the command, GitHub", () => {
  const fakeGh = (records: TelRecord[]) => async (args: string[]): Promise<string> => {
    if (args[0] === "run" && args[1] === "download") {
      const dir = args[args.indexOf("-D") + 1]!;
      records.forEach((r, i) => { mkdirSync(join(dir, `telemetry-${i}`), { recursive: true }); writeFileSync(join(dir, `telemetry-${i}`, "telemetry.json"), JSON.stringify(r)); });
      return "";
    }
    if (args[0] === "run" && args[1] === "view") return JSON.stringify({ jobs: [] });
    throw new Error(`unexpected gh ${args.join(" ")}`);
  };

  it("stores the records, prints the table, and flags the step that is slow against its own history", async () => {
    const store = tmp();
    const lines: string[] = [];
    const call = fwcoreCall(root);
    const base = { call, http: (async () => { throw new Error("no http for github"); }) as Http, store, tmp: tmp(), slug: () => "gh/o/r", log: (l: string) => lines.push(l) };
    // three quiet runs of about 41 s, then a 70 s run of the same step: slow against the three before it (the store)
    for (const [i, s] of [40_000, 42_000, 41_000].entries()) {
      expect(await telemetryMain({ provider: "github", id: String(100 + i) }, { ...base, gh: fakeGh([rec(String(100 + i), "j", s, 3000)]) })).toBe(0);
    }
    lines.length = 0;
    expect(await telemetryMain({ provider: "github", id: "103" }, { ...base, gh: fakeGh([rec("103", "j", 70_000, 3000)]) })).toBe(0);
    const text = lines.join("\n");
    expect(text).toMatch(/1 job records stored \(4 in the store\)/);
    expect(text).toMatch(/SLOW lean\/j\/install#github\/ubuntu24-arm64-4c: 70\.0 s against baseline 41\.0 s over 3 runs/);
    expect(loadStore(join(store, "records.jsonl"))).toHaveLength(4);
    // the same run again replaces its own record: the store does not grow
    await telemetryMain({ provider: "github", id: "103" }, { ...base, gh: fakeGh([rec("103", "j", 70_000, 3000)]) });
    expect(loadStore(join(store, "records.jsonl"))).toHaveLength(4);
  });

  it("refuses a run without telemetry artifacts", async () => {
    const lines: string[] = [];
    const code = await telemetryMain({ provider: "github", id: "9" }, { call: fwcoreCall(root), gh: fakeGh([]), http: (async () => "") as Http, store: tmp(), tmp: tmp(), slug: () => "x", log: (l) => lines.push(l) });
    expect(code).toBe(2);
    expect(lines.join("\n")).toMatch(/no telemetry artifact/);
  });

  it("tableLines lists only the given runs", () => {
    const reply = { spans: [
      { runId: "1", job: "j", name: "a", tool: "t", step: "j/a", kind: "k", durMs: 1000, code: "noBaseline", n: 0, baseline: 0, budgetMs: 5000 },
      { runId: "2", job: "j", name: "b", tool: "t", step: "j/b", kind: "k", durMs: 2000, code: "ok", n: 3, baseline: 1500, budgetMs: 5000 },
    ], slow: [] };
    const out = tableLines(reply, new Set(["2"])).join("\n");
    expect(out).toMatch(/ b /);
    expect(out).not.toMatch(/ a /);
    expect(out).toMatch(/slow: none/);
  });

  // macos-telemetry fix 3: a (matched) row per job, computed by Lean (obs.macMatched), so a GitHub job compares with a
  // Codemagic or CircleCI one: the upload, telemetry and post steps matched time drops on every provider are taken out of the wall time.
  const span = (name: string, durMs: number) => ({ runId: "7", job: "sim", name, tool: "t", step: `sim/${name}`, kind: "k", durMs, code: "ok", n: 3, baseline: durMs, budgetMs: 999999 });
  const simSpans = [
    span("(queue)", 4000), span("Determinism sessions", 60_000), span("Run actions/upload-artifact@abc", 10_000),
    span("Run ./.github/actions/telemetry", 20_000), span("Post Run actions/checkout@abc", 5_000), span("(job)", 100_000),
  ];

  it("tableLines adds one (matched) row per job: wall minus upload, telemetry and post steps, from fwcore", () => {
    const out = tableLines({ spans: simSpans, slow: [] }, new Set(["7"]), fwcoreCall(root));
    const matched = out.filter((l) => / matched$/.test(l));
    expect(matched).toHaveLength(1);
    expect(matched[0]).toMatch(/\(matched: wall - upload, telemetry, post\)\s+65\.0 /);
    // the row comes right after the (job) row; without a call the table is the old one
    expect(out.findIndex((l) => / matched$/.test(l))).toBe(out.findIndex((l) => / \(job\) /.test(l)) + 1);
    expect(tableLines({ spans: simSpans, slow: [] }, new Set(["7"])).some((l) => / matched$/.test(l))).toBe(false);
  });

  it("tableLines hands Lean the wall time and the durations of the steps, not the queue or the (job) span", () => {
    const seen: unknown[] = [];
    const call = ((req: { op: string }) => { seen.push(req); return { matchedMs: 1, unmatchedMs: 2 }; }) as unknown as Parameters<typeof tableLines>[2];
    tableLines({ spans: simSpans, slow: [] }, new Set(["7"]), call);
    expect(seen).toHaveLength(1);
    const req = seen[0] as { op: string; wallMs: number; steps: { name: string; startMs: number; endMs: number }[] };
    expect(req.op).toBe("obs.macMatched");
    expect(req.wallMs).toBe(100_000);
    expect(req.steps.map((s) => s.name)).toEqual(["Determinism sessions", "Run actions/upload-artifact@abc", "Run ./.github/actions/telemetry", "Post Run actions/checkout@abc"]);
    expect(req.steps.map((s) => s.endMs - s.startMs)).toEqual([60_000, 10_000, 20_000, 5_000]);
  });
});

describe("the command, CircleCI", () => {
  const SLUG = "gh/o/r";
  const art = { schema: 1, ident: { provider: "circleci", lane: "ci", job: "build", runId: "p-1", commit: "abc1234", class: "docker-medium" },
    machine: { os: "linux", arch: "x64", cpu: "c", cores: 2, memMb: 4096 }, times: { startedMs: T0, endedMs: T0 + 5000 }, steps: [], probes: [], cache: [] };

  it("walks pipeline, workflow, job and artifacts, and puts the queue time into the record", async () => {
    const seen: string[] = [];
    const http: Http = async (url) => {
      seen.push(url);
      if (url.endsWith("/pipeline/p-1/workflow")) return JSON.stringify({ items: [{ id: "w-1" }] });
      if (url.endsWith("/workflow/w-1/job")) return JSON.stringify({ items: [{ job_number: 7 }, { job_number: 8 }] });
      if (url.endsWith(`/project/${SLUG}/7/artifacts`)) return JSON.stringify({ items: [{ path: "telemetry/telemetry.json", url: "https://art.example/7" }] });
      if (url.endsWith(`/project/${SLUG}/8/artifacts`)) return JSON.stringify({ items: [] });
      if (url === "https://art.example/7") return JSON.stringify(art);
      if (url.endsWith(`/project/${SLUG}/job/7`)) return `{"queued_at":"${new Date(T0 - 2000).toISOString()}","started_at":"${new Date(T0 + 500).toISOString()}"}`;
      throw new Error(`unexpected ${url}`);
    };
    const [r] = await circleRecords(http, SLUG, "p-1");
    expect(r!.times.createdMs).toBe(T0 - 2000);
    expect(r!.times.startedMs).toBe(T0 + 500);
    expect(seen.filter((u) => u.includes("/artifacts"))).toHaveLength(2);
  });

  it("sends the token as a header, never in the URL, and an error does not carry it", async () => {
    const secret = "tok-0123456789";
    const calls: { url: string; headers: Record<string, string> }[] = [];
    vi.stubGlobal("fetch", async (url: string, init: { headers: Record<string, string> }) => { calls.push({ url, headers: init.headers }); return { ok: false, status: 401, text: async () => "" }; });
    const http = circleHttp({ CIRCLE_TOKEN: secret });
    await expect(http("https://circleci.com/api/v2/pipeline/p/workflow?x=1")).rejects.toThrow(/answered 401/);
    expect(calls[0]!.headers["Circle-Token"]).toBe(secret);
    expect(calls[0]!.url).not.toContain(secret);
    await http("https://circleci.com/api/v2/x").catch((e: Error) => expect(e.message).not.toContain(secret));
  });
});
