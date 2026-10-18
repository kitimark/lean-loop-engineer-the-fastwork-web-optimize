import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { Plan, PlanTask } from "@fw/contracts";
import { record } from "../hooks/spawn-guard.mjs";
import { lintCli, renderLint, renderPlan, syncCommands, topoSort, type WorkGraph } from "../src/plan.ts";

const here = dirname(fileURLToPath(import.meta.url));
const T = (id: string, deps: string[] = [], extra: object = {}) => ({ id, title: id, stream: "s", milestone: "M", deps, owner: "o", ...extra });

describe("topoSort", () => {
  it("puts dependencies first and keeps file order otherwise", () => {
    expect(topoSort([T("c", ["b"]), T("b", ["a"]), T("a"), T("d")]).map((t) => t.id)).toEqual(["a", "b", "c", "d"]);
  });
  it("names a cycle and an unknown dep", () => {
    expect(() => topoSort([T("a", ["b"]), T("b", ["a"])])).toThrow(/cycle among: a, b/);
    expect(() => topoSort([T("a", ["zz"])])).toThrow(/dep zz is not in the graph/);
  });
});

describe("syncCommands", () => {
  const g: WorkGraph = { milestones: [{ id: "M", title: "m" }], tasks: [T("b", ["a"]), T("a", [], { writes: ["x/**"], evidence: "abc1234" })] };
  it("milestones first, tasks deps-first, full task.define bodies", () => {
    const c = syncCommands(g);
    expect(c.map((x) => x.type)).toEqual(["milestone.define", "task.define", "task.define"]);
    expect(c[1]).toMatchObject({ task: "a", writes: ["x/**"], devices: [], evidence: "abc1234", milestone: "M" });
    expect(c[1]).not.toHaveProperty("needs");
    const d = syncCommands({ milestones: [], tasks: [T("p", [], { needs: ["device"] })] });
    expect(d[0]).toMatchObject({ task: "p", needs: ["device"] });
    expect(c[2]).toMatchObject({ task: "b", deps: ["a"], evidence: null });
    expect(c[2]).not.toHaveProperty("cut");
    const x = syncCommands({ milestones: [], tasks: [T("x", [], { cut: true })] });
    expect(x[0]).toMatchObject({ task: "x", cut: true });
  });
  it("keys are stable for equal content and change when a task is edited", () => {
    const k = (x: WorkGraph) => syncCommands(x).map((c) => c.key);
    expect(k(g)).toEqual(k(structuredClone(g)));
    const edited = structuredClone(g); edited.tasks[0]!.deps = [];
    const of = (x: WorkGraph, id: string) => k(x).find((key) => key.startsWith(`plan:d:${id}:`));
    expect(of(edited, "b")).not.toBe(of(g, "b"));
    expect(of(edited, "a")).toBe(of(g, "a"));
  });
  it("the ancestry fact: evidenceOnMain false only for a sha-like evidence off main, with its own key", () => {
    const asked: string[] = [];
    const off = (sha: string) => { asked.push(sha); return false; };
    const tasks = [T("a", [], { evidence: "abc1234" }), T("r", [], { evidence: "39053169745" }), T("u", [], { evidence: "user: ok" }), T("n")];
    const c = syncCommands({ milestones: [], tasks }, "lead", off);
    expect(c[0]).toMatchObject({ task: "a", evidenceOnMain: false });
    for (const x of c.slice(1)) expect(x).not.toHaveProperty("evidenceOnMain");
    expect(asked).toEqual(["abc1234"]);
    const on = syncCommands({ milestones: [], tasks }, "lead", () => true);
    expect(on[0]).not.toHaveProperty("evidenceOnMain");
    expect(on[0]!.key).toBe(syncCommands({ milestones: [], tasks })[0]!.key);
    expect(c[0]!.key).not.toBe(on[0]!.key);
  });
  it("clips an over-long title to the contract's 200", () => {
    const c = syncCommands({ milestones: [], tasks: [T("a", [], { title: "x".repeat(300) })] })[0] as { title: string };
    expect(c.title).toHaveLength(200);
  });
  it("the real docs/team/work-graph.json converts without error", () => {
    const f = JSON.parse(readFileSync(join(here, "../../../docs/team/work-graph.json"), "utf8")) as WorkGraph;
    expect(syncCommands(f)).toHaveLength(f.milestones.length + f.tasks.length);
  });
});

