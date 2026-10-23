// timing-alert: `timing.slow` / `NEXT investigate step=` come from fwcore's Fw.Obs.Timing verdicts (obs.slow), the TS is
// checked against packages/contracts/golden/obs/timing.jsonl; and the two watch false positives (landed after
// `fw land`, alert while the land lock is held) are decided by Lean (Fw.Obs.Next lands) from the facts built here.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { buildFacts, landCommitOnMain, nextAlerts, slowAlerts, slowNextLines, type NextReply, type Raw, type RawAgent } from "../src/next.ts";
import { coreCaller, slowFor } from "../src/watch.ts";
import { parseSamples, pathsFor } from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");
const haveCore = existsSync(fwcore);
const core = coreCaller([fwcore]);
const golden = readFileSync(join(root, "packages/contracts/golden/obs/timing.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: { op: string; params: unknown; samples: unknown[] }; response: { verdicts: unknown[] } });

const batchCore = (reqs: object[]) => {
  const input = reqs.map((q, i) => JSON.stringify({ id: i, ...q })).join("\n") + "\n";
  const r = spawnSync(fwcore, [], { input, encoding: "utf8", timeout: 120_000, maxBuffer: 64 << 20, env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" } });
  const byId = new Map<number, Record<string, unknown>>();
  for (const l of (r.stdout ?? "").split("\n").filter(Boolean)) { const m = JSON.parse(l) as { id: number }; byId.set(m.id, m); }
  return byId;
};
const goldenReq = (op: string) => golden.map((g) => ({ op, params: g.request.params, samples: g.request.samples }));
let timingBatch: Map<number, Record<string, unknown>> | null = null;
let slowBatch: Map<number, Record<string, unknown>> | null = null;

const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

describe.skipIf(!haveCore)("obs.timing / obs.slow against the Lean golden", () => {
  it("has the golden cases", () => expect(golden.length).toBeGreaterThanOrEqual(10));
  it("the golden has ceiling rows and every one reaches fwcore (params decoded, not dropped)", () => {
    const withCeil = golden.filter((g) => ((g.request.params as { ceilings?: unknown[] })?.ceilings ?? []).length > 0);
    expect(withCeil.length).toBeGreaterThanOrEqual(2);
  });
  it("one fwcore process answers every golden obs.timing and obs.slow request, one reply each", () => {
    timingBatch = batchCore(goldenReq("obs.timing"));
    slowBatch = batchCore(goldenReq("obs.slow"));
    expect(timingBatch.size).toBe(golden.length);
    expect(slowBatch.size).toBe(golden.length);
  });
  golden.forEach((g, i) => {
    it(`obs.timing replays: ${g.name.slice(0, 70)}`, () => {
      expect(timingBatch!.get(i)!.verdicts).toEqual(g.response.verdicts);
    });
  });
  it("obs.slow names the step of a slow latest sample, from the Lean verdict", async () => {
    const slow = golden.find((g) => /205 s .*slow/.test(g.name))!;
    expect((await core({ op: "obs.slow", params: slow.request.params, samples: slow.request.samples })).slow).toEqual(["lean/check.sh"]);
    const ok = golden.find((g) => /128 s .*ok/.test(g.name))!;
    expect((await core({ op: "obs.slow", params: ok.request.params, samples: ok.request.samples })).slow).toEqual([]);
  });
  it("every obs.slow subject of every golden case is a slow sample verdict of the same request", () => {
    for (const [i, g] of golden.entries()) {
      const r = slowBatch!.get(i)!.slow as string[];
      const workOf = (w?: Record<string, string>) => (w ? ` [${Object.entries(w).map(([k, x]) => `${k}=${x}`).join(",")}]` : "");
      const slowNames = new Set((g.response.verdicts as any[]).filter((v) => v.kind === "sample" && v.code === "slow").map((v) => `${v.tool}/${v.step}${v.runKind ? "#" + v.runKind : ""}${workOf(v.work)}`));
      for (const s of r) expect(slowNames.has(s)).toBe(true);
      if (slowNames.size === 0) expect(r).toEqual([]);
    }
  });
});

describe("samples and lines", () => {
  it("parseSamples orders by start time, floors load, skips bad lines", () => {
    const text = [
      JSON.stringify({ tool: "b", step: "x", startMs: 20, durMs: 5, host: "local", load: 9.9, exit: 0 }),
      "not json",
      JSON.stringify({ tool: "a", step: "y", startMs: 10, durMs: 7, host: "ci", load: 0.2 }),
      JSON.stringify({ tool: "a", step: "y", startMs: 30, durMs: -1, host: "ci" }),
      JSON.stringify({ tool: "a", step: "y", startMs: 30, durMs: 1, host: "mars" }),
    ].join("\n");
    expect(parseSamples(text)).toEqual([
      { tool: "a", step: "y", durMs: 7, host: "ci", load: 0, startMs: 10 },
      { tool: "b", step: "x", durMs: 5, host: "local", load: 9, exit: 0, startMs: 20 },
    ]);
  });
  it("prints NEXT investigate step= and one timing.slow alert per slow step", () => {
    expect(slowNextLines(["lean/check.sh", "fw/watch pass"])).toEqual(["NEXT investigate step=lean/check.sh", "NEXT investigate step=fw/watch pass"]);
    expect(slowAlerts(["lean/check.sh"])).toMatchObject([{ code: "timing.slow", subject: "lean/check.sh" }]);
    expect(slowNextLines([])).toEqual([]);
  });
  it("slowFor sends the history to obs.slow and returns fwcore's subjects; no history, no call; errors give none", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-slow-")); dirs.push(dir);
    const p = pathsFor(dir, { FW_CONSOLE_DIR: dir } as NodeJS.ProcessEnv);
    let calls = 0;
    expect(await slowFor(p, async () => { calls++; return { slow: ["x/y"] }; })).toEqual([]);
    expect(calls).toBe(0);
    writeFileSync(join(dir, "timings.jsonl"), JSON.stringify({ tool: "x", step: "y", startMs: 1, durMs: 9, host: "ci", load: 0 }) + "\n");
    const seen: Record<string, unknown>[] = [];
    expect(await slowFor(p, async (req) => { seen.push(req); return { slow: ["x/y"] }; })).toEqual(["x/y"]);
    expect(seen[0]).toMatchObject({ op: "obs.slow", samples: [{ tool: "x", step: "y", durMs: 9, host: "ci", load: 0 }] });
    expect(await slowFor(p, async () => { throw new Error("no fwcore"); })).toEqual([]);
  });
});

// ---- the two false positives ----
const raw = (a: Partial<RawAgent>, landLock: string | null = null): Raw => ({
  now: 1_000_000, session: 1, procs: [], ps: [], alive: () => false, file: () => null, queuedText: "", ci: [], board: new Map(), landLock,
  agents: [{
    id: "t", name: "t", task: "t", state: "done", ctxTokens: 0, handbackAt: 500_000, worktree: null, ahead: 3, landed: false, mergesClean: true,
    branchDeps: [], handoff: false, branch: "worktree-t", signals: null, ...a,
  }],
});
const alertsOf = async (r: Raw) => {
  const facts = buildFacts(r);
  const reply = (await core({ op: "obs.next", now: r.now, agents: facts })) as NextReply;
  return { facts, alerts: nextAlerts(reply) };
};

describe.skipIf(!haveCore)("inc-watch-unlanded-after-land and inc-watch-alert-during-land", () => {
  it("baseline: handed back, 3 ahead, not landed -> agent.unlanded", async () => {
    expect((await alertsOf(raw({}))).alerts).toMatchObject([{ code: "agent.unlanded", subject: "t" }]);
  });
  it("a land commit on main silences it even when the branch is gone from git (ahead/landed unknown)", async () => {
    const r = await alertsOf(raw({ ahead: null, landed: null, onMain: true }));
    expect(r.facts[0]!.branch).toMatchObject({ name: "worktree-t", onMain: true });
    expect(r.alerts).toEqual([]);
  });
  it("a land commit on main silences it while the branch still exists and is not an ancestor", async () => {
    expect((await alertsOf(raw({ onMain: true }))).alerts).toEqual([]);
  });
  it("a gone branch with no land commit gives no branch fact", () => {
    expect(buildFacts(raw({ ahead: null, landed: null, onMain: false }))[0]!.branch).toBeNull();
  });
  it("the live land lock naming the branch suppresses the alert; another branch's lock does not", async () => {
    expect((await alertsOf(raw({}, "worktree-t"))).alerts).toEqual([]);
    expect((await alertsOf(raw({}, "worktree-other"))).alerts).toMatchObject([{ code: "agent.unlanded" }]);
    expect((await alertsOf(raw({}, null))).alerts).toMatchObject([{ code: "agent.unlanded" }]);
  });
});

describe("landCommitOnMain reads main's history", () => {
  it("finds the Task: trailer of a land commit, not a mere mention", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-landlog-")); dirs.push(dir);
    const g = (...a: string[]) => execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", ...a], { cwd: dir, encoding: "utf8" });
    g("init", "-q", "-b", "main");
    g("commit", "-q", "--allow-empty", "-m", "land worktree-x\n\nTask: some-task");
    g("commit", "-q", "--allow-empty", "-m", "talk about Task: other-task in prose");
    const p = pathsFor(dir, {} as NodeJS.ProcessEnv);
    expect(await landCommitOnMain(p, "some-task")).toBe(true);
    expect(await landCommitOnMain(p, "other-task")).toBe(false);
    expect(await landCommitOnMain(p, "some")).toBe(false);
    expect(await landCommitOnMain(p, "some.task")).toBe(false);
  });
});
