import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { check, coreCaller, coreCandidates } from "../src/watch.ts";
import { afterAll, describe, expect, it } from "vitest";
import { pathsFor, type Runner } from "../src/watch-collect.ts";
import { CORE_BIN, CORE_COMMIT, SVC_INPUTS, collectSvcs, parseTouched, readApi, readApiBase } from "../src/watch-svc.ts";

const SHA_A = "a".repeat(40);
const SHA_B = "b".repeat(40);
const SHA_C = "c".repeat(40);
const dirs: string[] = [];
const root = () => { const d = mkdtempSync(join(tmpdir(), "fwsvc-")); dirs.push(d); mkdirSync(join(d, ".fw-console")); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
const writeApi = (d: string, o: object) => writeFileSync(join(d, ".fw-console", "api.json"), JSON.stringify(o));
/** an api.json of a live console-api started at `commit` whose fwcore child was built from `coreCommit` */
const api = (d: string, commit: string, coreCommit: string) => writeApi(d, { port: 1, pid: 42, commit, coreCommit });
const writeCore = (d: string, commit?: string) => {
  mkdirSync(join(d, "lean/.lake/build/bin"), { recursive: true });
  writeFileSync(join(d, CORE_BIN), "bin");
  if (commit) writeFileSync(join(d, CORE_COMMIT), commit + "\n");
};
const setMtime = (path: string, sec: number) => utimesSync(path, sec, sec);
// a fake runner: `touched[base]` lists the paths the range base..main touches; `reflog` answers the reflog call
const gitFake = (touched: Record<string, string[]>, reflog = ""): Runner => async (_c, args) => {
  if (args[0] === "reflog") return reflog;
  const range = args.find((a) => a.endsWith("..main"))!;
  const path = args[args.length - 1]!;
  return (touched[range.slice(0, -6)] ?? []).includes(path) ? SHA_B + "\n" : "";
};
const find = (svcs: Awaited<ReturnType<typeof collectSvcs>>, name: string) => svcs.find((s) => s.name === name);
const changedPaths = (s?: { inputs: { path: string; changed: boolean }[] }) => s?.inputs.filter((i) => i.changed).map((i) => i.path);
const reflogOf = (...e: [string, number][]) => e.map(([s, t]) => `${s} main@{${t}}`).join("\n");

describe("parseTouched", () => {
  it.each([[SHA_B + "\n", true], ["", false], ["  \n", false]])("%j -> %j", (out, v) => expect(parseTouched(out)).toBe(v));
  it.each([["garbage"], [null], [{ missing: true }]])("%j -> null", (out) => expect(parseTouched(out as never)).toBeNull());
});

describe("readApi / readApiBase", () => {
  it("reads the start commit and the core build record of a live console-api; none for a dead pid or a missing file", () => {
    const d = root(); const p = pathsFor(d);
    expect(readApi(p, () => true)).toBeNull(); // no api.json
    writeApi(d, { port: 1, pid: 42 });
    expect(readApi(p, () => true)).toEqual({ commit: null, coreCommit: null, coreUnknown: null }); // alive, nothing identified
    writeApi(d, { port: 1, pid: 42, commit: "abc", coreCommit: "xyz" });
    expect(readApiBase(p, () => true)).toBeNull(); // not a full sha
    writeApi(d, { port: 1, pid: 42, commit: SHA_A, coreCommit: SHA_B, startedAt: 1 });
    expect(readApi(p, () => true)).toEqual({ commit: SHA_A, coreCommit: SHA_B, coreUnknown: null });
    writeApi(d, { port: 1, pid: 42, commit: SHA_A, coreUnknown: "why" });
    expect(readApi(p, () => true)).toEqual({ commit: SHA_A, coreCommit: null, coreUnknown: "why" });
    expect(readApi(p, () => false)).toBeNull(); // crashed: stale file, pid gone
  });
});

describe("collectSvcs (fake runner)", () => {
  it("each piece is judged against its own base: console-api by its start commit, its fwcore child by the child's build commit, the disk binary by its record", async () => {
    const d = root(); api(d, SHA_A, SHA_B); writeCore(d, SHA_C);
    const svcs = await collectSvcs(pathsFor(d), gitFake({ [SHA_A]: ["apps/console-api/src"], [SHA_B]: ["lean/Fw"], [SHA_C]: [] }), () => true);
    expect(svcs.map((s) => s.name)).toEqual(["console-api", "fwcore"]);
    expect(find(svcs, "console-api")!.inputs.map((i) => i.path)).toEqual([...SVC_INPUTS["console-api"]!, ...SVC_INPUTS.fwcore!]);
    expect(changedPaths(find(svcs, "console-api"))).toEqual(["apps/console-api/src", "lean/Fw"]);
    expect(changedPaths(find(svcs, "fwcore"))).toEqual([]);
    expect(svcs.every((s) => s.unknown === undefined)).toBe(true);
  });
  it("console-api inputs include its package.json and the lockfile", () => {
    expect(SVC_INPUTS["console-api"]).toEqual(expect.arrayContaining(["apps/console-api/package.json", "pnpm-lock.yaml"]));
  });
  it("asks for the first-parent range base..main with the path after --", async () => {
    const d = root(); api(d, SHA_A, SHA_B);
    const seen: string[][] = [];
    await collectSvcs(pathsFor(d), async (_c, a, _t, cwd) => { seen.push([...a, String(cwd)]); return ""; }, () => true);
    expect(seen[0]).toEqual(["log", "-1", "--first-parent", "--format=%H", `${SHA_A}..main`, "--", "apps/console-api/src", d]);
  });
  it("[] when nothing runs and nothing is built; the disk binary alone when console-api is down", async () => {
    const d = root();
    expect(await collectSvcs(pathsFor(d), gitFake({}), () => true)).toEqual([]);
    writeCore(d, SHA_B);
    expect((await collectSvcs(pathsFor(d), gitFake({}), () => true)).map((s) => s.name)).toEqual(["fwcore"]);
  });
  it("a live console-api with no start commit or no core build commit is unknown with the reason, never skipped", async () => {
    const d = root();
    writeApi(d, { port: 1, pid: 42 }); // an old api.json
    let s = find(await collectSvcs(pathsFor(d), gitFake({}), () => true), "console-api")!;
    expect(s.unknown).toBe("api.json records no start commit; api.json records no core build commit");
    expect(s.inputs).toEqual([]);
    writeApi(d, { port: 1, pid: 42, commit: SHA_A, coreUnknown: "no move of main at or before the binary" });
    s = find(await collectSvcs(pathsFor(d), gitFake({ [SHA_A]: ["apps/console-api/src"] }), () => true), "console-api")!;
    expect(s.unknown).toBe("no move of main at or before the binary");
    expect(changedPaths(s)).toEqual(["apps/console-api/src"]); // the own group is still judged
  });
  it("a git failure on one service never drops the other", async () => {
    const d = root(); api(d, SHA_A, SHA_B); writeCore(d, SHA_C);
    const failA: Runner = async (c, a, t, cwd) => (a.some((x) => x.startsWith(SHA_A)) ? null : gitFake({ [SHA_C]: ["lean/Fw"] })(c, a, t, cwd));
    const svcs = await collectSvcs(pathsFor(d), failA, () => true);
    expect(find(svcs, "console-api")!.unknown).toContain("git failed");
    expect(find(svcs, "fwcore")).toEqual({ name: "fwcore", inputs: SVC_INPUTS.fwcore!.map((path) => ({ path, changed: path === "lean/Fw" })) });
    const failAll = await collectSvcs(pathsFor(d), async () => null, () => true);
    expect(failAll.map((s) => [s.name, s.unknown !== undefined])).toEqual([["console-api", true], ["fwcore", true]]);
  });
  it("a rebuild on disk without a console-api restart leaves console-api stale; the restart clears it (Fw.Obs.rebuild_without_restart_api_stale)", async () => {
    const d = root();
    const touched = { [SHA_A]: ["lean/Fw"], [SHA_B]: [] }; // a lean land happened after A, nothing after B
    writeCore(d, SHA_A); api(d, SHA_A, SHA_A);
    let svcs = await collectSvcs(pathsFor(d), gitFake(touched), () => true);
    expect(changedPaths(find(svcs, "fwcore"))).toEqual(["lean/Fw"]);
    expect(changedPaths(find(svcs, "console-api"))).toEqual(["lean/Fw"]);
    writeCore(d, SHA_B); // fwcore-build.sh at main: the disk is fresh, the child is not
    svcs = await collectSvcs(pathsFor(d), gitFake(touched), () => true);
    expect(changedPaths(find(svcs, "fwcore"))).toEqual([]);
    expect(changedPaths(find(svcs, "console-api"))).toEqual(["lean/Fw"]); // still stale
    api(d, SHA_B, SHA_B); // console-api restarted (new child from the fresh binary)
    svcs = await collectSvcs(pathsFor(d), gitFake(touched), () => true);
    expect(svcs.map((s) => changedPaths(s))).toEqual([[], []]);
  });
  it("restarting console-api without a rebuild: the new child is as old as the disk, so both stay stale", async () => {
    const d = root(); writeCore(d, SHA_A);
    const touched = { [SHA_A]: ["lean/Fw"], [SHA_B]: [] };
    api(d, SHA_B, SHA_A); // restarted at B, child spawned from the binary built at A
    const svcs = await collectSvcs(pathsFor(d), gitFake(touched), () => true);
    expect(changedPaths(find(svcs, "fwcore"))).toEqual(["lean/Fw"]);
    expect(changedPaths(find(svcs, "console-api"))).toEqual(["lean/Fw"]);
  });
  it("the disk binary's base: a record not older than the binary wins; an older record is ignored for the reflog; no record uses the reflog; nothing identifies it: unknown", async () => {
    const d = root(); writeCore(d, SHA_C);
    const bin = join(d, CORE_BIN); const rec = join(d, CORE_COMMIT);
    const log = reflogOf([SHA_B, 1030], [SHA_A, 100]);
    const touched = { [SHA_A]: ["lean/Fw"], [SHA_B]: [], [SHA_C]: ["lean/Main.lean"] };
    setMtime(bin, 1000); setMtime(rec, 1000); // record as new as the binary
    expect(changedPaths(find(await collectSvcs(pathsFor(d), gitFake(touched, log), () => true), "fwcore"))).toEqual(["lean/Main.lean"]);
    setMtime(rec, 900); // plain `lake build` after an old script build: record older than the binary
    expect(changedPaths(find(await collectSvcs(pathsFor(d), gitFake(touched, log), () => true), "fwcore"))).toEqual(["lean/Fw"]);
    rmSync(rec); // no record at all
    expect(changedPaths(find(await collectSvcs(pathsFor(d), gitFake(touched, log), () => true), "fwcore"))).toEqual(["lean/Fw"]);
    const none = find(await collectSvcs(pathsFor(d), gitFake(touched, reflogOf([SHA_B, 1030])), () => true), "fwcore")!;
    expect(none.unknown).toBe("no move of main at or before the binary");
    const tie = find(await collectSvcs(pathsFor(d), gitFake(touched, reflogOf([SHA_B, 100], [SHA_A, 100])), () => true), "fwcore")!;
    expect(tie.unknown).toContain("same second");
    const gitDown = find(await collectSvcs(pathsFor(d), async () => null, () => true), "fwcore")!;
    expect(gitDown.unknown).toBe("git reflog of main failed");
  });
});

// real history, the fw land pre-lock path: the merge commit C is built with commit-tree BEFORE the checks (dated
// T - 1 min), the binary is built (plain `lake build`, no record) and console-api starts at T from the old main, and
// main is fast-forwarded to C at T + 1 min. A commit-time comparison misses this; the first-parent range does not.
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
    const c = sh(d, iso(T - 60_000), "commit-tree", "-p", old, "-p", feat, "-m", "land", `${feat}^{tree}`);
    return { d, old, c };
  }

  it("a console-api started in the window between commit-tree and the ff is stale; a restart after the ff clears it", async () => {
    const { d, old, c } = setup();
    api(d, old, old); // started at T, main still at old
    sh(d, iso(T + 60_000), "merge", "--ff-only", "-q", c); // main moves at T + 1 min
    const stale = await collectSvcs(pathsFor(d), real, () => true);
    expect(changedPaths(find(stale, "console-api"))).toEqual(["apps/console-api/src", "lean/Fw"]);
    const head = sh(d, null, "rev-parse", "main");
    api(d, head, head); // restart records the current main
    expect(changedPaths(find(await collectSvcs(pathsFor(d), real, () => true), "console-api"))).toEqual([]);
  });

  it("a branch merged --no-ff is seen at the merge (first-parent)", async () => {
    const { d, old } = setup();
    sh(d, iso(T + 300_000), "merge", "--no-ff", "-qm", "land", "feat");
    api(d, old, old);
    expect(changedPaths(find(await collectSvcs(pathsFor(d), real, () => true), "console-api"))).toEqual(["apps/console-api/src", "lean/Fw"]);
  });

  it("a plain `lake build` (no record) in the pre-lock window: the reflog names the old head, so the land is seen as stale", async () => {
    const { d, c } = setup();
    writeCore(d); // no .commit file, as with a plain `lake build`
    setMtime(join(d, CORE_BIN), T / 1000); // built at T from `old` (the reflog of main: base at T - 1 h)
    sh(d, iso(T + 60_000), "merge", "--ff-only", "-q", c);
    const fw = find(await collectSvcs(pathsFor(d), real, () => true), "fwcore")!;
    expect(fw.unknown).toBeUndefined();
    expect(changedPaths(fw)).toEqual(["lean/Fw"]);
    // built after the land (a later build): the newest move at or before the binary is the land itself, clean
    setMtime(join(d, CORE_BIN), (T + 120_000) / 1000);
    expect(changedPaths(find(await collectSvcs(pathsFor(d), real, () => true), "fwcore"))).toEqual([]);
  });

  it("a binary older than every move of main is unknown (alert), not silence", async () => {
    const { d, c } = setup();
    sh(d, iso(T + 60_000), "merge", "--ff-only", "-q", c);
    writeCore(d);
    setMtime(join(d, CORE_BIN), (T - 7200_000) / 1000);
    expect(find(await collectSvcs(pathsFor(d), real, () => true), "fwcore")!.unknown).toBe("no move of main at or before the binary");
  });
});

