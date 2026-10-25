// `fw run`, `fw ci` and `fw watch` make every gh call through the shared request budget (packages/gh-budget): the fake gh
// of that package counts the calls on a simulated clock. Decisions are fwcore's; these tests check the wiring:
// the number of gh calls does not depend on the number of waiters, and no call is made while the budget says wait or stop.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { waitFor } from "@fw/gh-budget";
import { drive, fastCore, goldenDir, mkWorld, type Call, type World } from "../../../packages/gh-budget/test/util.ts";
import { loadState } from "../../../packages/gh-budget/src/state.ts";
import { ciLines } from "../src/land.ts";
import { chargedGh, fwcoreCall, parseRunArgs, runMain, type FwCall, type Gh, type RunDeps } from "../src/run.ts";
import { chargedRunner, type Runner } from "../src/watch-collect.ts";

const T0 = 1_800_000_000;
const SHA = "0123456789abcdef0123456789abcdef01234567";
const hasCore = (() => { try { fwcoreCall(process.cwd()); return true; } catch { return false; } })();
const mk = () => mkdtempSync(join(tmpdir(), "fw-runbudget-"));
const kind = (c: Call) => (c.args[1] === "view" ? (c.args.includes("headSha") ? "head" : "created") : c.args[1] === "download" ? "download" : c.args[1] === "list" ? "list" : c.args.slice(0, 2).join(" "));
const count = (cs: Call[]) => { const m: Record<string, number> = {}; for (const c of cs) m[kind(c)] = (m[kind(c)] ?? 0) + 1; return m; };

