import { describe, expect, it } from "vitest";
import type { Env } from "@fw/gh-budget";
import { GhClock, passParts, phasedEnv, runPhases, stepOf } from "../src/run-phases.ts";
import { runCli } from "../src/run.ts";

const rec = () => {
  const out: { step: string; exit: number | null | undefined; extra?: object }[] = [];
  const begin = (_t: string, step: string) => (exit?: number | null, extra?: object) => { out.push({ step, exit, extra }); };
  return { out, begin };
};
const done = { code: 0, lines: ["run 123 success"] };

describe("fw run phases", () => {
  it("splits a dispatch into plan, the dispatch call parts, wait (with the run id) and file", async () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, false);
    const gh = ph.gh((async () => "") as never), wait = ph.wait((async () => done) as never);
    await gh(["workflow", "run", "x.yml"]);
    await wait({ kind: "run", runId: 1 } as never, 10);
    await gh(["run", "download", "123"]);
    ph.finish(0);
    expect(out.map((o) => o.step)).toEqual(["run plan", "run dispatch lock", "run wait", "run file"]);
    expect(out[2]!.extra).toEqual({ runId: 123 });
  });
  it("a wait slice that timed out (code 3) stays in the same wait span; a second job starts a new dispatch", async () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, false);
    let n = 0;
    const gh = ph.gh((async () => "") as never), wait = ph.wait((async () => (n++ === 0 ? { code: 3, lines: [] } : done)) as never);
    await gh(["workflow", "run", "x.yml"]);
    await wait({} as never, 10); await wait({} as never, 10);
    await gh(["workflow", "run", "y.yml"]);
    ph.finish(2);
    expect(out.map((o) => o.step)).toEqual(["run plan", "run dispatch lock", "run wait", "run file", "run dispatch lock", "run wait"]);
    expect(out[5]!.exit).toBe(2);
  });
  it("a run waited with --from-run has no dispatch call: the first wait ends the plan span", async () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, false);
    await ph.wait((async () => done) as never)({} as never, 10);
    ph.finish(0);
    expect(out.map((o) => o.step)).toEqual(["run plan", "run wait", "run file"]);
  });
  it("a fw run that fails before its first phase (usage error) still writes a span", async () => {
    const { out, begin } = rec();
    await expect(runCli(["--bogus"], process.cwd(), {}, begin as never)).rejects.toThrow();
    expect(out.map((o) => [o.step, o.exit])).toEqual([["run plan", 1]]);
  });
  it("a dry run is one run dry span", () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, true);
    ph.finish(0);
    expect(out.map((o) => o.step)).toEqual(["run dry"]);
  });
  it("a failed dispatch call closes its part with the exit code, no wait span", async () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, false);
    await expect(ph.gh((async () => { throw new Error("x"); }) as never)(["workflow", "run", "x.yml"])).rejects.toThrow();
    ph.finish(1);
    expect(out.map((o) => [o.step, o.exit])).toEqual([["run plan", 0], ["run dispatch lock", 1]]);
  });
  it("the step names of the phases", () => {
    expect(["plan", "lock", "backoff", "call", "wait", "file", "dry"].map((p) => stepOf(p as never))).toEqual(
      ["run plan", "run dispatch lock", "run dispatch backoff", "run dispatch call", "run wait", "run file", "run dry"]);
  });
});

describe("the parts of a dispatch call", () => {
  const fakeEnv = (replies: string[]): Env => ({
    dir: "", gh: "gh", now: () => 0, sleepUntil: async () => {},
    core: (req: { op: string }) => (req.op === "ci.budget.reserve" ? { decision: replies.shift() } : { state: {} }),
  } as unknown as Env);
  it("a wait then an issue: lock, backoff, lock, call, in that order, then wait", async () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, false);
    const env = ph.env(fakeEnv(["wait", "issue"]));
    const gh = ph.gh((async () => {
      env.core({ op: "ci.budget.reserve" }); await env.sleepUntil(1);
      env.core({ op: "ci.budget.reserve" }); env.core({ op: "ci.budget.observe" });
      return "";
    }) as never);
    await gh(["workflow", "run", "x.yml"]);
    ph.finish(0);
    expect(out.map((o) => o.step)).toEqual(["run plan", "run dispatch lock", "run dispatch backoff", "run dispatch lock", "run dispatch call", "run wait"]);
  });
  it("GhClock adds the parts up over several calls", () => {
    let t = 0;
    const c = new GhClock(undefined, () => t);
    c.start(); t = 5; c.on("issue"); t = 12; c.on("ghEnd");
    t = 20; c.start(); t = 21; c.on("wait"); t = 31; c.on("slept"); t = 32; c.on("issue"); t = 40; c.on("ghEnd");
    expect(c.ms).toEqual({ lock: 7, backoff: 10, call: 15 });
    expect(c.calls).toBe(2);
  });
  it("events outside a call are ignored", () => {
    const c = new GhClock(undefined, () => 0);
    c.on("issue"); c.on("wait");
    expect(c.ms).toEqual({ lock: 0, backoff: 0, call: 0 });
  });
  it("a watch pass is split into lock, call and the rest; a pass without gh call has no parts", () => {
    const c = { ms: { lock: 2000.4, call: 3000, backoff: 0 }, calls: 1 };
    expect(passParts(c, 9000)).toEqual([
      { step: "watch pass gh lock", durMs: 2000 }, { step: "watch pass gh call", durMs: 3000 }, { step: "watch pass other", durMs: 4000 }]);
    expect(passParts({ ms: { lock: 0, call: 0, backoff: 0 }, calls: 0 }, 9000)).toEqual([]);
    expect(passParts({ ms: { lock: 5000, call: 5000, backoff: 0 }, calls: 1 }, 9000).at(-1)!.durMs).toBe(0);
  });
  it("phasedEnv forwards every core reply unchanged", () => {
    const seen: string[] = [];
    const e = phasedEnv({ core: (r: { op: string }) => ({ op: r.op, decision: "issue" }), sleepUntil: async () => {} } as unknown as Env, (x) => seen.push(x));
    expect(e.core({ op: "ci.budget.reserve" })).toEqual({ op: "ci.budget.reserve", decision: "issue" });
    e.core({ op: "ci.budget.observe" });
    expect(seen).toEqual(["issue", "ghEnd"]);
  });
});
