import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { check, coreCaller, coreCandidates } from "../src/watch.ts";
import { afterAll, describe, expect, it } from "vitest";
import { pathsFor, type Runner } from "../src/watch-collect.ts";
import { SVC_INPUTS, collectSvcs, parseCommitTime, readApiStart } from "../src/watch-svc.ts";

// fake clock: console-api started at T0 (ms); a fake git answers the last commit time (seconds) of each input path
const T0 = 1_760_000_000_000;
const dirs: string[] = [];
const root = () => { const d = mkdtempSync(join(tmpdir(), "fwsvc-")); dirs.push(d); mkdirSync(join(d, ".fw-console")); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
const writeApi = (d: string, o: object) => writeFileSync(join(d, ".fw-console", "api.json"), JSON.stringify(o));
const gitAt = (times: Record<string, number>): Runner => async (_c, args) => {
  const path = args[args.length - 1]!;
  return path in times ? String(Math.floor(times[path]! / 1000)) + "\n" : "";
};

describe("parseCommitTime", () => {
  it.each([["1760000000\n", 1_760_000_000_000], ["", 0], ["  \n", 0]])("%j -> %j", (out, ms) => expect(parseCommitTime(out)).toBe(ms));
  it.each([["garbage"], [null], [{ missing: true }]])("%j -> null", (out) => expect(parseCommitTime(out as never)).toBeNull());
});

describe("readApiStart", () => {
  it("reads startedAt of a live console-api; none for a dead pid, a missing file or an old api.json", () => {
    const d = root(); const p = pathsFor(d);
    expect(readApiStart(p, () => true)).toBeNull(); // no api.json
    writeApi(d, { port: 1, pid: 42 });
    expect(readApiStart(p, () => true)).toBeNull(); // written by an old console-api: no startedAt
    writeApi(d, { port: 1, pid: 42, startedAt: T0, commit: "abc" });
    expect(readApiStart(p, () => true)).toBe(T0);
    expect(readApiStart(p, () => false)).toBeNull(); // crashed: stale file, pid gone
  });
});

describe("collectSvcs", () => {
  it("reports console-api and fwcore, both at console-api's start, with each group's last change on main", async () => {
    const d = root(); writeApi(d, { port: 1, pid: 42, startedAt: T0 });
    const svcs = await collectSvcs(pathsFor(d), gitAt({ "apps/console-api/src": T0 + 36 * 60_000, "lean/Fw": T0 - 5000 }), () => true);
    expect(svcs!.map((s) => s.name)).toEqual(["console-api", "fwcore"]);
    expect(svcs!.every((s) => s.startedAt === T0)).toBe(true);
    const api = svcs![0]!.inputs;
    expect(api.map((i) => i.path)).toEqual(SVC_INPUTS["console-api"]);
    expect(api.find((i) => i.path === "apps/console-api/src")!.changedAt).toBe(T0 + 36 * 60_000); // the workflow-claim landing
    expect(api.find((i) => i.path === "packages/contracts/src")!.changedAt).toBe(0);
    expect(svcs![1]!.inputs.find((i) => i.path === "lean/Fw")!.changedAt).toBe(T0 - 5000);
  });
  it("calls git on main with the path after --", async () => {
    const d = root(); writeApi(d, { port: 1, pid: 42, startedAt: T0 });
    const seen: string[][] = [];
    await collectSvcs(pathsFor(d), async (_c, a, _t, cwd) => { seen.push([...a, String(cwd)]); return ""; }, () => true);
    expect(seen[0]).toEqual(["log", "-1", "--format=%ct", "main", "--", "apps/console-api/src", d]);
  });
  it("[] when console-api is not running; null (carry forward) when git fails", async () => {
    const d = root();
    expect(await collectSvcs(pathsFor(d), gitAt({}), () => true)).toEqual([]);
    writeApi(d, { port: 1, pid: 42, startedAt: T0 });
    expect(await collectSvcs(pathsFor(d), async () => null, () => true)).toBeNull();
  });
});

// end to end with the real fwcore binary (skipped when it is not built): the incident, as a fake-clock replay
const repo = resolve(import.meta.dirname, "../../..");
describe.skipIf(!existsSync(join(repo, "lean/.lake/build/bin/fwcore")))("svc.stale through fwcore", () => {
  const core = coreCaller(coreCandidates(repo, repo, {}));
  const snap = async (changes: Record<string, number>, startedAt = T0) => {
    const d = root(); writeApi(d, { port: 1, pid: 42, startedAt });
    const svcs = await collectSvcs(pathsFor(d), gitAt(changes), () => true);
    return { now: startedAt + 10 * 3600_000, params: {}, agents: [], lead: { lastToolAt: null, noteAt: null },
      system: { load1: 0, loadFloor: 0, memPressure: "normal", diskFreeGB: 100, simLock: { holder: null, since: null },
        docker: [], worktrees: 0, consolePids: [], ci: [], services: [], keep: [], svcs, stale: [] } } as never;
  };
  it("workflow-claim landed 36 min after console-api started: svc.stale names the changed paths", async () => {
    const h = await check(await snap({ "apps/console-api/src": T0 + 36 * 60_000 }), core);
    const a = h.alerts.filter((x) => x.code === "svc.stale");
    expect(a.map((x) => [x.subject, x.detail])).toEqual([["console-api", "changed since start: apps/console-api/src"]]);
  });
  it("a restart after the landing clears it", async () => {
    const h = await check(await snap({ "apps/console-api/src": T0 + 36 * 60_000 }, T0 + 40 * 60_000), core);
    expect(h.alerts.filter((x) => x.code === "svc.stale")).toEqual([]);
  });
});
