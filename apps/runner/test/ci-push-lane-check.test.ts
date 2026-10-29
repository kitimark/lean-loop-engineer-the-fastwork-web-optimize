import "./land-timeout.ts";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { landCheck, laneReason, lanesTrailer, requiredLanes, type PushFacts } from "../src/ci-push.ts";
import { fileIntents, intentPath, type LandIntent } from "../src/land-intent.ts";
import { landBranch, makePusher, markerMessage, type StartCtx } from "../src/land-remote.ts";

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

  it("the hook's own input path (preciseInputs globs) gives Lean's verdict on every case", async () => {
    const g = (await import(pathToFileURL(join(ROOT, ".github/scripts/changed-inputs.mjs")).href)) as {
      loadIntent(r: string): { lanes: { prefix: string; lanes: { file: string; name: string; token: string; byDefault: boolean }[] } };
      preciseInputs(r: string, f: string): string[] | null;
      decide(a: Record<string, unknown>): { run: boolean };
    };
    const { lanes: il } = g.loadIntent(ROOT);
    const nonMeasuring = il.lanes.filter((l) => head.seeders.includes(l.file)).map((l) => l.name);
    for (const c of cases) {
      const files = c.diff.filter((f) => !c.merged.includes(f));
      const runs = il.lanes
        .filter((l) => g.decide({ event: "push", ref: "refs/heads/ci/x", files, globs: g.preciseInputs(ROOT, l.file) ?? [], msg: c.msgs[0] ?? "", lane: { ...l, prefix: il.prefix }, tip: true, landed: c.landed }).run)
        .map((l) => l.name);
      const v = laneReason(c.msgs, runs, nonMeasuring, files.length === 0);
      expect(v.reason, c.name).toBe(c.reason);
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

  it("(b) refuses a lean-only task whatever its [lanes: lean] trailer says, and refuses an unknown required lane", () => {
    const { push, commit, remoteHas } = setup();
    commit("lean/Fw/Wire.lean", "lean only\n\n[lanes: lean]");
    const r = push("ci/x");
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("only the seeder lane would run");
    expect(remoteHas("refs/heads/ci/x")).toBe(false);
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

type LandRow = { kind: "landCheck"; name: string; intent: LandIntent | null; ref: string; facts: PushFacts; check: string | null; admit: boolean };
const landRows = rows.filter((r) => r.kind === "landCheck") as LandRow[];

describe("Lean golden replay (Fw.Ci.Intent landCheck)", () => {
  it("landBranch and markerMessage of land-remote.ts equal Lean", () => {
    const branches = rows.filter((x) => x.kind === "landBranch");
    const markers = rows.filter((x) => x.kind === "marker");
    expect(branches.length).toBeGreaterThanOrEqual(4);
    expect(markers.length).toBeGreaterThanOrEqual(5);
    for (const r of branches) expect(landBranch(r.task, r.merge, r.again), r.task).toBe(r.branch);
    for (const r of markers) expect(markerMessage({ task: r.task, mergeSha: r.merge, legs: r.legs ? { ...r.legs, cc: [] } : undefined } as StartCtx)).toBe(r.msg);
  });

  it("the hook's landCheck equals Lean on every case, and every check occurs", async () => {
    const g = await import(pathToFileURL(join(ROOT, ".github/scripts/changed-inputs.mjs")).href);
    const names = (g.loadIntent(ROOT) as { lanes: { lanes: { name: string }[] } }).lanes.lanes.map((l) => l.name);
    expect(new Set(landRows.map((r) => r.check))).toEqual(new Set([null, "ok", "branch", "marker", "parent", "tree", "message", "lanes", "process"]));
    for (const r of landRows) {
      const c = r.intent ? landCheck(r.intent, r.ref, r.facts, names) : null;
      expect(c, r.name).toBe(r.check);
      expect(c === "ok", r.name).toBe(r.admit);
    }
  });
});

describe("ci push lane check: fw land's own push (land intent)", () => {
  const landSetup = () => {
    const s = setup();
    s.commit("packages/measure-wktr/a.mjs", "fix x");
    const run = (a: string[]) => execFileSync("git", ["-c", `core.hooksPath=${HOOKS}`, ...a], { cwd: s.fx.root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
    const merge = run(["rev-parse", "HEAD"]);
    const common = run(["rev-parse", "--path-format=absolute", "--git-common-dir"]);
    const marker = () => run(["commit-tree", run(["rev-parse", `${merge}^{tree}`]), "-p", merge, "-m", `land t ${merge.slice(0, 7)}`]);
    return { ...s, run, merge, common, marker, branch: `ci/land-t-${merge.slice(0, 7)}` };
  };
  const ctx = (merge: string) => ({ task: "t", mergeSha: merge, want: { sha: merge, laneId: "land", laneDigest: "d" }, legs: { all: ["check-sh"], gh: [], cc: ["check-sh"] } }) as StartCtx;

  it("passes the land's all-CircleCI push, whose tip names no lane, and drops the intent after the push", async () => {
    const { push, remoteHas, run, merge, common, branch } = landSetup();
    expect(push("ci/x").status).not.toBe(0);
    const out = await makePusher({ git: run, intent: fileIntents(() => common) })(ctx(merge));
    expect(out.branch).toBe(branch);
    expect(run(["log", "-1", "--format=%B", out.marker])).toBe(`land t ${merge.slice(0, 7)}`);
    expect(remoteHas(`refs/heads/${branch}`)).toBe(true);
    expect(existsSync(intentPath(common, out.marker))).toBe(false);
  });

  it("refuses a hand-made ci/land push of the same commit without the intent", () => {
    const { fx, push, remoteHas, marker, branch } = landSetup();
    fx.git(fx.root, "branch", "-f", branch, marker());
    const r = push(branch);
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain(`REFUSED: ci push lane check: ${branch}`);
    expect(r.stderr).not.toContain("land intent");
    expect(remoteHas(`refs/heads/${branch}`)).toBe(false);
  });

  it("refuses an intent whose land process is not pushing, and names the failed check", () => {
    const { fx, push, remoteHas, merge, common, marker, branch } = landSetup();
    const m = marker();
    fx.git(fx.root, "branch", "-f", branch, m);
    const drop = fileIntents(() => common).write({ task: "t", merge, again: false, marker: m, pid: 1, legs: { gh: [], all: ["check-sh"] } });
    try {
      const r = push(branch);
      expect(r.status).not.toBe(0);
      expect(r.stderr).toContain("land intent of t not verified: process");
      expect(remoteHas(`refs/heads/${branch}`)).toBe(false);
    } finally { drop(); }
  });

  it("refuses an intent pushed to another ci branch", () => {
    const { fx, push, remoteHas, merge, common, marker } = landSetup();
    const m = marker();
    fx.git(fx.root, "branch", "-f", "ci/land-x", m);
    const drop = fileIntents(() => common).write({ task: "t", merge, again: false, marker: m, pid: process.pid, legs: { gh: [], all: ["check-sh"] } });
    try {
      const r = push("ci/land-x");
      expect(r.status).not.toBe(0);
      expect(r.stderr).toContain("land intent of t not verified: branch");
      expect(remoteHas("refs/heads/ci/land-x")).toBe(false);
    } finally { drop(); }
  });
});
