import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { githubAdapter, laneStateOf, landBranch, normalizeGithub, remoteDigest, remoteVerdict, awaitRemote, laneBind, circleciAdapter, type Adapter, type GhRunView, type LaneRun, type Want } from "../src/land-remote.ts";
import { fwcoreCall } from "../src/run.ts";
import { checksCli } from "../src/checks.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const SHA = "a".repeat(40);
const MARKER = "b".repeat(40);
const DIGEST = remoteDigest(call, ["apps/runner", "packages/gh-budget"]);
const want: Want = { sha: SHA, laneId: "land", laneDigest: DIGEST };
const ctx = { marker: MARKER, want };

const recorded = (name: string): GhRunView => JSON.parse(readFileSync(join(root, "apps/runner/test/fixtures/land-remote", name), "utf8")) as GhRunView;
const passView = (sha = SHA, digest = DIGEST): GhRunView => ({
  headSha: MARKER, conclusion: "success", status: "completed",
  createdAt: "2026-10-20T10:00:00Z", startedAt: "2026-10-20T10:00:10Z", updatedAt: "2026-10-20T10:05:10Z",
  jobs: [{ name: "land", status: "completed", conclusion: "success", steps: [{ name: "suites (the remote tier of the Lean-selected checks)", conclusion: "success" }, { name: `lane: sha=${sha} digest=${digest}`, conclusion: "success" }] }],
});
const norm = (code: number, view: GhRunView | null, c: { marker: string; want: Want }, out = "") => normalizeGithub(laneStateOf(call, code, out, view), view, c);
const verdictOf = (runs: LaneRun[], o: Partial<{ localOk: boolean; needed: boolean; allow: ("github" | "circleci")[]; waitsLeft: number }> = {}) =>
  remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want, waitsLeft: 0, runs, ...o });

