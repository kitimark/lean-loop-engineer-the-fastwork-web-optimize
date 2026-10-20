import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { checkGraph } from "../src/plan-check.ts";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "../../..");
const real = readFileSync(join(repo, "docs/team/work-graph.json"), "utf8");
const task = (id: string, extra: object = {}) => ({ id, title: id, stream: "s", milestone: null, deps: [], owner: "o", writes: [], devices: [], evidence: null, ...extra });
const graph = (tasks: object[]) => JSON.stringify({ milestones: [], tasks });

/** The pre-commit command (`checkmap file json`) on a graph file in a throwaway git repo. */
function checkmap(text: string) {
  const dir = mkdtempSync(join(tmpdir(), "graph-check-"));
  spawnSync("git", ["init", "-q"], { cwd: dir });
  mkdirSync(join(dir, "docs/team"), { recursive: true });
  writeFileSync(join(dir, "docs/team/work-graph.json"), text);
  const t0 = performance.now();
  const r = spawnSync("node", [join(repo, "scripts/checkmap.mjs"), "file", "json", "docs/team/work-graph.json"], { cwd: dir, encoding: "utf8" });
  return { code: r.status, err: r.stderr, ms: Math.round(performance.now() - t0) };
}

describe("work-graph schema check (pre-commit checkmap)", () => {
  it("refuses a task with 33 writes, naming the task and the field", () => {
    const r = checkmap(graph([task("a"), task("big", { writes: Array.from({ length: 33 }, (_, i) => `f${i}`) })]));
    expect(r.code).toBe(1);
    expect(r.err).toContain("big: writes");
  });
  it("accepts 32 writes", () => {
    expect(checkmap(graph([task("ok", { writes: Array.from({ length: 32 }, (_, i) => `f${i}`) })])).code).toBe(0);
  });
  it("names the task for 33 deps", () => {
    const deps = Array.from({ length: 33 }, (_, i) => `d${i}`);
    expect(checkGraph(graph([...deps.map((d) => task(d)), task("many", { deps })]))).toEqual([expect.stringContaining("many: deps")]);
  });
  it("accepts the current graph", () => {
    expect(checkGraph(real)).toEqual([]);
    const r = checkmap(real);
    expect(r.code).toBe(0);
    console.log(`graph check (node start + schema, current graph): ${r.ms} ms`);
  });
});
