// land-wait: the provider-neutral remote land verdict. Run records are normalized from `gh run view` JSON (the fixtures below; the
// pass shape is a recorded lane run, the others are derived from it by changing one field, and say so) and judged by fwcore.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { githubAdapter, stateOfWaitExit, landBranch, normalizeGithub, remoteDigest, remoteVerdict, awaitRemote, laneBind, circleciAdapter, type Adapter, type GhRunView, type LaneRun, type Want } from "../src/land-remote.ts";
import { fwcoreCall } from "../src/run.ts";
import { checksCli } from "../src/checks.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const SHA = "a".repeat(40);
const MARKER = "b".repeat(40);
const DIGEST = remoteDigest(call, ["apps/runner", "packages/gh-budget"]);
const want: Want = { sha: SHA, laneId: "land", laneDigest: DIGEST };
const ctx = { marker: MARKER, want };

/** Recorded shape of `gh run view <id> --json headSha,conclusion,status,createdAt,startedAt,updatedAt,jobs` for a lane run (fixtures/land-remote/*.json). */
const recorded = (name: string): GhRunView => JSON.parse(readFileSync(join(root, "apps/runner/test/fixtures/land-remote", name), "utf8")) as GhRunView;
const passView = (sha = SHA, digest = DIGEST): GhRunView => ({
  headSha: MARKER, conclusion: "success", status: "completed",
  createdAt: "2026-10-20T10:00:00Z", startedAt: "2026-10-20T10:00:10Z", updatedAt: "2026-10-20T10:05:10Z",
  jobs: [{ name: "land", conclusion: "success", steps: [{ name: "suites (the remote tier of the Lean-selected checks)", conclusion: "success" }, { name: `lane: sha=${sha} digest=${digest}`, conclusion: "success" }] }],
});
const verdictOf = (runs: LaneRun[], o: Partial<{ localOk: boolean; needed: boolean; allow: ("github" | "circleci")[]; waitsLeft: number }> = {}) =>
  remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want, waitsLeft: 0, runs, ...o });

