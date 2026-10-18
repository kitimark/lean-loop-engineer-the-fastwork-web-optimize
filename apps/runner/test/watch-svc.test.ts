import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { check, coreCaller, coreCandidates } from "../src/watch.ts";
import { afterAll, describe, expect, it } from "vitest";
import { pathsFor, type Runner } from "../src/watch-collect.ts";
import { CORE_BIN, CORE_COMMIT, SVC_INPUTS, collectSvcs, parseTouched, readApiBase } from "../src/watch-svc.ts";

const SHA_A = "a".repeat(40);
const SHA_B = "b".repeat(40);
const dirs: string[] = [];
const root = () => { const d = mkdtempSync(join(tmpdir(), "fwsvc-")); dirs.push(d); mkdirSync(join(d, ".fw-console")); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
const writeApi = (d: string, o: object) => writeFileSync(join(d, ".fw-console", "api.json"), JSON.stringify(o));
const writeCore = (d: string, commit?: string) => {
  mkdirSync(join(d, "lean/.lake/build/bin"), { recursive: true });
  writeFileSync(join(d, CORE_BIN), "bin");
  if (commit) writeFileSync(join(d, CORE_COMMIT), commit + "\n");
};
// a fake runner: `touched[base]` lists the paths the range base..main touches
const gitFake = (touched: Record<string, string[]>): Runner => async (_c, args) => {
  const range = args.find((a) => a.endsWith("..main"))!;
  const path = args[args.length - 1]!;
  return (touched[range.slice(0, -6)] ?? []).includes(path) ? SHA_B + "\n" : "";
};
const find = (svcs: Awaited<ReturnType<typeof collectSvcs>>, name: string) => svcs!.find((s) => s.name === name);
const changedPaths = (s?: { inputs: { path: string; changed: boolean }[] }) => s?.inputs.filter((i) => i.changed).map((i) => i.path);

describe("parseTouched", () => {
  it.each([[SHA_B + "\n", true], ["", false], ["  \n", false]])("%j -> %j", (out, v) => expect(parseTouched(out)).toBe(v));
  it.each([["garbage"], [null], [{ missing: true }]])("%j -> null", (out) => expect(parseTouched(out as never)).toBeNull());
});

describe("readApiBase", () => {
  it("reads the start commit of a live console-api; none for a dead pid, a missing file, an old api.json or a non-sha", () => {
    const d = root(); const p = pathsFor(d);
    expect(readApiBase(p, () => true)).toBeNull(); // no api.json
    writeApi(d, { port: 1, pid: 42 });
    expect(readApiBase(p, () => true)).toBeNull(); // no commit
    writeApi(d, { port: 1, pid: 42, commit: "abc" });
    expect(readApiBase(p, () => true)).toBeNull(); // not a full sha
    writeApi(d, { port: 1, pid: 42, commit: SHA_A, startedAt: 1 });
    expect(readApiBase(p, () => true)).toBe(SHA_A);
    expect(readApiBase(p, () => false)).toBeNull(); // crashed: stale file, pid gone
  });
});

describe("collectSvcs (fake runner)", () => {
  it("each service is judged against its own base: console-api by its start commit, fwcore by its build commit", async () => {
    const d = root(); writeApi(d, { port: 1, pid: 42, commit: SHA_A }); writeCore(d, SHA_B);
    const svcs = await collectSvcs(pathsFor(d), gitFake({ [SHA_A]: ["apps/console-api/src"], [SHA_B]: ["lean/Fw"] }), () => true);
    expect(svcs!.map((s) => s.name)).toEqual(["console-api", "fwcore"]);
    expect(find(svcs, "console-api")!.inputs.map((i) => i.path)).toEqual(SVC_INPUTS["console-api"]);
    expect(changedPaths(find(svcs, "console-api"))).toEqual(["apps/console-api/src"]); // the workflow-claim landing
    expect(changedPaths(find(svcs, "fwcore"))).toEqual(["lean/Fw"]);
  });
  it("asks for the first-parent range base..main with the path after --", async () => {
    const d = root(); writeApi(d, { port: 1, pid: 42, commit: SHA_A });
    const seen: string[][] = [];
    await collectSvcs(pathsFor(d), async (_c, a, _t, cwd) => { seen.push([...a, String(cwd)]); return ""; }, () => true);
    expect(seen[0]).toEqual(["log", "-1", "--first-parent", "--format=%H", `${SHA_A}..main`, "--", "apps/console-api/src", d]);
  });
  it("[] when neither is running or built; fwcore alone when console-api is down; null (carry forward) when a call fails", async () => {
    const d = root();
    expect(await collectSvcs(pathsFor(d), gitFake({}), () => true)).toEqual([]);
    writeCore(d, SHA_B);
    expect((await collectSvcs(pathsFor(d), gitFake({}), () => true))!.map((s) => s.name)).toEqual(["fwcore"]);
    writeApi(d, { port: 1, pid: 42, commit: SHA_A });
    expect(await collectSvcs(pathsFor(d), async () => null, () => true)).toBeNull();
  });
  it("restarting console-api (new start commit) does not refresh fwcore; a rebuild does", async () => {
    const d = root(); writeCore(d, SHA_A);
    const touched = { [SHA_A]: ["lean/Fw"], [SHA_B]: [] };
    writeApi(d, { port: 1, pid: 42, commit: SHA_A });
    expect(changedPaths(find(await collectSvcs(pathsFor(d), gitFake(touched), () => true), "fwcore"))).toEqual(["lean/Fw"]);
    writeApi(d, { port: 2, pid: 43, commit: SHA_B }); // restart at the current main
    const after = await collectSvcs(pathsFor(d), gitFake(touched), () => true);
    expect(changedPaths(find(after, "console-api"))).toEqual([]);
    expect(changedPaths(find(after, "fwcore"))).toEqual(["lean/Fw"]); // Fw.Obs.Stack.restart_without_build_stale
    writeCore(d, SHA_B); // fwcore-build.sh at main
    expect(changedPaths(find(await collectSvcs(pathsFor(d), gitFake(touched), () => true), "fwcore"))).toEqual([]);
  });
});

// real history, the fw land pre-lock path: the merge commit C is built with commit-tree BEFORE the checks (dated
// T - 1 min), console-api starts at T from the old main, and main is fast-forwarded to C at T + 1 min. A commit-time
// comparison misses this; the first-parent range start..main does not.
describe("collectSvcs with a real history", () => {
  const sh = (cwd: string, date: string | null, ...args: string[]) => execFileSync("git", args, {
    cwd, encoding: "utf8",
    env: { ...process.env, GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid",
      ...(date ? { GIT_AUTHOR_DATE: date, GIT_COMMITTER_DATE: date } : {}) },
  }).trim();
  const real: Runner = async (c, args, _t, cwd) => { try { return execFileSync(c, args, { cwd, encoding: "utf8" }); } catch { return null; } };
  const iso = (ms: number) => new Date(ms).toISOString();
  const T = 1_760_000_000_000;

  function setup() {
    const d = root(); sh(d, null, "init", "-q", "-b", "main");
    mkdirSync(join(d, "apps/console-api/src"), { recursive: true });
    mkdirSync(join(d, "lean/Fw"), { recursive: true });
    writeFileSync(join(d, "apps/console-api/src/a.ts"), "1\n"); writeFileSync(join(d, "lean/Fw/A.lean"), "1\n");
    sh(d, null, "add", "-A"); sh(d, iso(T - 3600_000), "commit", "-qm", "base");
    const old = sh(d, null, "rev-parse", "HEAD");
    sh(d, null, "checkout", "-q", "-b", "feat");
    writeFileSync(join(d, "apps/console-api/src/a.ts"), "2\n"); writeFileSync(join(d, "lean/Fw/A.lean"), "2\n");
    sh(d, iso(T - 600_000), "commit", "-qam", "branch work");
    const feat = sh(d, null, "rev-parse", "HEAD");
    sh(d, null, "checkout", "-q", "main");
    // fw land: commit-tree with two parents, dated before the checks (T - 1 min); main moves later
    const c = sh(d, iso(T - 60_000), "commit-tree", "-p", old, "-p", feat, "-m", "land", `${feat}^{tree}`);
    return { d, old, c };
  }

  it("a console-api started in the window between commit-tree and the ff is stale; a restart after the ff clears it", async () => {
    const { d, old, c } = setup();
    writeApi(d, { port: 1, pid: 42, commit: old }); // started at T, main still at old
    sh(d, iso(T + 60_000), "merge", "--ff-only", "-q", c); // main moves at T + 1 min
    const stale = await collectSvcs(pathsFor(d), real, () => true);
    expect(changedPaths(find(stale, "console-api"))).toEqual(["apps/console-api/src"]);
    writeApi(d, { port: 2, pid: 43, commit: sh(d, null, "rev-parse", "main") }); // restart records the current main
    expect(changedPaths(find(await collectSvcs(pathsFor(d), real, () => true), "console-api"))).toEqual([]);
  });

  it("a branch merged --no-ff is seen at the merge (first-parent)", async () => {
    const { d, old } = setup();
    sh(d, iso(T + 300_000), "merge", "--no-ff", "-qm", "land", "feat");
    writeApi(d, { port: 1, pid: 42, commit: old });
    expect(changedPaths(find(await collectSvcs(pathsFor(d), real, () => true), "console-api"))).toEqual(["apps/console-api/src"]);
  });

  it("fwcore: stale after a lean land following its build; a console-api restart leaves it stale; a rebuild at main clears it", async () => {
    const { d, old, c } = setup();
    writeCore(d, old);
    writeApi(d, { port: 1, pid: 42, commit: old });
    sh(d, iso(T + 60_000), "merge", "--ff-only", "-q", c);
    const head = sh(d, null, "rev-parse", "main");
    expect(changedPaths(find(await collectSvcs(pathsFor(d), real, () => true), "fwcore"))).toEqual(["lean/Fw"]);
    writeApi(d, { port: 2, pid: 43, commit: head }); // restart without a rebuild
    const mid = await collectSvcs(pathsFor(d), real, () => true);
    expect(changedPaths(find(mid, "console-api"))).toEqual([]);
    expect(changedPaths(find(mid, "fwcore"))).toEqual(["lean/Fw"]);
    writeCore(d, head); // docs/team/tools/fwcore-build.sh at main
    expect(changedPaths(find(await collectSvcs(pathsFor(d), real, () => true), "fwcore"))).toEqual([]);
  });

  it("without a build record the binary mtime decides (premise): built after the land is clean, before it is stale", async () => {
    const { d, c } = setup();
    sh(d, iso(T + 60_000), "merge", "--ff-only", "-q", c);
    writeCore(d); // no .commit file
    const bin = join(d, CORE_BIN);
    utimesSync(bin, (T + 120_000) / 1000, (T + 120_000) / 1000);
    expect(changedPaths(find(await collectSvcs(pathsFor(d), real, () => true), "fwcore"))).toEqual([]);
    utimesSync(bin, (T - 1_800_000) / 1000, (T - 1_800_000) / 1000); // built from `base` (committed T - 1 h), before the land
    expect(changedPaths(find(await collectSvcs(pathsFor(d), real, () => true), "fwcore"))).toEqual(["lean/Fw"]);
  });
});

// end to end with the real fwcore binary (skipped when it is not built)
const repo = resolve(import.meta.dirname, "../../..");
describe.skipIf(!existsSync(join(repo, "lean/.lake/build/bin/fwcore")))("svc.stale through fwcore", () => {
  const core = coreCaller(coreCandidates(repo, repo, {}));
  const snap = async (touched: Record<string, string[]>, startCommit = SHA_A) => {
    const d = root(); writeApi(d, { port: 1, pid: 42, commit: startCommit });
    const svcs = await collectSvcs(pathsFor(d), gitFake(touched), () => true);
    return { now: 10 * 3600_000, params: {}, agents: [], lead: { lastToolAt: null, noteAt: null },
      system: { load1: 0, loadFloor: 0, memPressure: "normal", diskFreeGB: 100, simLock: { holder: null, since: null },
        docker: [], worktrees: 0, consolePids: [], ci: [], services: [], keep: [], svcs, stale: [] } } as never;
  };
  it("workflow-claim landed after console-api started: svc.stale names the changed paths", async () => {
    const h = await check(await snap({ [SHA_A]: ["apps/console-api/src"] }), core);
    const a = h.alerts.filter((x) => x.code === "svc.stale");
    expect(a.map((x) => [x.subject, x.detail])).toEqual([["console-api", "changed on main since its commit: apps/console-api/src"]]);
  });
  it("a restart (new start commit, empty range) clears it", async () => {
    const h = await check(await snap({ [SHA_A]: ["apps/console-api/src"] }, SHA_B), core);
    expect(h.alerts.filter((x) => x.code === "svc.stale")).toEqual([]);
  });
});
