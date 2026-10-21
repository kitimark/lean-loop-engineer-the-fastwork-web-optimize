import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { checkGraph } from "../src/plan-check.ts";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "../../..");
const real = readFileSync(join(repo, "docs/team/work-graph.json"), "utf8");
const task = (id: string, extra: object = {}) => ({ id, title: id, stream: "s", milestone: null, deps: [], owner: "o", writes: [], devices: [], evidence: null, ...extra });
const dirs: string[] = [];
afterAll(() => { for (const d of dirs) rmSync(d, { recursive: true, force: true }); });
const graph = (tasks: object[]) => JSON.stringify({ milestones: [], tasks });

/** The pre-commit command (`checkmap file json`) on a graph file in a throwaway git repo. */
function checkmap(text: string) {
  const dir = mkdtempSync(join(tmpdir(), "graph-check-"));
  dirs.push(dir);
  spawnSync("git", ["init", "-q"], { cwd: dir });
  mkdirSync(join(dir, "docs/team"), { recursive: true });
  writeFileSync(join(dir, "docs/team/work-graph.json"), text);
  const t0 = performance.now();
  const r = spawnSync("node", [join(repo, "scripts/checkmap.mjs"), "file", "graph", "docs/team/work-graph.json"], { cwd: dir, encoding: "utf8" });
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
  it("names a duplicate task id and a non-object task entry", () => {
    expect(checkGraph(graph([task("a"), task("a")]))).toEqual([expect.stringContaining("a: id: duplicate task id")]);
    const text = JSON.stringify({ milestones: [], tasks: [task("a"), 7, null, ["x"]] });
    expect(checkGraph(text)).toEqual(["<graph>: tasks[1]: not an object", "<graph>: tasks[2]: not an object", "<graph>: tasks[3]: not an object"]);
  });
  it("does not call id-less tasks duplicates", () => {
    const { id: _a, ...noId1 } = task("x");
    const { id: _b, ...noId2 } = task("y");
    const r = checkGraph(JSON.stringify({ milestones: [], tasks: [noId1, noId2, { ...noId1, id: 5 }, { ...noId2, id: 5 }] }));
    expect(r.length).toBeGreaterThan(0);
    expect(r.some((l) => l.includes("duplicate task id"))).toBe(false);
  });
  it("--staged judges the index blob, not the working tree", () => {
    const dir = mkdtempSync(join(tmpdir(), "graph-staged-"));
    dirs.push(dir);
    const run = (cmd: string, args: string[], env: object = {}) => spawnSync(cmd, args, { cwd: dir, encoding: "utf8", env: { ...process.env, ...env } });
    run("git", ["init", "-q"]);
    mkdirSync(join(dir, "docs/team"), { recursive: true });
    const f = join(dir, "docs/team/work-graph.json");
    writeFileSync(f, graph([task("big", { writes: Array.from({ length: 33 }, (_, i) => `f${i}`) })]));
    run("git", ["add", "docs/team/work-graph.json"]);
    writeFileSync(f, graph([task("ok")]));  // the tree is fine, the index is not
    const cm = [join(repo, "scripts/checkmap.mjs"), "file", "graph", "docs/team/work-graph.json"];
    const staged = run("node", cm, { FW_CHECKMAP_STAGED: "1" });
    expect(staged.status).toBe(1);
    expect(staged.stderr).toContain("big: writes");
    expect(run("node", cm).status).toBe(0);
  });
  it("accepts the current graph", () => {
    expect(checkGraph(real)).toEqual([]);
    const r = checkmap(real);
    expect(r.code).toBe(0);
    console.log(`graph check (node start + schema, current graph): ${r.ms} ms`);
  });
});
