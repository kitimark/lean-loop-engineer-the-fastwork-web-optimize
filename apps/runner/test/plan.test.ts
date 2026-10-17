import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { Plan, PlanTask } from "@fw/contracts";
import { record } from "../hooks/spawn-guard.mjs";
import { renderPlan, syncCommands, topoSort, type WorkGraph } from "../src/plan.ts";

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
      "4 tasks: 1 done, 1 running, 1 ready, 1 blocked, 0 cut", "  M 1/4  mini", "READY (tasks in one group can run in parallel):", "  group 1: b",
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
    expect(out[0]).toBe("6 tasks: 1 done, 1 running, 1 ready, 1 blocked, 2 cut");
    expect(out.at(-1)).toBe("CUT (2): x, y");
    expect(out.slice(0, -1).filter((l) => /\b[xy]\b/.test(l))).toEqual([]);
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
