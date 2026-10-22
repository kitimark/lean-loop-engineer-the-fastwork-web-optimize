import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";
import { awaitGroups, circleciAdapter, githubAdapter, legsCovered, makePusher, markerMessage, normalizeCircle, remoteDigest, runTiered, type Adapter, type CircleDeps, type CircleLane, type GhRunView, type LaneRun, type StartCtx, type Want } from "../src/land-remote.ts";
import { ccStatusFrom, loadCircleci, planOverflow, readSlots, realCircle, type OverflowDeps } from "../src/land-overflow.ts";
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
  it("has rows for all three ops", () => {
    expect(new Set(lines.map((l) => l.op))).toEqual(new Set(["ci.overflow", "ci.overflowCombine", "ci.overflowSettle"]));
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
    const p = await planOverflow(baseDeps({ slots: async () => ({ active: ["engine-premises", "land", "wktr-fixtures"], ageS: 90 }) }));
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
      { budget: () => ({ spent: 0, storage: 1_000_000 }) },
    ] as Partial<OverflowDeps>[]) {
      const p = await planOverflow(baseDeps({ forceFull: true, ...over }));
      expect(p, JSON.stringify(Object.keys(over))).toMatchObject({ gh: LEGS, cc: [] });
    }
  });
  it("storage past the stop of 1000 goes to CircleCI while the budget fits; the overage refuses only past the pool", async () => {
    for (const storage of [1297, 2000, 100_000])
      expect(await planOverflow(baseDeps({ forceFull: true, budget: () => ({ spent: 819, storage }) }))).toMatchObject({ gh: [], cc: LEGS, reason: "github-full" });
    expect(await planOverflow(baseDeps({ forceFull: true, budget: () => ({ spent: 319_550, storage: 1765 }) }))).toMatchObject({ cc: LEGS });
    expect(await planOverflow(baseDeps({ forceFull: true, budget: () => ({ spent: 319_550, storage: 3765 }) }))).toMatchObject({ gh: LEGS, cc: [], reason: "circleci-storage" });
  });
  it("GitHub Actions degraded: every leg goes to CircleCI", async () => {
    const p = await planOverflow(baseDeps({ ghStatus: async () => ({ actions: "partial_outage", prevDegraded: false }) }));
    expect(p).toMatchObject({ gh: [], cc: LEGS, reason: "github-degraded" });
  });
});