describe("normalize a GitHub land run, then ask fwcore", () => {
  it("pass bound to the sha and digest: accept", () => {
    const run = normalizeGithub(0, passView(), ctx);
    expect(run).toEqual({ provider: "github", sha: SHA, laneId: "land", laneDigest: DIGEST, state: "pass" });
    expect(verdictOf([run])).toMatchObject({ kind: "accept", ok: true, reason: "remote-pass" });
  });
  it("fail: refuse", () => {
    const run = normalizeGithub(1, { ...passView(), conclusion: "failure" }, ctx);
    expect(verdictOf([run])).toMatchObject({ kind: "refuse", ok: false, reason: "remote-lane-failed" });
  });
  it("fail before the lane printed its binding still refuses", () => {
    const run = normalizeGithub(1, { ...passView(), conclusion: "failure", jobs: [] }, ctx);
    expect(verdictOf([run])).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
  it("pass for another sha is not accepted", () => {
    const run = normalizeGithub(0, passView("c".repeat(40)), ctx);
    expect(verdictOf([run]).ok).toBe(false);
    expect(verdictOf([run]).kind).not.toBe("accept");
  });
  it("pass for another suite list (digest) is not accepted", () => {
    const run = normalizeGithub(0, passView(SHA, remoteDigest(call, ["apps/runner"])), ctx);
    expect(verdictOf([run]).kind).not.toBe("accept");
  });
  it("pass of another commit's run (headSha) binds to nothing", () => {
    const run = normalizeGithub(0, { ...passView(), headSha: "d".repeat(40) }, ctx);
    expect(run.sha).toBe("");
    expect(verdictOf([run]).kind).not.toBe("accept");
  });
  it("pass without a lane step binds to nothing", () => {
    const run = normalizeGithub(0, { ...passView(), jobs: [] }, ctx);
    expect(verdictOf([run]).kind).not.toBe("accept");
  });
  it("cancelled (fw ci wait exit 4): run the remote tier locally", () => {
    const run = normalizeGithub(4, null, ctx);
    expect(run.state).toBe("cancelled");
    expect(verdictOf([run])).toMatchObject({ kind: "local", reason: "remote-cancelled-run-locally" });
  });
  it("unavailable (gh error, exit 2): run locally when no provider is left", () => {
    const run = normalizeGithub(2, null, ctx);
    expect(run.state).toBe("unavailable");
    expect(verdictOf([run])).toMatchObject({ kind: "local" });
  });
  it("still running (exit 3): wait", () => {
    expect(verdictOf([normalizeGithub(3, null, ctx, "ci wait: timed out after 540s")])).toMatchObject({ kind: "wait", reason: "lane-running" });
  });
  it("github pass + circleci fail across providers: refuse", () => {
    const gh = normalizeGithub(0, passView(), ctx);
    const cc: LaneRun = { provider: "circleci", sha: SHA, laneId: "land", laneDigest: DIGEST, state: "fail" };
    expect(verdictOf([gh, cc], { allow: ["github", "circleci"] })).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
    expect(verdictOf([cc, gh], { allow: ["github", "circleci"] })).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
  it("lane step names parse back to sha and digest", () => {
    expect(laneBind(passView())).toEqual({ sha: SHA, digest: DIGEST });
  });
  it("a local failure refuses even when the lane passed", () => {
    expect(verdictOf([normalizeGithub(0, passView(), ctx)], { localOk: false })).toMatchObject({ kind: "refuse", reason: "local-tier-failed" });
  });
});

describe("a recorded lane run (live proof of task land-wait: ci/land-probe-30a307f, run 39317802669)", () => {
  // fail.json is `gh run view` of the real lane run: its apps/runner suite failed because the test file had no fixture yet.
  const v = recorded("fail.json");
  const b = laneBind(v)!;
  const w: Want = { sha: b.sha, laneId: "land", laneDigest: b.digest };
  it("the lane's step name binds the run to the merge commit and its suite list", () => {
    expect(b.sha).toBe("30a307f82747ff8c632d14592134597220c66fe5");
    expect(b.digest).toBe(remoteDigest(call, ["apps/console-api", "apps/runner", "packages/engine-check", "packages/gate-breakpoints", "packages/gh-budget", "packages/measure-chromium"]));
  });
  it("fw ci wait exit 1 on it: a run bound to the sha, refused", () => {
    const run = normalizeGithub(1, v, { marker: v.headSha, want: w });
    expect(run).toEqual({ provider: "github", sha: b.sha, laneId: "land", laneDigest: b.digest, state: "fail" });
    expect(remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want: w, waitsLeft: 0, runs: [run] })).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
  it("derived: the same record with exit 0 is accepted for its sha and not for another", () => {
    const run = normalizeGithub(0, v, { marker: v.headSha, want: w });
    expect(remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want: w, waitsLeft: 0, runs: [run] }).kind).toBe("accept");
    expect(remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want: { ...w, sha: "e".repeat(40) }, waitsLeft: 0, runs: [run] }).kind).not.toBe("accept");
  });
});

describe("the recorded passing lane run (ci/land-probe-e5b7f17, run 39319745028)", () => {
  const v = recorded("pass.json");
  const b = laneBind(v)!;
  const w: Want = { sha: b.sha, laneId: "land", laneDigest: b.digest };
  it("fw ci wait exit 0: accepted for the sha it printed, not for another", () => {
    expect(b.sha).toBe("e5b7f17739f4df104dcdf4ac774b3b016f453855");
    const run = normalizeGithub(0, v, { marker: v.headSha, want: w });
    expect(run.state).toBe("pass");
    expect(remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want: w, waitsLeft: 0, runs: [run] })).toMatchObject({ kind: "accept", reason: "remote-pass" });
    expect(remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want: { ...w, sha: "e".repeat(40) }, waitsLeft: 0, runs: [run] }).kind).not.toBe("accept");
  });
});

