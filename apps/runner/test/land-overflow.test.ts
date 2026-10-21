// land-lane-circleci: GitHub first, CircleCI for the legs GitHub has no slot for. The rule is Lean Fw.Ci.Overflow (golden
// packages/contracts/golden/ci/overflow.jsonl, replayed here through fwcore); the rest is glue, checked with fake providers.
import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { awaitGroups, circleciAdapter, githubAdapter, legsCovered, makePusher, markerMessage, normalizeCircle, remoteDigest, runTiered, type Adapter, type CircleDeps, type CircleLane, type GhRunView, type LaneRun, type StartCtx, type Want } from "../src/land-remote.ts";
import { ccStatusFrom, planOverflow, readSlots, type OverflowDeps } from "../src/land-overflow.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const SHA = "a".repeat(40);
const MARKER = "b".repeat(40);
const LEGS = readFileSync(join(root, "lean", "land-legs.txt"), "utf8").split(/\s+/).filter(Boolean);
const DIGEST = remoteDigest(call, ["apps/runner", "packages/gh-budget"]);
const want: Want = { sha: SHA, laneId: "land", laneDigest: DIGEST };

describe("the Lean golden, replayed through fwcore", () => {
  const lines = readFileSync(join(root, "packages/contracts/golden/ci/overflow.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as { op: string; name: string; request: Record<string, unknown>; response: Record<string, unknown> });
  it("has rows for both ops", () => {
    expect(new Set(lines.map((l) => l.op))).toEqual(new Set(["ci.overflow", "ci.overflowCombine"]));
  });
  for (const l of lines) {
    it(`${l.op}: ${l.name}`, () => {
      let got: Record<string, unknown>;
      try { got = call({ op: l.op, ...l.request }); } catch (e) { got = { error: (e as Error).message.replace(/^fwcore [\w.]+: /, "") }; }
      expect(got).toEqual(l.response);
    });
  }
  it("the legs of the golden are the legs of lean/land-legs.txt", () => {
    const first = lines.find((l) => l.op === "ci.overflow")!;
    expect(first.request.legs).toEqual(LEGS);
  });
});

describe("the width table covers every workflow", () => {
  const lean = readFileSync(join(root, "lean/Fw/Ci/Overflow.lean"), "utf8");
  const block = /def widths[\s\S]*?\]\n/.exec(lean)![0];
  const rows = new Map([...block.matchAll(/\("([a-z0-9-]+)", (\d+)\)/g)].map((m) => [m[1]!, Number(m[2])]));
  const names = readdirSync(join(root, ".github/workflows")).filter((f) => f.endsWith(".yml")).map((f) => /^name:\s*(\S+)/m.exec(readFileSync(join(root, ".github/workflows", f), "utf8"))![1]!);
  it("every workflow name has a row, and every row names a workflow", () => {
    expect([...rows.keys()].sort()).toEqual([...names].sort());
  });
  it("fwcore counts one run of a workflow as its row says", () => {
    for (const n of names) {
      const r = call({ op: "ci.overflow", legs: LEGS, ghActive: [n], ghActions: "operational", ghPrev: false, ccArm: "unknown", ccReadAt: null, now: 1, spent: 0, storage: 0, keys: null, checkout: null, forceFull: false }) as { ghFree: number };
      expect(r.ghFree, n).toBe(Math.max(0, 20 - rows.get(n)!));
    }
  });
});

describe("the legs of land.yml are the legs of the overflow", () => {
  it("the workflow matrix lists exactly lean/land-legs.txt", () => {
    const yml = readFileSync(join(root, ".github/workflows/land.yml"), "utf8");
    expect(/^\s+leg: \[(.*)\]$/m.exec(yml)![1]!.split(/,\s*/)).toEqual(LEGS);
  });
});

const baseDeps = (over: Partial<OverflowDeps> = {}, counts = { cc: 0, keys: 0 }): OverflowDeps => ({
  call, legs: LEGS, now: () => 1_060_000, forceFull: false,
  slots: async () => ({ active: [], ageS: 0 }),
  ghStatus: async () => ({ actions: "operational", prevDegraded: false }),
  ccStatus: async () => { counts.cc++; return { arm: "healthy", readAt: 1_000_000 }; },
  keys: async () => { counts.keys++; return { keys: 1, checkout: null }; },
  budget: () => ({ spent: 0, storage: 0 }),
  ...over,
});

describe("planOverflow", () => {
  it("calm: every leg stays on GitHub and CircleCI is not asked", async () => {
    const counts = { cc: 0, keys: 0 };
    const p = await planOverflow(baseDeps({}, counts));
    expect(p).toMatchObject({ gh: LEGS, cc: [], reason: "github-first" });
    expect(counts).toEqual({ cc: 0, keys: 0 });
  });
  it("GitHub full (the test flag) and CircleCI ready: every leg goes to CircleCI", async () => {
    const p = await planOverflow(baseDeps({ forceFull: true }));
    expect(p).toMatchObject({ gh: [], cc: LEGS, reason: "github-full" });
    expect(p!.note).toMatch(/forced full/);
  });
  it("a partly full GitHub keeps the first legs", async () => {
    const p = await planOverflow(baseDeps({ slots: async () => ({ active: ["visual-diff", "snapshot-extract", "trajectory-probe"], ageS: 90 }) }));
    expect(p).toMatchObject({ gh: LEGS.slice(0, 3), cc: LEGS.slice(3), reason: "github-full" });
    expect(p!.note).toMatch(/90 s old/);
  });
  it("the slot count cannot be read: GitHub first", async () => {
    expect(await planOverflow(baseDeps({ slots: async () => ({ active: null, ageS: 0 }) }))).toMatchObject({ gh: LEGS, cc: [] });
    expect(await planOverflow(baseDeps({ slots: async () => { throw new Error("403"); } }))).toMatchObject({ gh: LEGS, cc: [] });
  });
  it("CircleCI is not usable (status stale, status unreadable, key missing, key list unreadable): stay on GitHub", async () => {
    for (const over of [
      { ccStatus: async () => ({ arm: "healthy", readAt: 100 }) },
      { ccStatus: async () => { throw new Error("console down"); } },
      { keys: async () => ({ keys: 0, checkout: null }) },
      { keys: async () => { throw new Error("no token"); } },
      { budget: () => ({ spent: 399_000, storage: 0 }) },
      { budget: () => ({ spent: 0, storage: 2000 }) },
    ] as Partial<OverflowDeps>[]) {
      const p = await planOverflow(baseDeps({ forceFull: true, ...over }));
      expect(p, JSON.stringify(Object.keys(over))).toMatchObject({ gh: LEGS, cc: [] });
    }
  });
  it("GitHub Actions degraded: every leg goes to CircleCI", async () => {
    const p = await planOverflow(baseDeps({ ghStatus: async () => ({ actions: "partial_outage", prevDegraded: false }) }));
    expect(p).toMatchObject({ gh: [], cc: LEGS, reason: "github-degraded" });
  });
});

describe("readSlots: one gh call, cached, no retry", () => {
  const rows = JSON.stringify([{ status: "in_progress", workflowName: "visual-diff", databaseId: 1 }, { status: "completed", workflowName: "land", databaseId: 2 }, { status: "queued", workflowName: "wktr", databaseId: 3 }]);
  it("counts the runs that are queued or running, once per TTL", async () => {
    const dir = mkdtempSync(join(tmpdir(), "slots-"));
    const file = join(dir, "slots.json");
    const calls: string[][] = [];
    const gh = async (a: string[]) => { calls.push(a); return rows; };
    let t = 1_000_000;
    expect(await readSlots(gh, () => t, file)).toEqual({ active: ["visual-diff", "wktr"], ageS: 0 });
    t += 60_000;
    expect(await readSlots(gh, () => t, file)).toEqual({ active: ["visual-diff", "wktr"], ageS: 60 });
    expect(calls.length).toBe(1);
    expect(calls[0]).toEqual(["run", "list", "--limit", "100", "--json", "status,workflowName,databaseId"]);
    t += 61_000;
    await readSlots(gh, () => t, file);
    expect(calls.length).toBe(2);
  });
  it("a refused call is unknown and is not retried", async () => {
    let n = 0;
    const r = await readSlots(async () => { n++; throw new Error("HTTP 403"); }, () => 1, undefined);
    expect(r.active).toBeNull();
    expect(n).toBe(1);
  });
  it("an unreadable cache file is no cache", async () => {
    const dir = mkdtempSync(join(tmpdir(), "slots-"));
    const file = join(dir, "slots.json");
    writeFileSync(file, "not json");
    expect((await readSlots(async () => rows, () => 5, file)).active).toEqual(["visual-diff", "wktr"]);
  });
});

describe("ccStatusFrom reads the console's view", () => {
  it("takes the arm verdict and the read time, and anything else is unknown", async () => {
    expect(await ccStatusFrom(async () => ({ status: 200, body: { readAt: 5, arm: { verdict: "healthy", usable: true } } }))).toEqual({ arm: "healthy", readAt: 5 });
    expect(await ccStatusFrom(async () => ({ status: 404, body: {} }))).toEqual({ arm: "unknown", readAt: null });
    expect(await ccStatusFrom(async () => ({ status: 200, body: { readAt: null } }))).toEqual({ arm: "unknown", readAt: null });
  });
});

describe("the marker commit both providers share", () => {
  const split = (gh: string[], cc: string[]) => ({ all: LEGS, gh, cc });
  const ctx = (legs?: StartCtx["legs"]): StartCtx => ({ task: "t", mergeSha: SHA, want, ...(legs ? { legs } : {}) });
  it("a land with no overflow keeps the message it always had", () => {
    expect(markerMessage(ctx())).toBe(`[ci:land] land t ${SHA.slice(0, 7)}`);
    expect(markerMessage(ctx(split(LEGS, [])))).toBe(`[ci:land] land t ${SHA.slice(0, 7)}`);
  });
  it("a partial GitHub set names its legs; a CircleCI-only land does not start the GitHub lane", () => {
    expect(markerMessage(ctx(split(["check-sh", "suites-a"], LEGS.slice(2))))).toBe(`[ci:land] land t ${SHA.slice(0, 7)} [legs:check-sh,suites-a]`);
    expect(markerMessage(ctx(split([], LEGS)))).not.toMatch(/\[ci:land\]/);
  });
  it("two adapters push once and see one marker", async () => {
    const calls: string[][] = [];
    const git = (a: string[]) => { calls.push(a); return a[0] === "commit-tree" ? "c".repeat(40) : "tree"; };
    const push = makePusher({ git });
    const c = ctx(split(["check-sh"], LEGS.slice(1)));
    const [x, y] = await Promise.all([push(c), push(c)]);
    expect(x).toEqual(y);
    expect(calls.filter((a) => a[0] === "push").length).toBe(1);
    expect(calls.find((a) => a[0] === "commit-tree")!.slice(-1)[0]).toMatch(/\[legs:check-sh\]/);
  });
  it("a refused scan fails both", async () => {
    const push = makePusher({ git: () => "x", scan: () => "an email" });
    await expect(push(ctx())).rejects.toThrow(/scan refused/);
  });
});

const lane = (leg: string, over: Partial<CircleLane> = {}): CircleLane => ({ job: `land-${leg}`, conclusion: "pass", leg, sha: SHA, digest: DIGEST, engine: "false", rc: 0, ...over });

describe("normalizeCircle", () => {
  const legs = ["suites-a", "chromium"];
  const f = (lanes: CircleLane[], sha = MARKER) => ({ sha, lanes });
  const n = (state: LaneRun["state"], fetched: ReturnType<typeof f> | null) => normalizeCircle(call, state, fetched, { marker: MARKER, want, legs });
  it("a pass of every leg binds to the sha and digest the legs printed", () => {
    expect(n("pass", f(legs.map((l) => lane(l))))).toEqual({ provider: "circleci", sha: SHA, laneId: "land", laneDigest: DIGEST, state: "pass" });
  });
  it("a missing leg, a failed leg or another commit does not pass", () => {
    expect(n("pass", f([lane("suites-a")])).state).toBe("fail");
    expect(n("pass", f([lane("suites-a"), lane("chromium", { rc: 1 })])).state).toBe("fail");
    expect(n("pass", f([lane("suites-a"), lane("chromium", { conclusion: "fail" })])).state).toBe("fail");
    expect(n("pass", f(legs.map((l) => lane(l)), "d".repeat(40)))).toMatchObject({ state: "pass", sha: "", laneDigest: "" });
  });
  it("legs that disagree on the digest or the sha bind to nothing", () => {
    expect(n("pass", f([lane("suites-a"), lane("chromium", { digest: "other" })]))).toMatchObject({ sha: "", laneDigest: "" });
    expect(n("pass", f([lane("suites-a"), lane("chromium", { sha: "e".repeat(40) })]))).toMatchObject({ sha: "", laneDigest: "" });
  });
  it("a failure is attributed to what was asked for, and a pass with no record binds to nothing", () => {
    expect(n("fail", null)).toMatchObject({ state: "fail", sha: SHA, laneDigest: DIGEST });
    expect(n("pass", null)).toMatchObject({ state: "pass", sha: "", laneDigest: "" });
    expect(n("running", null)).toMatchObject({ state: "running", sha: SHA });
  });
});

const circleDeps = (over: Partial<CircleDeps> = {}, log: string[] = []): CircleDeps => ({
  call,
  push: async () => ({ branch: "ci/land-t", marker: MARKER }),
  trigger: async (branch, legs) => { log.push(`trigger ${branch} ${legs.join(",")}`); return "p1"; },
  wait: async () => 0,
  fetch: async () => ({ sha: MARKER, lanes: ["suites-a", "chromium"].map((l) => lane(l)), times: { queueMs: 1000, laneMs: 60000 } }),
  ...over,
});
const ccCtx: StartCtx = { task: "t", mergeSha: SHA, want, legs: { all: LEGS, gh: LEGS.filter((l) => l !== "suites-a" && l !== "chromium"), cc: ["suites-a", "chromium"] } };

describe("circleciAdapter", () => {
  it("starts one pipeline for the CircleCI legs on the shared branch", async () => {
    const log: string[] = [];
    const h = await circleciAdapter(circleDeps({}, log)).start(ccCtx);
    expect(h).toEqual({ provider: "circleci", branch: "ci/land-t", marker: MARKER, pipelineId: "p1" });
    expect(log).toEqual(["trigger ci/land-t suites-a,chromium"]);
  });
  it("refuses to start with no leg for it", async () => {
    await expect(circleciAdapter(circleDeps()).start({ ...ccCtx, legs: { all: LEGS, gh: LEGS, cc: [] } })).rejects.toThrow(/no leg/);
  });
  it("a pipeline still going is running; a finished pass is bound; a fail is a fail", async () => {
    const h = { provider: "circleci" as const, branch: "ci/land-t", marker: MARKER, pipelineId: "p1" };
    expect((await circleciAdapter(circleDeps({ wait: async () => 3 })).poll(h, ccCtx, 1)).run.state).toBe("running");
    const pass = await circleciAdapter(circleDeps()).poll(h, ccCtx, 1);
    expect(pass.run).toMatchObject({ state: "pass", sha: SHA, laneDigest: DIGEST });
    expect(pass.times).toMatchObject({ queueMs: 1000, laneMs: 60000 });
    expect((await circleciAdapter(circleDeps({ wait: async () => 1 })).poll(h, ccCtx, 1)).run.state).toBe("fail");
    expect((await circleciAdapter(circleDeps({ wait: async () => 5 })).poll(h, ccCtx, 1)).run.state).toBe("unavailable");
  });
  it("a record that cannot be read leaves a pass unbound and says why", async () => {
    const h = { provider: "circleci" as const, branch: "b", marker: MARKER, pipelineId: "p1" };
    const p = await circleciAdapter(circleDeps({ fetch: async () => { throw new Error("404"); } })).poll(h, ccCtx, 1);
    expect(p.run).toMatchObject({ state: "pass", sha: "", laneDigest: "" });
    expect(p.note).toMatch(/not read/);
  });
});

/** An adapter that answers with the given states, for the groups. */
const fakeProvider = (provider: "github" | "circleci", states: LaneRun["state"][], started: StartCtx[] = [], sha = SHA): Adapter => {
  let i = 0;
  return {
    provider,
    async start(c) { started.push(c); return { provider, branch: "ci/land-t", marker: MARKER }; },
    async poll() { return { run: { provider, sha, laneId: "land", laneDigest: DIGEST, state: states[Math.min(i++, states.length - 1)]! } }; },
  };
};
const groupIn = (adapters: Partial<Record<"github" | "circleci", Adapter>>, gh: string[], cc: string[], localOk = true) => ({
  call, adapters, ctx: { task: "t", mergeSha: SHA, want }, split: { all: LEGS, gh, cc }, local: Promise.resolve(localOk), log: () => {}, span: () => {}, sliceS: 0.02, deadlineS: 30,
});

describe("awaitGroups: each provider's legs are waited for on their own, fwcore combines", () => {
  const gh3 = LEGS.slice(0, 3), cc2 = LEGS.slice(3);
  it("both groups pass: accept, and each provider was started with the split", async () => {
    const started: StartCtx[] = [];
    const o = await awaitGroups(groupIn({ github: fakeProvider("github", ["running", "pass"], started), circleci: fakeProvider("circleci", ["pass"], started) }, gh3, cc2));
    expect(o.verdict.kind).toBe("accept");
    expect(started.map((c) => c.legs)).toEqual([{ all: LEGS, gh: gh3, cc: cc2 }, { all: LEGS, gh: gh3, cc: cc2 }]);
  });
  it("one group fails: refuse", async () => {
    const o = await awaitGroups(groupIn({ github: fakeProvider("github", ["pass"]), circleci: fakeProvider("circleci", ["fail"]) }, gh3, cc2));
    expect(o.verdict).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
  });
  it("a group that is unavailable: the land runs the remote tier on this Mac", async () => {
    const dead: Adapter = { provider: "circleci", async start() { throw new Error("no key"); }, async poll() { throw new Error("unused"); } };
    const o = await awaitGroups(groupIn({ github: fakeProvider("github", ["pass"]), circleci: dead }, gh3, cc2));
    expect(o.verdict.kind).toBe("local");
  });
  it("a CircleCI group alone with a pass bound to the wrong sha does not accept", async () => {
    const o = await awaitGroups(groupIn({ circleci: fakeProvider("circleci", ["pass"], [], "c".repeat(40)) }, [], LEGS));
    expect(o.verdict.kind).not.toBe("accept");
  });
  it("the same bound pass is judged alike on either provider (Lean verdict_same)", async () => {
    const g = await awaitGroups(groupIn({ github: fakeProvider("github", ["pass"]) }, LEGS, []));
    const c = await awaitGroups(groupIn({ circleci: fakeProvider("circleci", ["pass"]) }, [], LEGS));
    expect(g.verdict.kind).toBe(c.verdict.kind);
    expect(g.verdict.kind).toBe("accept");
  });
  it("a failed local tier refuses whatever the providers say", async () => {
    const o = await awaitGroups(groupIn({ github: fakeProvider("github", ["pass"]), circleci: fakeProvider("circleci", ["pass"]) }, gh3, cc2, false));
    expect(o.verdict).toMatchObject({ kind: "refuse", reason: "local-tier-failed" });
  });
});

describe("runTiered with an overflow plan", () => {
  const ids = ["apps/runner", "packages/gh-budget"];
  const plan = (gh: string[], cc: string[]) => ({ legs: LEGS, plan: async () => ({ gh, cc, reason: "github-full", note: "test" }) });
  const run = async (overflow: ReturnType<typeof plan> | undefined, adapters: Partial<Record<"github" | "circleci", Adapter>>) => {
    const logs: string[] = [];
    let localRuns = 0;
    const r = await runTiered({
      call, checks: ids.map((id) => ({ id, argv: [id] })), laneIds: ids, task: "t", mergeSha: SHA, adapters, allow: ["github"], overflow,
      runLocal: async () => { localRuns++; return { bad: null, kind: "checks" }; }, log: (l) => logs.push(l), span: () => {}, sliceS: 0.02, deadlineS: 30,
    });
    return { r, logs, localRuns };
  };
  it("a plan with no CircleCI leg is the all-GitHub land: one push, no legs in the context", async () => {
    const started: StartCtx[] = [];
    const o = await run(plan(LEGS, []), { github: fakeProvider("github", ["pass"], started) });
    expect(o.r.bad).toBeNull();
    expect(started.map((c) => c.legs)).toEqual([undefined]);
  });
  it("legs on both providers pass: the land proceeds, the local tier ran once", async () => {
    const started: StartCtx[] = [];
    const o = await run(plan(LEGS.slice(0, 3), LEGS.slice(3)), { github: fakeProvider("github", ["pass"], started), circleci: fakeProvider("circleci", ["pass"], started) });
    expect(o.r.bad).toBeNull();
    expect(started.length).toBe(2);
    expect(o.logs.some((l) => /^remote: overflow github-full: GitHub check-sh,suites-a,suites-b, CircleCI chromium,playwright-webkit/.test(l))).toBe(true);
    expect(o.localRuns).toBe(1);
  });
  it("every leg on CircleCI: only CircleCI is started", async () => {
    const started: StartCtx[] = [];
    const gh = fakeProvider("github", ["pass"], started);
    const o = await run(plan([], LEGS), { github: gh, circleci: fakeProvider("circleci", ["pass"], started) });
    expect(o.r.bad).toBeNull();
    expect(started.length).toBe(1);
    expect(started[0]!.legs!.gh).toEqual([]);
  });
  it("a CircleCI leg that fails refuses the land", async () => {
    const o = await run(plan(LEGS.slice(0, 3), LEGS.slice(3)), { github: fakeProvider("github", ["pass"]), circleci: fakeProvider("circleci", ["fail"]) });
    expect(o.r.bad).toMatch(/the land lane failed/);
  });
  it("a plan that cannot be made is the all-GitHub land", async () => {
    const started: StartCtx[] = [];
    const o = await run({ legs: LEGS, plan: async () => { throw new Error("boom"); } } as never, { github: fakeProvider("github", ["pass"], started) });
    expect(o.r.bad).toBeNull();
    expect(o.logs.some((l) => /overflow plan not made/.test(l))).toBe(true);
    expect(started.map((c) => c.legs)).toEqual([undefined]);
  });
});

describe("a land that gave GitHub only some legs passes only with a job for each", () => {
  const gh = ["check-sh", "suites-a"];
  const split = { all: LEGS, gh, cc: LEGS.slice(2) };
  const job = (leg: string, ok = true) => ({ name: `land (${leg})`, conclusion: ok ? "success" : "failure", steps: [{ name: `lane: sha=${SHA} digest=${DIGEST}`, conclusion: "success" }] });
  const view = (jobs: { name: string; conclusion: string; steps?: { name: string; conclusion: string }[] }[]): GhRunView => ({ workflowName: "land", headSha: MARKER, conclusion: "success", status: "completed", jobs: [{ name: "guard", conclusion: "success" }, ...jobs] });
  const adapter = (v: GhRunView, cache?: GhRunView) => githubAdapter({
    call, git: () => MARKER, wait: async () => ({ code: 0, out: "run 7 x" }),
    gh: async (a) => (a[1] === "list" ? JSON.stringify([{ databaseId: 7 }]) : JSON.stringify(v)),
    ...(cache ? { cache: () => cache } : {}),
  });
  const poll = (a: Adapter, legs = split) => a.poll({ provider: "github", branch: "b", marker: MARKER }, { task: "t", mergeSha: SHA, want, legs }, 1);
  it("legsCovered reads the matrix job names", () => {
    expect(legsCovered(view([job("check-sh"), job("suites-a")]), gh)).toBe(true);
    expect(legsCovered(view([job("check-sh")]), gh)).toBe(false);
    expect(legsCovered(null, gh)).toBe(false);
  });
  it("every leg given to GitHub has a passing job: pass", async () => {
    expect((await poll(adapter(view([job("check-sh"), job("suites-a")])))).run).toMatchObject({ state: "pass", sha: SHA, laneDigest: DIGEST });
  });
  it("a job missing: fail, with the reason", async () => {
    const p = await poll(adapter(view([job("check-sh")])));
    expect(p.run.state).toBe("fail");
    expect(p.note).toMatch(/no job for every leg/);
  });
  it("the poller's cached record cannot show the legs, so a pass is read from gh", async () => {
    const cached = view([{ name: "lane", conclusion: "success", steps: [{ name: `lane: sha=${SHA} digest=${DIGEST}`, conclusion: "success" }] }]);
    const p = await poll(adapter(view([job("check-sh"), job("suites-a")]), cached));
    expect(p.run.state).toBe("pass");
  });
  it("a land with every leg on GitHub is judged as before", async () => {
    const p = await poll(adapter(view([job("check-sh")])), { all: LEGS, gh: LEGS, cc: [] });
    expect(p.run.state).toBe("pass");
  });
});