// end to end with the real fwcore binary (skipped when it is not built)
const repo = resolve(import.meta.dirname, "../../..");
describe.skipIf(!existsSync(join(repo, "lean/.lake/build/bin/fwcore")))("svc.stale and svc.unknown through fwcore", () => {
  const core = coreCaller(coreCandidates(repo, repo, {}));
  const snap = async (writeIt: (d: string) => void, touched: Record<string, string[]>) => {
    const d = root(); writeIt(d);
    const svcs = await collectSvcs(pathsFor(d), gitFake(touched), () => true);
    return { now: 10 * 3600_000, params: {}, agents: [], lead: { lastToolAt: null, noteAt: null },
      system: { load1: 0, loadFloor: 0, memPressure: "normal", diskFreeGB: 100, simLock: { holder: null, since: null },
        docker: [], worktrees: 0, consolePids: [], ci: [], services: [], keep: [], svcs, stale: [] } } as never;
  };
  it("workflow-claim landed after console-api started: svc.stale names the changed paths", async () => {
    const h = await check(await snap((d) => api(d, SHA_A, SHA_A), { [SHA_A]: ["apps/console-api/src"] }), core);
    const a = h.alerts.filter((x) => x.code === "svc.stale");
    expect(a.map((x) => [x.subject, x.detail])).toEqual([["console-api", "changed on main since its commit: apps/console-api/src"]]);
  });
  it("a restart (new start commit, empty range) clears it", async () => {
    const h = await check(await snap((d) => api(d, SHA_B, SHA_B), { [SHA_A]: ["apps/console-api/src"] }), core);
    expect(h.alerts.filter((x) => x.code === "svc.stale")).toEqual([]);
  });
  it("a lean land with a rebuild but no restart: console-api's fwcore child is stale (svc.stale console-api lean/Fw)", async () => {
    const h = await check(await snap((d) => { writeCore(d, SHA_B); api(d, SHA_B, SHA_A); }, { [SHA_A]: ["lean/Fw"] }), core);
    expect(h.alerts.filter((x) => x.code === "svc.stale").map((x) => [x.subject, x.detail])).toEqual([["console-api", "changed on main since its commit: lean/Fw"]]);
  });
  it("code that cannot be identified is svc.unknown with the reason", async () => {
    const h = await check(await snap((d) => { writeCore(d); writeApi(d, { port: 1, pid: 42, commit: SHA_A }); }, {}), core);
    const a = h.alerts.filter((x) => x.code === "svc.unknown");
    expect(a.map((x) => x.subject).sort()).toEqual(["console-api", "fwcore"]);
    expect(a.find((x) => x.subject === "console-api")!.detail).toBe("cannot identify the code that runs: api.json records no core build commit");
  });
});