// the budget decisions and `fw run`'s own calls go to one persistent fwcore (fastCore) and the fake gh answers in-process
// (production spawns both per call, ~0.1 s each, more under load): generous timeouts anyway, because a timed-out test leaves
// its virtual-time driver running against the next test's world
describe.skipIf(!hasCore)("fw run through the request budget", { timeout: 120_000 }, () => {
  const call: FwCall = hasCore ? fastCore() : () => ({});
  const run = (extra: Record<string, unknown> = {}) => ({ databaseId: 111, createdAt: T0, completeAt: T0 + 300, conclusion: "success", headSha: SHA, headBranch: "ci/t", ...extra });

  /** RunDeps on the fake world; `download` writes what the real one would, after the charged call. */
  function deps(w: World, onDispatch?: () => void): RunDeps {
    const charged = chargedGh(w.env);
    const gh: Gh = async (a) => {
      const out = await charged(a);
      if (a[0] === "workflow") onDispatch?.();
      if (a[0] === "run" && a[1] === "download") {
        const d = a[a.indexOf("-D") + 1]!;
        mkdirSync(join(d, "trace"), { recursive: true });
        writeFileSync(join(d, "counts-run1.json"), "{}");
      }
      return out;
    };
    return { call, gh, wait: (t, timeoutS) => waitFor(w.env, t, { timeoutS }), now: w.sim.now, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: () => {}, nonce: () => "n0nce1234" };
  }
  const fromRun = parseRunArgs(["--engines", "chromium", "--target", "original", "--from-run", "chromium=111"]);

  async function scenario(runs: number, extraWaiters: number) {
    const w = mkWorld(T0, { fastGh: true });
    w.config({ start: T0, listCost: 2, runs: [run()] });
    const ps: Promise<unknown>[] = Array.from({ length: runs }, () => runMain(fromRun, deps(w)));
    for (let i = 0; i < extraWaiters; i++) ps.push(waitFor(w.env, { kind: "run", runId: 111 }, { timeoutS: 3600 }));
    const res = await drive(w.sim, ps);
    return { w, calls: w.calls(), res };
  }

  it("1 fw run alone and with 9 other waiters on its run make the same gh calls", async () => {
    const one = await scenario(1, 0);
    const ten = await scenario(1, 9);
    expect(one.res[0]).toBe(0);
    expect(ten.res.slice(0, 1)).toEqual([0]);
    expect(ten.res.slice(1).every((r) => (r as { code: number }).code === 0)).toBe(true);
    expect(count(ten.calls)).toEqual(count(one.calls));
    expect(ten.calls.map((c) => [c.t, ...c.args.slice(0, 2)])).toEqual(one.calls.map((c) => [c.t, ...c.args.slice(0, 2)]));
    console.log(`# gh calls: 1 waiter ${one.calls.length} ${JSON.stringify(count(one.calls))}, 10 waiters ${ten.calls.length}`);
  });

  it("10 fw runs of one run id make the waiting calls of 1; only their own view and download scale", async () => {
    const one = await scenario(1, 0);
    const ten = await scenario(10, 0);
    expect(ten.res).toEqual(Array(10).fill(0));
    const a = count(one.calls), b = count(ten.calls);
    expect(b.list).toBe(a.list);
    expect(b.created).toBe(a.created);
    expect(b.head).toBe(10);
    expect(b.download).toBe(50); // 5 pieces per fw run (3 counts shards, classes, telemetry)
    console.log(`# gh calls: 1 fw run ${one.calls.length} ${JSON.stringify(a)}, 10 fw runs ${ten.calls.length} ${JSON.stringify(b)}`);
  });

  it("dispatching finds and awaits the new run through the poller: no gh run watch, no run list loop", async () => {
    const w = mkWorld(T0, { fastGh: true });
    const old = run({ databaseId: 50, createdAt: T0 - 1000, completeAt: T0 - 900 });
    w.config({ start: T0, listCost: 2, runs: [old] });
    const d = deps(w, () => w.config({ start: T0, listCost: 2, runs: [old, run({ databaseId: 51, createdAt: w.sim.now() + 5, completeAt: w.sim.now() + 250, workflowName: "chromium-counts", event: "workflow_dispatch", displayTitle: "chromium-counts dispatch nonce=n0nce1234" })] }));
    const args = parseRunArgs(["--engines", "chromium", "--target", "original", "--ref", "ci/t"]);
    const [code] = await drive(w.sim, [runMain(args, d)]);
    expect(code).toBe(0);
    const calls = w.calls();
    expect(calls.some((c) => c.args[1] === "watch")).toBe(false);
    // identity, not recency: no list before the dispatch; the dispatch carries the nonce, the wait selects the run that echoes it
    expect(calls[0]!.args.slice(0, 2).join(" ")).toBe("workflow run");
    expect(calls[0]!.args).toContain("nonce=n0nce1234");
    expect(calls.find((c) => c.args.includes("headSha"))!.args[2]).toBe("51");
    const ticks = calls.filter((c) => c.args[1] === "list").length;
    const { Pmin } = JSON.parse(readFileSync(join(goldenDir, "limits.json"), "utf8")) as { Pmin: number };
    expect(ticks).toBeLessThanOrEqual(Math.ceil(250 / Pmin) + 1);
    console.log(`# gh calls: dispatch ${calls.length} ${JSON.stringify(count(calls))}`);
  });

  it("no gh call is made in the minute the one-off share is spent: the calls wait instead", async () => {
    const w = mkWorld(T0, { fastGh: true });
    w.config({ start: T0, listCost: 2, runs: [run()] });
    const gh = chargedGh(w.env);
    await drive(w.sim, [(async () => { for (let i = 0; i < 30; i++) await gh(["run", "view", "111", "--json", "headSha"]); })()]);
    const cs = w.calls();
    expect(cs).toHaveLength(30);
    for (const c of cs) expect(cs.filter((x) => x.t > c.t - 60 && x.t <= c.t).reduce((n, x) => n + x.cost, 0)).toBeLessThanOrEqual(40);
    expect(Math.max(...cs.map((c) => c.t)) - T0).toBeGreaterThanOrEqual(60); // it did wait
  });

  it("after a refusal with retry-after the collector makes no call until the time passes", async () => {
    const w = mkWorld(T0, { fastGh: true });
    w.config({ start: T0, runs: [run()], overrides: [{ at: T0, lines: ["HTTP/2.0 403 Forbidden", "Retry-After: 120"] }] });
    const base: Runner = async () => { throw new Error("only gh is expected here"); };
    const ci = chargedRunner(base, () => w.env);
    const list = () => ci("gh", ["run", "list", "--limit", "20"], 10_000);
    expect(await list()).toBeNull(); // the refused call itself
    expect(w.calls()).toHaveLength(1);
    for (const dt of [1, 60, 119]) { w.sim.set(T0 + dt); expect(await list()).toBeNull(); }
    expect(w.calls()).toHaveLength(1); // wait: gh was not started
    w.sim.set(T0 + 121);
    expect(typeof (await list())).toBe("string");
    expect(w.calls()).toHaveLength(2);
  });

  it("after maxFails refusals in a row the budget says stop: fw run throws and starts no more gh", async () => {
    const w = mkWorld(T0, { fastGh: true });
    const refuse = { at: T0, lines: ["HTTP/2.0 429 Too Many Requests"] };
    w.config({ start: T0, runs: [run()], overrides: Array(20).fill(refuse) });
    const gh = chargedGh(w.env);
    const errs: string[] = [];
    await drive(w.sim, [(async () => { for (let i = 0; i < 12; i++) await gh(["run", "view", "111", "--json", "headSha"]).catch((e: Error) => errs.push(e.message)); })()]);
    expect(errs.slice(0, 6).every((e) => /failed: HTTP 429|failed: gh exited/.test(e) || /failed/.test(e))).toBe(true);
    expect(errs.slice(6).every((e) => /not made.*stop \(failures\)/.test(e))).toBe(true);
    expect(w.calls()).toHaveLength(6); // maxFails = 6 (limits.json); the other 6 attempts started no gh
    w.sim.set(T0 + 100_000);
    await expect(gh(["run", "list"])).rejects.toThrow(/stop/);
    expect(w.calls()).toHaveLength(6);
  });
});

describe("chargedRunner", () => {
  it("passes other programs through untouched", async () => {
    const seen: string[] = [];
    const r = chargedRunner(async (cmd) => { seen.push(cmd); return "ok"; }, () => { throw new Error("no budget needed"); });
    expect(await r("docker", ["ps"], 1000)).toBe("ok");
    expect(seen).toEqual(["docker"]);
  });
  it("a missing budget (no fwcore) is a failed gh call, not a crash", async () => {
    const r = chargedRunner(async () => "x", () => { throw new Error("fwcore not built"); });
    expect(await r("gh", ["run", "list"], 1000)).toBeNull();
  });
});

describe.skipIf(!hasCore)("land's advisory CI line", () => {
  it("books its run list at 3 requests and makes one gh call", () => {
    const w = mkWorld(T0, { fastGh: true });
    w.config({ start: T0, listCost: 2, runs: [{ databaseId: 111, createdAt: T0, completeAt: T0 + 300, conclusion: "success", headSha: SHA, headBranch: "ci/t" }] });
    expect(ciLines("ci/t", w.root, w.env).length).toBeGreaterThan(0);
    expect(w.calls().map((c) => c.args.slice(0, 2).join(" "))).toEqual(["run list"]);
    const st = loadState(w.stateDir) as { ledger: { cost: number; charged: boolean }[] };
    expect(st.ledger.filter((e) => e.charged).map((e) => e.cost)).toEqual([3]);
  });
});