describe("renderPlan", () => {
  const ag = (): Pick<PlanTask, "needs" | "lane"> => ({ needs: [], lane: "agent" });
  const dv = (): Pick<PlanTask, "needs" | "lane"> => ({ needs: ["device"], lane: "device" });
  const p: Plan = {
    tasks: [
      { id: "a", title: "A", stream: "s", milestone: "M", owner: "o", deps: [], ...ag(), state: "done", blockers: [], agent: null, evidence: "abc1234" },
      { id: "b", title: "B", stream: "s", milestone: "M", owner: "o", deps: ["a"], ...ag(), state: "ready", blockers: [], agent: null, evidence: null },
      { id: "c", title: "C", stream: "s", milestone: "M", owner: "o", deps: ["a"], ...ag(), state: "running", blockers: [], agent: "c", evidence: null },
      { id: "d", title: "D", stream: "s", milestone: "M", owner: "o", deps: ["b", "c"], ...ag(), state: "blocked", blockers: ["b", "c"], agent: null, evidence: null },
    ],
    milestones: [{ id: "M", title: "mini", done: 1, total: 4 }], criticalPath: ["b", "d"], parallelSafe: [["b"]],
  };
  it("prints ready groups, running, blocked with blockers, critical path", () => {
    expect(renderPlan(p)).toBe([
      "4 tasks: 1 done, 1 running, 0 handed back, 0 integrated, 0 parked, 1 ready, 1 blocked, 0 cut", "  M 1/4  mini", "READY (tasks in one group can run in parallel):", "  group 1: b",
      "DEVICE (needs you + the iPhone):", "  none",
      "RUNNING:", "  c (agent c)", "BLOCKED (waiting on):", "  d <- b, c", "CRITICAL PATH (2): b -> d", "CUT (0): none",
    ].join("\n"));
  });
  it("lists cut tasks on one CUT line at the end, nowhere else", () => {
    const q: Plan = { ...p, tasks: [...p.tasks,
      { id: "x", title: "CUT: X", stream: "s", milestone: "MX", owner: "o", deps: [], ...ag(), state: "cut", blockers: [], agent: null, evidence: null },
      { id: "y", title: "CUT: Y", stream: "s", milestone: "MX", owner: "o", deps: [], ...dv(), state: "cut", blockers: [], agent: null, evidence: null },
    ] };
    const out = renderPlan(q).split("\n");
    expect(out[0]).toBe("6 tasks: 1 done, 1 running, 0 handed back, 0 integrated, 0 parked, 1 ready, 1 blocked, 2 cut");
    expect(out.at(-1)).toBe("CUT (2): x, y");
    expect(out.slice(0, -1).filter((l) => /\b[xy]\b/.test(l))).toEqual([]);
  });
  it("lists tasks whose agents ended with where the work went, after RUNNING (task-state-truth)", () => {
    const q: Plan = { ...p, tasks: [...p.tasks,
      { id: "h", title: "H", stream: "s", milestone: "M", owner: "o", deps: [], ...ag(), state: "handedBack", blockers: [], agent: null, evidence: null, outcome: { kind: "handedBack", agent: "h", tip: "abc1234" } },
      { id: "i", title: "I", stream: "s", milestone: "M", owner: "o", deps: [], ...ag(), state: "integrated", blockers: [], agent: null, evidence: null, outcome: { kind: "integrated", branch: "ci/integrate-1", tip: "b00ef68" } },
      { id: "k", title: "K", stream: "s", milestone: "M", owner: "o", deps: [], ...ag(), state: "parked", blockers: [], agent: null, evidence: null, outcome: { kind: "parked", reason: "agent ended without a handback" } },
    ] };
    const out = renderPlan(q).split("\n");
    expect(out[0]).toBe("7 tasks: 1 done, 1 running, 1 handed back, 1 integrated, 1 parked, 1 ready, 1 blocked, 0 cut");
    const i = out.indexOf("ENDED, NOT LANDED (3):");
    expect(out.slice(i - 2, i + 5)).toEqual(["RUNNING:", "  c (agent c)", "ENDED, NOT LANDED (3):",
      "  handedBack h  by h at abc1234", "  integrated i  into ci/integrate-1 at b00ef68", "  parked     k  agent ended without a handback",
      "BLOCKED (waiting on):"]);
  });
  it("prints the device lane apart: ready first, then blocked with blockers; not in BLOCKED", () => {
    const q: Plan = { ...p, tasks: [...p.tasks,
      { id: "e", title: "E", stream: "s", milestone: "M", owner: "o", deps: ["d"], ...dv(), state: "blocked", blockers: ["d"], agent: null, evidence: null },
      { id: "f", title: "Finger swipe", stream: "s", milestone: "M", owner: "o", deps: [], ...dv(), state: "ready", blockers: [], agent: null, evidence: null },
    ] };
    const out = renderPlan(q).split("\n");
    const i = out.indexOf("DEVICE (needs you + the iPhone):");
    expect(out.slice(i, i + 4)).toEqual(["DEVICE (needs you + the iPhone):", "  ready    f  Finger swipe", "  blocked  e <- d", "RUNNING:"]);
    expect(out.slice(out.indexOf("BLOCKED (waiting on):"))).toEqual(["BLOCKED (waiting on):", "  d <- b, c", "CRITICAL PATH (2): b -> d", "CUT (0): none"]);
  });
});