describe("fw ci wait exit 3 and the empty binding (review round 1)", () => {
  it("exit 3 is running only with `timed out after`; a stopped poller or a refused gh call is unavailable", () => {
    expect(stateOfWaitExit(3, "ci wait: timed out after 540s")).toBe("running");
    expect(stateOfWaitExit(3, "ci wait: poller stopped")).toBe("unavailable");
    expect(stateOfWaitExit(3)).toBe("unavailable");
  });
  it("a poll that comes back running at once is slept out: polls stay near deadline/slice", async () => {
    let polls = 0;
    const quick: Adapter = { provider: "github", async start() { return { provider: "github", branch: "b", marker: MARKER }; },
      async poll() { polls++; return { run: { provider: "github", sha: SHA, laneId: "land", laneDigest: DIGEST, state: "running" } }; } };
    const t0 = Date.now();
    const o = await awaitRemote({ call, adapters: { github: quick }, allow: ["github"], ctx: { task: "t", mergeSha: SHA, want }, local: Promise.resolve(true), log: () => {}, span: () => {}, sliceS: 0.05, deadlineS: 0.5 });
    expect(Date.now() - t0).toBeGreaterThanOrEqual(450);
    expect(polls).toBeLessThanOrEqual(14);
    expect(o.verdict.kind).not.toBe("accept");
  });
  it("a lane step with empty groups binds nothing; the failed run still refuses", () => {
    const v = recorded("fail.json");
    const empty = { ...v, jobs: v.jobs!.map((j) => ({ ...j, steps: j.steps!.map((st) => (st.name.startsWith("lane:") ? { ...st, name: "lane: sha= digest=" } : st)) })) };
    expect(laneBind(empty)).toBeNull();
    const half = { ...v, jobs: v.jobs!.map((j) => ({ ...j, steps: j.steps!.map((st) => (st.name.startsWith("lane:") ? { ...st, name: `lane: sha=${"a".repeat(40)} digest=` } : st)) })) };
    expect(laneBind(half)).toBeNull();
    const run = normalizeGithub(1, empty, { marker: empty.headSha, want });
    expect(verdictOf([run])).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
});

describe("the personal-data scan before the ci/land push", () => {
  const mk = (hit: string | null) => {
    const calls: string[][] = [];
    const a = githubAdapter({ git: (args) => { calls.push(args); return "x".repeat(40); }, scan: () => hit, wait: async () => ({ code: 0, out: "" }), gh: async () => "" });
    return { a, calls };
  };
  it("a hit stops the push: the provider is unavailable with the named reason, and the land runs the tier locally", async () => {
    const { a, calls } = mk("a.md:3:5 rule=home-path");
    await expect(a.start({ task: "t", mergeSha: SHA, want })).rejects.toThrow(/personal-data scan refused/);
    expect(calls.some((c) => c[0] === "push")).toBe(false);
    const logs: string[] = [];
    const o = await awaitRemote({ call, adapters: { github: a }, allow: ["github"], ctx: { task: "t", mergeSha: SHA, want }, local: Promise.resolve(true), log: (l) => logs.push(l), span: () => {}, sliceS: 0.05, deadlineS: 5 });
    expect(o.verdict.kind).toBe("local");
    expect(logs.join("\n")).toMatch(/personal-data scan refused/);
  });
  it("a clean scan pushes", async () => {
    const { a, calls } = mk(null);
    await a.start({ task: "t", mergeSha: SHA, want });
    expect(calls.some((c) => c[0] === "push")).toBe(true);
  });
});

describe("golden land-remote.jsonl (written by Lean) through fwcore", () => {
  const lines = readFileSync(join(root, "packages/contracts/golden/console/land-remote.jsonl"), "utf8").trim().split("\n");
  it("has the Lean cases", () => expect(lines.length).toBeGreaterThanOrEqual(30));
  for (const l of lines) {
    const g = JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> };
    it(g.name, () => expect(call(g.request)).toEqual(g.response));
  }
});

describe("awaitRemote with fake providers", () => {
  const run = (provider: "github" | "circleci", state: LaneRun["state"], sha = SHA): LaneRun => ({ provider, sha, laneId: "land", laneDigest: DIGEST, state });
  const fake = (provider: "github" | "circleci", states: LaneRun["state"][], started: string[] = []): Adapter => {
    let i = 0;
    return {
      provider,
      async start() { started.push(provider); return { provider, branch: `ci/${provider}`, marker: MARKER }; },
      async poll() { return { run: run(provider, states[Math.min(i++, states.length - 1)]!) }; },
    };
  };
  const base = (adapters: Partial<Record<"github" | "circleci", Adapter>>, allow: ("github" | "circleci")[], localOk = true) => ({
    call, adapters, allow, ctx: { task: "t", mergeSha: SHA, want }, local: Promise.resolve(localOk), log: () => {}, span: () => {}, sliceS: 0.05, deadlineS: 30,
  });
  it("github running then pass: accept, one push", async () => {
    const started: string[] = [];
    const o = await awaitRemote(base({ github: fake("github", ["running", "pass"], started) }, ["github"]));
    expect(o.verdict.kind).toBe("accept");
    expect(started).toEqual(["github"]);
  });
  it("github pass + circleci fail: refuse", async () => {
    const o = await awaitRemote(base({ github: fake("github", ["pass"]), circleci: fake("circleci", ["fail"]) }, ["circleci", "github"]));
    expect(o.verdict).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
  it("github unavailable, circleci passes: the next provider is tried and accepted", async () => {
    const started: string[] = [];
    const o = await awaitRemote(base({ github: fake("github", ["unavailable"], started), circleci: fake("circleci", ["pass"], started) }, ["github", "circleci"]));
    expect(o.verdict.kind).toBe("accept");
    expect(started).toEqual(["github", "circleci"]);
  });
  it("a provider whose run binds to another sha is started once, then the land runs the tier locally", async () => {
    const started: string[] = [];
    const wrong: Adapter = { provider: "github", async start() { started.push("github"); return { provider: "github", branch: "b", marker: MARKER }; }, async poll() { return { run: run("github", "pass", "c".repeat(40)) }; } };
    const o = await awaitRemote(base({ github: wrong }, ["github"]));
    expect(started).toEqual(["github"]);
    expect(o.verdict.kind).toBe("local");
  });
  it("the CircleCI stub is unavailable, so the land falls back", async () => {
    const o = await awaitRemote(base({ circleci: circleciAdapter(() => false) }, ["circleci"]));
    expect(o.verdict.kind).toBe("local");
  });
  it("a start that throws is unavailable", async () => {
    const bad: Adapter = { provider: "github", async start() { throw new Error("push refused"); }, async poll() { throw new Error("unused"); } };
    const o = await awaitRemote(base({ github: bad }, ["github"]));
    expect(o.verdict.kind).toBe("local");
  });
  it("branch names are unique per commit", () => {
    expect(landBranch("t", SHA)).toBe("ci/land-t-aaaaaaa");
    expect(landBranch("t", "b".repeat(40))).not.toBe(landBranch("t", SHA));
  });
});

describe("fw checks --tier remote prints the lane digest", () => {
  it("LANE digest= is the fwcore digest of the listed remote ids", async () => {
    const out: string[] = [];
    const code = await checksCli(["--affected", "--base", "HEAD", "--tier", "remote", "--list"], root, { core: call, changed: ["apps/runner/src/land.ts"], log: (l) => out.push(l) });
    expect(code).toBe(0);
    const ids = out.filter((l) => l.startsWith("remote ")).map((l) => l.slice(7));
    expect(ids.length).toBeGreaterThan(0);
    expect(out).toContain(`LANE digest=${remoteDigest(call, ids)}`);
  });
  it("the local tier prints no lane digest", async () => {
    const out: string[] = [];
    await checksCli(["--affected", "--base", "HEAD", "--tier", "local", "--list"], root, { core: call, changed: ["apps/runner/src/land.ts"], log: (l) => out.push(l) });
    expect(out.some((l) => l.startsWith("LANE "))).toBe(false);
  });
});