describe("the land-lane wait applies Lean landStops: no storage stop after budgetFits admitted the legs", () => {
  it("ledger at 1297, forceFull: the legs go to CircleCI, the wait cancels nothing and returns the pipeline's code", async () => {
    const tmp = mkdtempSync(join(tmpdir(), "fw-land-cc-"));
    mkdirSync(join(tmp, "scripts"));
    mkdirSync(join(tmp, ".local"));
    writeFileSync(join(tmp, "scripts", "circleci.mjs"), `export * from ${JSON.stringify(pathToFileURL(join(root, "scripts", "circleci.mjs")).href)};\n`);
    const m = (await loadCircleci(tmp)) as Awaited<ReturnType<typeof loadCircleci>> & {
      loadFixture: (n: string) => { slug: string; pipelineId: string; api: { routes: Record<string, unknown> } };
      fixtureFetch: (api: unknown) => (u: string, i?: { method?: string }) => Promise<unknown>;
    };
    const fx = m.loadFixture("premise-tests");
    writeFileSync(join(tmp, ".local", "circleci.json"), JSON.stringify({ slug: fx.slug, definitionId: "def" }));
    writeFileSync(join(tmp, ".local", "circleci-ledger.json"), JSON.stringify({ pipelines: { old: { cache: 2_594_000_000, at: Date.now() - 86_400_000 } } }));
    const calls: string[] = [];
    const wf = Object.keys(fx.api.routes).map((k) => /^GET \/workflow\/([^/]+)\/job$/.exec(k)?.[1]).find(Boolean);
    const base = m.fixtureFetch({ ...fx.api, routes: { ...fx.api.routes, [`POST /workflow/${wf}/cancel`]: {} } });
    const fetchFn = async (u: string, i?: { method?: string }) => { calls.push(`${i?.method ?? "GET"} ${u}`); return base(u, i); };
    const cc = await realCircle(tmp, join(tmp, "out"), () => {}, { fetchFn, getToken: () => "t" });
    expect(cc.budget().storage).toBe(1297);
    expect(await planOverflow(baseDeps({ forceFull: true, budget: cc.budget }))).toMatchObject({ gh: [], cc: LEGS, reason: "github-full" });
    const deps = cc.deps(call, (async () => { throw new Error("no push"); }) as never);
    expect(await deps.wait(fx.pipelineId, 3600)).toBe(0);
    expect(calls.some((c) => c.startsWith("POST "))).toBe(false);
    const pilot = await (m.waitPipeline as (ctx: unknown, a: object) => Promise<{ code: number }>)(
      { golden: m.loadGolden(), fetchFn, getToken: () => "t", sleep: async () => {}, now: Date.now, log: () => {}, ledgerPath: join(tmp, ".local", "circleci-ledger.json") },
      { slug: fx.slug, pipelineId: fx.pipelineId });
    expect(pilot.code).toBe(5);
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
  it("the re-run of a failed CircleCI start pushes its own branch and names its legs", async () => {
    const calls: string[][] = [];
    const git = (a: string[]) => { calls.push(a); return a[0] === "commit-tree" ? "c".repeat(40) : "tree"; };
    const push = makePusher({ git });
    const first = ctx(split(["check-sh"], LEGS.slice(1)));
    const again: StartCtx = { ...first, legs: { all: LEGS, gh: LEGS.slice(1), cc: [] }, again: true };
    const [x, y] = await Promise.all([push(first), push(again)]);
    expect(x.branch).not.toBe(y.branch);
    expect(y.branch).toMatch(/-again$/);
    expect(calls.filter((a) => a[0] === "push").length).toBe(2);
    expect(calls.filter((a) => a[0] === "commit-tree").map((a) => a.slice(-1)[0]).some((m) => /\[legs:suites-a/.test(m!))).toBe(true);
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
  it("a GitHub group that is unavailable: the land runs the remote tier on this Mac", async () => {
    const dead: Adapter = { provider: "github", async start() { throw new Error("no gh"); }, async poll() { throw new Error("unused"); } };
    const o = await awaitGroups(groupIn({ github: dead, circleci: fakeProvider("circleci", ["pass"]) }, gh3, cc2));
    expect(o.verdict.kind).toBe("local");
  });
  describe("a CircleCI start that failed is run again on GitHub (Lean Overflow.settle, failed_start_covered_once)", () => {
    const deadCc: Adapter = { provider: "circleci", async start() { throw new Error("no key"); }, async poll() { throw new Error("unused"); } };
    it("the legs of CircleCI start on GitHub on the again branch, the local tier is not used, the verdict is GitHub's", async () => {
      const started: StartCtx[] = [];
      const o = await awaitGroups(groupIn({ github: fakeProvider("github", ["pass"], started), circleci: deadCc }, gh3, cc2));
      expect(o.verdict.kind).toBe("accept");
      expect(started.map((c) => [c.legs!.gh, c.legs!.cc, c.again ?? false])).toEqual([[gh3, cc2, false], [cc2, [], true]]);
      expect(o.startFailed).toEqual(["circleci"]);
    });
    it("every leg on CircleCI and none can start: all the legs run on GitHub", async () => {
      const started: StartCtx[] = [];
      const o = await awaitGroups(groupIn({ github: fakeProvider("github", ["pass"], started), circleci: deadCc }, [], LEGS));
      expect(o.verdict.kind).toBe("accept");
      expect(started.map((c) => [c.legs!.gh, c.again ?? false])).toEqual([[LEGS, true]]);
    });
    it("a missing adapter, a failing trigger and a failing key check are the same", async () => {
      for (const circleci of [undefined, circleciAdapter(circleDeps({ trigger: async () => { throw new Error("trigger 500"); } })), circleciAdapter(circleDeps({ push: async () => { throw new Error("key check"); } }))]) {
        const started: StartCtx[] = [];
        const o = await awaitGroups(groupIn({ github: fakeProvider("github", ["pass"], started), ...(circleci ? { circleci } : {}) }, gh3, cc2));
        expect(o.verdict.kind).toBe("accept");
        expect(started.map((c) => c.again ?? false)).toEqual([false, true]);
      }
    });
    it("the re-run cannot start either: the local tier runs the remote checks", async () => {
      let n = 0;
      const gh: Adapter = { provider: "github", async start() { if (n++ > 0) throw new Error("gh down"); return { provider: "github", branch: "b", marker: MARKER }; }, async poll() { return { run: { provider: "github", sha: SHA, laneId: "land", laneDigest: DIGEST, state: "pass" } }; } };
      expect((await awaitGroups(groupIn({ github: gh, circleci: deadCc }, gh3, cc2))).verdict.kind).toBe("local");
    });
    it("the re-run fails: refuse", async () => {
      let n = 0;
      const gh: Adapter = { provider: "github", async start() { n++; return { provider: "github", branch: "b", marker: MARKER }; }, async poll() { return { run: { provider: "github", sha: SHA, laneId: "land", laneDigest: DIGEST, state: n > 1 ? "fail" : "pass" } }; } };
      expect((await awaitGroups(groupIn({ github: gh, circleci: deadCc }, gh3, cc2))).verdict).toMatchObject({ kind: "refuse", reason: "remote-lane-failed" });
    });
    it("a CircleCI pipeline that started and then failed is a refusal, not a second run", async () => {
      const started: StartCtx[] = [];
      const o = await awaitGroups(groupIn({ github: fakeProvider("github", ["pass"], started), circleci: fakeProvider("circleci", ["fail"]) }, gh3, cc2));
      expect(o.verdict).toMatchObject({ kind: "refuse" });
      expect(started.length).toBe(1);
      expect(o.startFailed).toEqual([]);
    });
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