describe("spawn guard record", () => {
  it("carries the spawned agent's name (so the drain can claim a task of that name)", () => {
    const r = record({ tool_name: "Agent", tool_use_id: "u", tool_input: { name: "con-plan" } }, { decision: "allow", reason: null });
    expect(r).toMatchObject({ hook_event_name: "SpawnGuard", agent_name: "con-plan" });
    expect(record({ tool_name: "Agent", tool_use_id: "u" }, null).agent_name).toBeNull();
  });
});

describe("plan lint", () => {
  const lf = (task: string, code: string, severity: string, detail = "") => ({ task, code, severity, detail });
  it("renders errors and warnings, counts info", () => {
    const text = renderLint({ ok: false, errors: 1, warnings: 1, infos: 2, findings: [lf("a", "unknownDep", "error", "zz"), lf("b", "evUser", "warn", "user: x"), lf("c", "evidenceNoTrailer", "info")] });
    expect(text).toBe("error a unknownDep: zz\nwarn  b evUser: user: x\nplan lint: 1 errors, 1 warnings, 2 info (evidence without a Task: trailer on main)");
  });
  it("sends the tasks and the commits of main to fwcore and exits 1 on errors", async () => {
    const dir = mkdtempSync(join(tmpdir(), "lint-"));
    const f = join(dir, "g.json");
    writeFileSync(f, JSON.stringify({ milestones: [], tasks: [T("a", ["b"]), T("b", [], { evidence: "abc1234" })] }));
    const seen: Record<string, unknown>[] = [];
    const bad = async (r: Record<string, unknown>) => (seen.push(r), { ok: false, errors: 1, warnings: 0, infos: 0, findings: [lf("a", "unknownDep", "error", "b")] });
    const good = async () => ({ ok: true, errors: 0, warnings: 0, infos: 0, findings: [] });
    const commits = [{ sha: "s1", body: "x\n\nTask: a" }];
    expect(await lintCli([f], here, bad, commits)).toBe(1);
    expect(seen[0]).toMatchObject({ op: "plan.lint", commits, tasks: [{ id: "a", deps: ["b"], evidence: null }, { id: "b", evidence: "abc1234" }] });
    expect(await lintCli([f], here, good, commits)).toBe(0);
    seen.length = 0;
    await lintCli([f], here, bad, commits, () => false);
    expect((seen[0]!.tasks as object[])[1]).toMatchObject({ id: "b", evidenceOnMain: false });
    seen.length = 0;
    await lintCli([f], here, bad, commits, () => true);
    expect((seen[0]!.tasks as object[])[1]).not.toHaveProperty("evidenceOnMain");
    await expect(lintCli([], here)).rejects.toThrow(/usage/);
  });
});
