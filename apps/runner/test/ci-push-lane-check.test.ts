// Task ci-push-lane-check (incident inc-ci-push-no-lane): the ci/* pre-push hook refuses a push that would run no measuring lane.
// The TS verdict is checked against the Lean golden (packages/contracts/golden/ci/pushlane.jsonl, Fw.Ci.Intent `reason`), then each
// refusal case runs through the real hook; main and non-ci branches pass untouched.
import "./land-timeout.ts";
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { laneReason, lanesTrailer, requiredLanes } from "../src/ci-push.ts";

const ROOT = resolve(import.meta.dirname, "../../..");
const HOOKS = join(ROOT, "scripts/hooks");
const rows = readFileSync(join(ROOT, "packages/contracts/golden/ci/pushlane.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
const head = rows[0] as { seeders: string[] };
type Row = { name: string; msgs: string[]; diff: string[]; merged: string[]; landed: boolean; cones: Record<string, string[]>; runs: string[]; measuring: string[];
  required: string[]; missing: string[]; reason: string; refuse: boolean };
const cases = rows.filter((r) => r.kind === "pushLane") as Row[];

describe("Lean golden replay (Fw.Ci.Intent reason)", () => {
  it("has a case for every reason", () => {
    expect(new Set(cases.map((c) => c.reason))).toEqual(new Set(["ok", "same-tree", "missing", "no-measuring"]));
    expect(cases.length).toBeGreaterThanOrEqual(15);
  });

  it("the TS verdict equals Lean on every case, the lanes started come from the guard script", async () => {
    const m = await import(pathToFileURL(join(ROOT, ".github/scripts/changed-inputs.mjs")).href);
    const { table } = m.loadGolden(ROOT);
    const { lanes } = (await import(pathToFileURL(join(ROOT, ".github/scripts/changed-inputs.mjs")).href)).loadIntent(ROOT) as { lanes: { prefix: string; lanes: { file: string; name: string; token: string; byDefault: boolean }[] } };
    const nonMeasuring = lanes.lanes.filter((l) => head.seeders.includes(l.file)).map((l) => l.name);
    for (const c of cases) {
      const S = (g: string) => (table.sets[g] ?? [g]).flatMap((h: string) => (h.startsWith("@cone:") ? (c.cones[h.slice(6)] ?? []) : [h]));
      const files = c.diff.filter((f) => !c.merged.includes(f));
      const runs = table.workflows
        .map((w: { file: string; inputs: string[] }) => ({ w, lane: lanes.lanes.find((l) => l.file === w.file)! }))
        .filter(({ w, lane }: { w: { file: string; inputs: string[] }; lane: { name: string } }) =>
          m.decide({ event: "push", ref: "refs/heads/ci/x", files, globs: m.expand(S, w.inputs), msg: c.msgs[0] ?? "", lane: { ...lane, prefix: lanes.prefix }, tip: true, landed: c.landed }).run)
        .map(({ lane }: { lane: { name: string } }) => lane.name);
      expect(runs, c.name).toEqual(c.runs);
      const v = laneReason(c.msgs, runs, nonMeasuring, files.length === 0);
      expect(v.reason, c.name).toBe(c.reason);
      expect(v.reason !== "ok", c.name).toBe(c.refuse);
      expect(v.required, c.name).toEqual(c.required);
      expect(v.missing, c.name).toEqual(c.missing);
      expect(v.measuring, c.name).toEqual(c.measuring);
    }
  });

  it("the trailer parser", () => {
    expect(lanesTrailer("x [lanes: wktr, Breakpoint-Gate]\n[lanes:lean]")).toEqual(["wktr", "breakpoint-gate", "lean"]);
    expect(lanesTrailer("[lanes: wktr")).toEqual([]);
    expect(requiredLanes(["a [lanes: wktr]", "[lanes: wktr lean]"])).toEqual(["wktr", "lean"]);
  });
});

function setup() {
  const fx = makeRepo();
  const bare = join(fx.root, "..", "origin.git");
  execFileSync("git", ["init", "-q", "--bare", bare]);
  fx.git(fx.root, "remote", "add", "origin", bare);
  const push = (ref: string) => spawnSync("git", ["-c", `core.hooksPath=${HOOKS}`, "push", "origin", ref], { cwd: fx.root, encoding: "utf8" });
  expect(push("main").status).toBe(0);
  fx.git(fx.root, "checkout", "-q", "-b", "ci/x");
  const commit = (file: string | null, msg: string) => {
    if (file) fx.commit(fx.root, file, `${msg}\n`);
    fx.git(fx.root, "commit", "-q", ...(file ? ["--amend"] : ["--allow-empty"]), "-m", msg);
  };
  return { fx, push, commit, remoteHas: (ref: string) => fx.git(fx.root, "ls-remote", bare, ref) !== "" };
}

describe("ci push lane check (the hook)", () => {
  it("(a) refuses an empty commit that carries a lane token, and names the lanes that would run", () => {
    const { push, commit, remoteHas } = setup();
    commit(null, "[ci:wktr] ci: request");
    const r = push("ci/x");
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("REFUSED: ci push lane check: ci/x");
    expect(r.stderr).toContain("no file on the branch differs from origin/main");
    expect(r.stderr).toContain("lanes that would run: lean");
    expect(remoteHas("refs/heads/ci/x")).toBe(false);
  });

  it("(b) refuses a push whose tip names no lane", () => {
    const { push, commit, remoteHas } = setup();
    commit("packages/measure-wktr/a.mjs", "fix x");
    let r = push("ci/x");
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("names no lane whose inputs changed");
    expect(r.stderr).toContain("lanes that would run: lean");
    expect(r.stderr).toContain("[ci:");
    expect(remoteHas("refs/heads/ci/x")).toBe(false);
  });

  it("(b) refuses a named lane that reads none of the changed files", () => {
    const { push, commit, remoteHas } = setup();
    commit("docs/x.md", "[ci:wktr] docs only");
    const r = push("ci/x");
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("lanes that would run: lean");
    expect(remoteHas("refs/heads/ci/x")).toBe(false);
  });

  it("passes a push whose tip names a lane that reads a changed file", () => {
    const { fx, push, commit, remoteHas } = setup();
    commit("packages/measure-wktr/a.mjs", "wktr [ci:wktr]");
    const r = push("ci/x");
    expect(r.stderr).not.toContain("lane check");
    expect(r.status, r.stderr).toBe(0);
    expect(remoteHas("refs/heads/ci/x")).toBe(true);
    void fx;
  });

  it("(c) refuses a push that misses a lane the branch's [lanes: ...] trailer requires, and passes once it names it", () => {
    const { push, commit, remoteHas } = setup();
    commit("packages/measure-wktr/a.mjs", "work [ci:wktr]\n\n[lanes: wktr, breakpoint-gate]");
    let r = push("ci/x");
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("the task requires breakpoint-gate");
    expect(r.stderr).toContain("[ci:breakpoint-gate]");
    expect(remoteHas("refs/heads/ci/x")).toBe(false);
    commit("packages/measure-wktr/b.mjs", "more [ci:wktr]\n\n[lanes: wktr]");
    r = push("ci/x");
    expect(r.stderr).not.toContain("the task requires wktr");
  });

  it("passes a lean-only task, and refuses an unknown required lane", () => {
    const { push, commit, remoteHas } = setup();
    commit("lean/Fw/Wire.lean", "lean only\n\n[lanes: lean]");
    const r = push("ci/x");
    expect(r.stderr).not.toContain("lane check");
    expect(remoteHas("refs/heads/ci/x")).toBe(true);
    commit("lean/Fw/Wire2.lean", "[ci:wktr] more\n\n[lanes: nope]");
    const u = push("ci/x");
    expect(u.status).not.toBe(0);
    expect(u.stderr).toContain("nope is no lane");
  });

  it("does not decide main, another branch or a tag", () => {
    const { fx, push, commit } = setup();
    commit(null, "[ci:wktr] empty");
    fx.git(fx.root, "branch", "feature/y");
    fx.git(fx.root, "tag", "v1");
    expect(push("feature/y").status).toBe(0);
    expect(push("v1").status).toBe(0);
    fx.git(fx.root, "checkout", "-q", "main");
    fx.git(fx.root, "commit", "-q", "--allow-empty", "-m", "main empty");
    const r = push("main");
    expect(r.stderr).not.toContain("lane check");
    expect(r.status).toBe(0);
  });
});
