// land-lane-circleci round 2: the width table of Lean `Fw.Ci.Overflow.widths` is derived from the workflow files and never below the real
// job count. The derivation is in workflow-widths.ts (a heaviest set of jobs no two of which are ancestor and descendant, each job at most its
// matrix size, its max-parallel and, on macOS, the 5 macOS slots). A matrix that comes from `fromJSON(...)` is bounded by the maximum its
// input allows, read from the workflow file or the planner it calls; a dynamic matrix with no bound here fails the test. So a matrix that
// grows past the table, a new job, or a new workflow fails here until the Lean table is raised.
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { checksWithReads } from "../src/land.ts";
import { fwcoreCall } from "../src/run.ts";
import { checkRow, gateJobsMax, parseWorkflow, trajectoryMax, widest, width, type Job, type Workflow, widthTable } from "./workflow-widths.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const LEGS = readFileSync(join(root, "lean", "land-legs.txt"), "utf8").split(/\s+/).filter(Boolean);
const read = (p: string) => readFileSync(join(root, p), "utf8");
const num = (text: string, re: RegExp, what: string): number => { const m = re.exec(text); if (!m) throw new Error(`${what}: no match for ${re}`); return Number(m[1]); };
/** the largest number in a `case "$X" in 1|2|3) ;;` list */
const caseMax = (text: string, v: string): number => { const m = new RegExp(`case "\\$${v}" in ((?:\\d\\|)*\\d)\\)`).exec(text); if (!m) throw new Error(`no case list for ${v}`); return Math.max(...m[1]!.split("|").map(Number)); };
// the widths a `[trajectory widths=..]` line may list (.github/scripts/trajectory-line.mjs asks pickWidths): the longest accepted list
const { pickWidths } = (await import(join(root, "packages/gate-breakpoints/src/trajectory/reduce.mjs"))) as { pickWidths: (s: string) => number[] | null };
const widthsMax = (): number => { const ws = [390, 640, 641, 1280]; let best = 0; for (let m = 0; m < 16; m++) { const l = ws.filter((_, i) => m & (1 << i)); if (pickWidths(l.join(",")) !== null) best = Math.max(best, l.length); } return best; };
/** the number of sets in `set: [1, 2, 3]` of smoothness.yml's plan step */
const setsOf = (text: string): number => { const m = /set: \[((?:\d, )*\d)\]/.exec(text); if (!m) throw new Error("smoothness sets: no match"); return m[1]!.split(", ").length; };
const engines2 = 2; // `both` is [chromium, playwright-webkit] in the plan step of every workflow below

/** The most one dynamic matrix can have, per `workflow/job`, with where the bound comes from (CONFIRMED by reading it, at the time of this commit). */
function dynamicMax(): Record<string, () => number> {
  const once = <T,>(f: () => T): (() => T) => { let v: T | undefined; return () => (v ??= f()); };
  const traj = once(() => trajectoryMax(root));
  const gate = once(() => gateJobsMax(root));
  const wf = (f: string) => read(`.github/workflows/${f}`);
  return {
    // breakpoint-gate.yml:226 `matrix: fromJSON(needs.site.outputs.matrix)`; the jobs .github/scripts/gate-jobs.mjs plans over every input the case lists at :171-:174 allow
    "breakpoint-gate/gate": gate,
    // chromium-counts.yml:380 `fromJSON(needs.plan.outputs.matrix)` = targets (2, the plan's `both`) x runs, runs 2..10 at :145
    "chromium-counts/counts": () => engines2 * num(wf("chromium-counts.yml"), /"\$RUNS" -gt (\d+)/, "chromium-counts runs"),
    // engine-premises.yml:174 runs 1..6 (case list at :110); :245 jobs 1..4 (:111), max-parallel 1 at :243
    "engine-premises/chromium": () => caseMax(wf("engine-premises.yml"), "RUNS"),
    "engine-premises/webkit": () => caseMax(wf("engine-premises.yml"), "JOBS"),
    // mutants.yml:126 `fromJSON(needs.plan.outputs.shards)`, shards 1..24 (:110)
    "mutants/shard": () => num(wf("mutants.yml"), /"\$SHARDS" -le (\d+)/, "mutants shards"),
    // visual-diff.yml:275-276 engines (2, :151) x shards 1..16 (packages/visual-diff/src/shards.mjs:12); port-fonts :347 engines
    "visual-diff/shoot": () => engines2 * num(read("packages/visual-diff/src/shards.mjs"), /n > (\d+)/, "visual-diff shards"),
    "visual-diff/port-fonts": () => engines2,
    // sim-speed.yml:121 `fromJSON(needs.plan.outputs.matrix)` = arms (any number of words, :105) x reps 1..3 (:104); unbounded, so the 5 macOS slots (runs-on xcode-27) are the bound
    "sim-speed/probe": () => 1e9,
    "smoothness/cadence": () => widthsMax() * setsOf(wf("smoothness.yml")),
    "smoothness/webkit-sim": () => 4,
    // toolbar-throttle.yml:119 vms 1..3, or 1..6 when the commit message has [throttle:morph-end] (max-parallel 3 caps it)
    "toolbar-throttle/sim": () => 6,
    "trajectory-probe/probe": () => traj().linux,
    "trajectory-probe/probe-apple": () => traj().apple,
    "trajectory-probe/merge": () => engines2,
    // webkit-sim.yml:275 the matrix of the plan (Lean measure.simPlan, vms 1..3 x arms); unbounded here, so macOS (xcode-27) and max-parallel 2 at :274 are the bound
    "webkit-sim/sim": () => 1e9,
    // wktr.yml:123 (max-parallel 1 at :121) and wktr-fixtures.yml:129 (max-parallel from the golden, up to 5): jobs 1..4 (wktr.yml:104; wktr-fixtures.yml:110), macOS
    "wktr/wktr": () => caseMax(wf("wktr.yml"), "JOBS"),
    "wktr-fixtures/fixtures": () => caseMax(wf("wktr-fixtures.yml"), "JOBS"),
  };
}