describe("normalize a GitHub land run, then ask fwcore", () => {
  it("pass bound to the sha and digest: accept", () => {
    const run = norm(0, passView(), ctx);
    expect(run).toEqual({ provider: "github", sha: SHA, laneId: "land", laneDigest: DIGEST, state: "pass" });
    expect(verdictOf([run])).toMatchObject({ kind: "accept", ok: true, reason: "remote-pass" });
  });
  it("fail: refuse", () => {
    const run = norm(1, { ...passView(), conclusion: "failure" }, ctx);
    expect(verdictOf([run])).toMatchObject({ kind: "refuse", ok: false, reason: "remote-lane-failed" });
  });
  it("fail before the lane printed its binding still refuses", () => {
    const run = norm(1, { ...passView(), conclusion: "failure", jobs: [] }, ctx);
    expect(verdictOf([run])).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
  it("pass for another sha is not accepted", () => {
    const run = norm(0, passView("c".repeat(40)), ctx);
    expect(verdictOf([run]).ok).toBe(false);
    expect(verdictOf([run]).kind).not.toBe("accept");
  });
  it("pass for another suite list (digest) is not accepted", () => {
    const run = norm(0, passView(SHA, remoteDigest(call, ["apps/runner"])), ctx);
    expect(verdictOf([run]).kind).not.toBe("accept");
  });
  it("pass of another commit's run (headSha) binds to nothing", () => {
    const run = norm(0, { ...passView(), headSha: "d".repeat(40) }, ctx);
    expect(run.sha).toBe("");
    expect(verdictOf([run]).kind).not.toBe("accept");
  });
  it("pass without a lane step binds to nothing", () => {
    const run = norm(0, { ...passView(), jobs: [] }, ctx);
    expect(verdictOf([run]).kind).not.toBe("accept");
  });
  it("cancelled (fw ci wait exit 4): run the remote tier locally", () => {
    const run = norm(4, null, ctx);
    expect(run.state).toBe("cancelled");
    expect(verdictOf([run])).toMatchObject({ kind: "local", reason: "remote-cancelled-run-locally" });
  });
  it("exit 2 (a wait error) is running: wait until the deadline (land-wait-final)", () => {
    expect(norm(2, null, ctx).state).toBe("running");
  });
  it("unavailable (gh unavailable, exit 5): run locally when no provider is left", () => {
    const run = norm(5, null, ctx);
    expect(run.state).toBe("unavailable");
    expect(verdictOf([run])).toMatchObject({ kind: "local" });
  });
  it("still running (exit 3): wait", () => {
    expect(verdictOf([norm(3, null, ctx, "ci wait: timed out after 540s")])).toMatchObject({ kind: "wait", reason: "lane-running" });
  });
  it("github pass + circleci fail across providers: refuse", () => {
    const gh = norm(0, passView(), ctx);
    const cc: LaneRun = { provider: "circleci", sha: SHA, laneId: "land", laneDigest: DIGEST, state: "fail" };
    expect(verdictOf([gh, cc], { allow: ["github", "circleci"] })).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
    expect(verdictOf([cc, gh], { allow: ["github", "circleci"] })).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
  it("lane step names parse back to sha and digest", () => {
    expect(laneBind(passView())).toEqual({ sha: SHA, digest: DIGEST });
  });
  it("a local failure refuses even when the lane passed", () => {
    expect(verdictOf([norm(0, passView(), ctx)], { localOk: false })).toMatchObject({ kind: "refuse", reason: "local-tier-failed" });
  });
});

describe("a recorded lane run (live proof of task land-wait: ci/land-probe-30a307f, run 39317802669)", () => {
  const v = recorded("fail.json");
  const b = laneBind(v)!;
  const w: Want = { sha: b.sha, laneId: "land", laneDigest: b.digest };
  it("the lane's step name binds the run to the merge commit and its suite list", () => {
    expect(b.sha).toBe("30a307f82747ff8c632d14592134597220c66fe5");
    expect(b.digest).toBe(remoteDigest(call, ["apps/console-api", "apps/runner", "packages/engine-check", "packages/gate-breakpoints", "packages/gh-budget", "packages/measure-chromium"]));
  });
  it("fw ci wait exit 1 on it: a run bound to the sha, refused", () => {
    const run = norm(1, v, { marker: v.headSha, want: w });
    expect(run).toEqual({ provider: "github", sha: b.sha, laneId: "land", laneDigest: b.digest, state: "fail" });
    expect(remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want: w, waitsLeft: 0, runs: [run] })).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
  it("derived: the same record with conclusion success and exit 0 is accepted for its sha and not for another", () => {
    const run = norm(0, { ...v, conclusion: "success", jobs: v.jobs?.map((j) => ({ ...j, conclusion: "success" })) }, { marker: v.headSha, want: w });
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
    const run = norm(0, v, { marker: v.headSha, want: w });
    expect(run.state).toBe("pass");
    expect(remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want: w, waitsLeft: 0, runs: [run] })).toMatchObject({ kind: "accept", reason: "remote-pass" });
    expect(remoteVerdict(call, { localOk: true, needed: true, allow: ["github"], want: { ...w, sha: "e".repeat(40) }, waitsLeft: 0, runs: [run] }).kind).not.toBe("accept");
  });
});

describe("fw ci wait exit 3 and the empty binding (review round 1)", () => {
  it("exit 3 is running with or without `timed out after` (a stopped poller or a refused gh call is a wait error, polled again until the deadline)", () => {
    expect(laneStateOf(call, 3, "ci wait: timed out after 540s")).toBe("running");
    expect(laneStateOf(call, 3, "ci wait: poller stopped")).toBe("running");
    expect(laneStateOf(call, 3)).toBe("running");
    expect(laneStateOf(call, 5)).toBe("unavailable");
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
    const run = norm(1, empty, { marker: empty.headSha, want });
    expect(verdictOf([run])).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
});

describe("the personal-data scan before the ci/land push", () => {
  const mk = (hit: string | null) => {
    const calls: string[][] = [];
    const a = githubAdapter({ git: (args) => { calls.push(args); return "x".repeat(40); }, scan: () => hit, call, wait: async () => ({ code: 0, out: "" }), gh: async () => "" });
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
  it("a CircleCI trigger that is refused is unavailable, so the land falls back", async () => {
    const refused = circleciAdapter({ call, push: async () => ({ branch: "ci/b", marker: MARKER }), trigger: async () => { throw new Error("key check: missing"); }, wait: async () => 3, fetch: async () => { throw new Error("unused"); } });
    const o = await awaitRemote({ ...base({ circleci: refused }, ["circleci"]), ctx: { task: "t", mergeSha: SHA, want, legs: { all: ["a"], gh: [], cc: ["a"] } } });
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

describe("a completed bound failed lane run always refuses, whatever `fw ci wait` returned", () => {
  const failed = (): GhRunView => ({ ...passView(), conclusion: "failure" });
  const outs: Record<number, string> = { 0: "run 123 land success", 1: "run 123 land failure -> fail", 2: "wait: gh run view 123 --json jobs failed: boom", 3: "wait: no gh call for the jobs of run 123: refused (budget)", 4: "run 123 land failure -> not-run" };
  for (const code of [0, 1, 2, 3, 4]) {
    it(`waiter exit ${code}: fail, refuse remote-lane-failed`, () => {
      const run = norm(code, failed(), ctx, outs[code]);
      expect(run).toEqual({ provider: "github", sha: SHA, laneId: "land", laneDigest: DIGEST, state: "fail" });
      expect(verdictOf([run])).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
    });
  }
  type Other = { conclusion: string };
  const adapterFor = (code: number, out: string, other?: Other, land: GhRunView = failed(), cache?: (h: unknown, id?: string) => GhRunView | null) => {
    const ghCalls: string[][] = [];
    const a = githubAdapter({
      call, git: () => MARKER, wait: async () => ({ code, out }),
      gh: async (args) => {
        ghCalls.push(args);
        const landOnly = args.includes("--workflow") && args[args.indexOf("--workflow") + 1] === "land";
        if (args[1] === "list") return JSON.stringify(other && !landOnly ? [{ databaseId: 999 }, { databaseId: 123 }] : [{ databaseId: 123 }]);
        const id = args[2];
        if (id === "999") return JSON.stringify({ ...passView(), workflowName: "lean", conclusion: other!.conclusion });
        return JSON.stringify({ ...land, workflowName: "land" });
      },
      ...(cache ? { cache } : {}),
    });
    return { a, ghCalls };
  };
  const awaitWith = async (a: ReturnType<typeof adapterFor>["a"]) => {
    const logs: string[] = [];
    const o = await awaitRemote({ call, adapters: { github: a }, allow: ["github"], ctx: { task: "t", mergeSha: SHA, want }, local: Promise.resolve(true), log: (l) => logs.push(l), span: () => {}, sliceS: 0.05, deadlineS: 5, waitsLeft: 3 });
    return { o, logs };
  };
  it("the run list is filtered to the land workflow", async () => {
    const { a, ghCalls } = adapterFor(4, "wait: no id");
    await awaitWith(a);
    const list = ghCalls.find((c) => c[1] === "list")!;
    expect(list[list.indexOf("--workflow") + 1]).toBe("land");
  });
  it("another workflow's newest success never lets a failed land run fall back to local", async () => {
    const { a } = adapterFor(4, "wait: no id", { conclusion: "success" });
    const { o, logs } = await awaitWith(a);
    expect(o.verdict).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
    expect(logs.join("\n")).not.toMatch(/on this Mac/);
  });
  it("another workflow's newest failure never refuses a land whose own run passed", async () => {
    const { a } = adapterFor(0, "wait: no id", { conclusion: "failure" }, passView());
    const { o } = await awaitWith(a);
    expect(o.verdict).not.toMatchObject({ reason: "remote-lane-failed" });
    expect(o.verdict.kind).toBe("accept");
  });
  it("a view of another workflow is not used even when asked for by id", async () => {
    const { a } = adapterFor(4, "run 999 something", { conclusion: "failure" });
    const { o } = await awaitWith(a);
    expect(o.verdict).not.toMatchObject({ reason: "remote-lane-failed" });
  });
  it("cached waiter facts decide before any gh call", async () => {
    const cached = { ...failed(), workflowName: "land" };
    const { a, ghCalls } = adapterFor(3, "wait: no gh call for the jobs of run 123: refused (budget)", undefined, failed(), () => cached);
    const { o } = await awaitWith(a);
    expect(o.verdict).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
    expect(ghCalls).toEqual([]);
  });
  it("extra gh calls carry the slice deadline and the abort signal", async () => {
    const seen: unknown[] = [];
    const a = githubAdapter({ call, git: () => MARKER, wait: async () => ({ code: 4, out: "run 123 x" }), gh: async (args, o) => { seen.push(o); return JSON.stringify({ ...failed(), workflowName: "land" }); } });
    await a.poll({ provider: "github", branch: "b", marker: MARKER }, { task: "t", mergeSha: SHA, want }, 5, new AbortController().signal);
    expect(seen[0]).toMatchObject({ deadline: expect.any(Number), signal: expect.anything() });
  });
  it("budget refused and no cached record: the wait error keeps waiting (running) and the reason is logged", async () => {
    const a = githubAdapter({ call, git: () => MARKER, wait: async () => ({ code: 3, out: "wait: no gh call for the jobs of run 123: refused" }), gh: async () => { throw new Error("gh run view not made: the request budget says stop"); } });
    const p = await a.poll({ provider: "github", branch: "b", marker: MARKER }, { task: "t", mergeSha: SHA, want }, 5);
    expect(p.run.state).toBe("running");
    expect(p.note).toMatch(/land run record not read/);
  });
  it("incident run 39338755874: waiter exit 4 (not-run) on a failed land run refuses", async () => {
    const { a } = adapterFor(4, "run 39338755874 land failure -> not-run");
    const { o } = await awaitWith(a);
    expect(o.verdict).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
  for (const code of [0, 1, 2, 3, 4]) {
    for (const withId of [true, false]) {
      it(`adapter, waiter exit ${code}, run id ${withId ? "in the output when it prints one" : "found by the branch listing"}: no fallback to the local tier`, async () => {
        const { a, ghCalls } = adapterFor(code, withId ? outs[code]! : "wait: something without an id");
        const logs: string[] = [];
        const o = await awaitRemote({
          call, adapters: { github: a }, allow: ["github"], ctx: { task: "t", mergeSha: SHA, want }, local: Promise.resolve(true),
          log: (l) => logs.push(l), span: () => {}, sliceS: 0.05, deadlineS: 5, waitsLeft: 3,
        });
        expect(o.verdict).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
        expect(o.verdict.kind).not.toBe("local");
        expect(logs.join("\n")).not.toMatch(/on this Mac/);
        expect(ghCalls.some((c) => c[0] === "run" && c[1] === "view")).toBe(true);
      });
    }
  }
  it("runTiered: the verdict line and a refusal, never a local run", async () => {
    const { a } = adapterFor(3, outs[3]!);
    const logs: string[] = [];
    let localRuns = 0;
    const { runTiered } = await import("../src/land-remote.ts");
    const ids = ["apps/runner", "packages/gh-budget"];
    const r = await runTiered({
      call, checks: ids.map((id) => ({ id, argv: [id] })), laneIds: ids, task: "t", mergeSha: SHA, adapters: { github: { ...a, async start() { return { provider: "github", branch: "b", marker: MARKER }; } } },
      allow: ["github"], runLocal: async () => { localRuns++; return { bad: null, kind: "checks" }; }, log: (l) => logs.push(l), span: () => {}, sliceS: 0.05, deadlineS: 5, waitsLeft: 3,
    });
    const tier = call({ op: "console.landTier", ids }) as { local: string[]; remote: string[] };
    expect(tier.remote.length).toBeGreaterThan(0);
    expect(r.bad).toMatch(/the land lane failed/);
    expect(logs.some((l) => /^remote: verdict refuse reason=remote-lane-failed/.test(l))).toBe(true);
    expect(logs.join("\n")).not.toMatch(/on this Mac/);
    expect(localRuns).toBe(1);
  });
});