const DYN = dynamicMax();
const lean = read("lean/Fw/Ci/Overflow.lean");
const table = widthTable(lean);
const files = readdirSync(join(root, ".github/workflows")).filter((f) => f.endsWith(".yml")).sort();
const workflows: Workflow[] = files.map((f) => parseWorkflow(root, f));

describe("the width table is the width of every workflow file", () => {
  const dyn = DYN;
  const sizeOf = (w: Workflow) => (j: Job): number => {
    const key = `${w.name}/${j.name}`;
    const f = dyn[key];
    if (!f) throw new Error(`${w.file}:${j.line} job ${j.name} has a matrix from fromJSON or outputs and no bound in dynamicMax(): add ${key} with where its maximum comes from`);
    return f();
  };
  const derived = new Map<string, number>();
  it("derives a width for every workflow (a dynamic matrix without a bound fails)", () => {
    for (const w of workflows) derived.set(w.name, width(w, sizeOf(w)));
    expect(derived.size).toBe(workflows.length);
    if (process.env.PRINT_WIDTHS) writeFileSync(process.env.PRINT_WIDTHS, workflows.map((w) => `${w.name} ${derived.get(w.name)} ${widest(w, sizeOf(w)).jobs.join(" ")}`).join("\n"));
  });
  it("every dynamic bound names a job that has a dynamic matrix", () => {
    const real = new Set(workflows.flatMap((w) => w.jobs.filter((j) => j.size === "dynamic").map((j) => `${w.name}/${j.name}`)));
    expect([...Object.keys(DYN)].filter((k) => !real.has(k))).toEqual([]);
  });
  it("no row of the table is below the width derived from its workflow", () => {
    for (const w of workflows) checkRow(table, w, derived.get(w.name)!);
  });
  it("and no row is above it either: the table is the derivation", () => {
    for (const w of workflows) checkRow(table, w, derived.get(w.name)!, true);
  });
  it("every workflow has a row and every row names a workflow", () => {
    expect([...table.keys()].sort()).toEqual(workflows.map((w) => w.name).sort());
  });
  it("fwcore counts one run of a workflow as its row says", () => {
    for (const w of workflows) {
      const r = call({ op: "ci.overflow", legs: LEGS, ghActive: [w.name], ghActions: "operational", ghPrev: false, ccArm: "unknown", ccReadAt: null, now: 1, spent: 0, storage: 0, keys: null, checkout: null, forceFull: false }) as { ghFree: number };
      expect(r.ghFree, w.name).toBe(Math.max(0, 20 - table.get(w.name)!));
    }
  });
});

describe("the scope file the width planner loads selects the width test", () => {
  it("spec.mjs loads scope.gen.json, and a change to that file alone selects runner:overflow-widths", () => {
    expect(readFileSync(join(root, "packages/gate-breakpoints/src/spec.mjs"), "utf8")).toContain("scope.gen.json");
    expect(checksWithReads(root, ["packages/gate-breakpoints/src/scope.gen.json"]).map((c) => c.id)).toContain("runner:overflow-widths");
  });
});
