// The resource baseline sampler (task sup-baseline): the TS classifier and verdict replay the Lean golden
// (packages/contracts/golden/obs/sup-health.jsonl, written by lean/scripts/SupHealthGolden.lean); the parsers, the sample
// builder and the timer are checked on fixed `top` / `ps` / `sysctl` text and a fake runner.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, afterEach, describe, expect, it, vi } from "vitest";
import {
  PROC_KINDS, HEAVY_KINDS, KIND_TABLE, RES_PARAMS, SUP_FILE, buildSample, ensureSampler, footMB, joinProcs, kindsOf, parseArgs, parseFreePct, parseProcs,
  parseSize, parseSwap, parseTop, reduceKinds, resVerdict, sampleOnce, stopSamplers, trippedBy, udidOf,
  type Device, type Paths, type ProcRow, type ProcKind, type ResObs, type ResParams, type Runner, type SupSample,
} from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const golden = readFileSync(join(root, "packages/contracts/golden/obs/sup-health.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown> & { op: string }; response: Record<string, unknown> });

const dirs: string[] = [];
const tmp = () => { const d = mkdtempSync(join(tmpdir(), "fw-sup-")); dirs.push(d); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
afterEach(() => { stopSamplers(); vi.useRealTimers(); });
const pathsIn = (d: string): Paths => ({ root: d, consoleDir: join(d, ".fw-console"), home: d, projectsDir: join(d, "projects") });

describe("the Lean golden", () => {
  it("lists the kinds and the heavy ones as the TS tables do", () => {
    const g = golden.find((x) => x.request.op === "sup.kinds")!;
    expect(g.response.kinds).toEqual([...PROC_KINDS]);
    expect(g.response.heavy).toEqual(PROC_KINDS.filter((k) => HEAVY_KINDS.has(k)));
  });
  it("the TS name table equals Lean's kindTable, entry for entry and in order", () => {
    const g = golden.find((x) => x.request.op === "sup.table")!;
    expect([...KIND_TABLE]).toEqual(g.response.table);
  });
  const procsOf = (g: { request: Record<string, unknown> }) => g.request.procs as ProcRow[];
  const devsOf = (g: { request: Record<string, unknown> }) => g.request.devices as Device[];
  for (const g of golden.filter((x) => x.request.op === "sup.classify")) {
    it(`classify: ${g.name}`, () => { expect(kindsOf(devsOf(g), procsOf(g))).toEqual(g.response.kinds); });
  }
  for (const g of golden.filter((x) => x.request.op === "sup.sample")) {
    it(`sample: ${g.name}`, () => {
      const kinds = kindsOf(devsOf(g), procsOf(g));
      expect(kinds).toEqual(g.response.kinds);
      const o = g.request.obs as ResObs;
      expect(resVerdict(g.request.params as ResParams, { ...o, procs: kinds })).toBe(g.response.verdict);
    });
  }
  for (const g of golden.filter((x) => x.request.op === "sup.tripped")) {
    it(`tripped: ${g.name}`, () => { expect(trippedBy(g.request.params as ResParams, g.request.obs as ResObs)).toEqual(g.response); });
  }
  for (const g of golden.filter((x) => x.request.op === "sup.verdict")) {
    it(`verdict: ${g.name}`, () => {
      const o = g.request.obs as Omit<ResObs, "procs"> & { procs: ProcKind[] };
      expect(resVerdict(g.request.params as ResParams, o)).toBe(g.response.verdict);
    });
  }
  it("the golden keeps the two cases the classifier exists for: background processes are quiet, a booted fw- device is busy", () => {
    expect(golden.find((x) => x.name.startsWith("CoreSimulatorService, system WebContent and lake serve"))?.response.verdict).toBe("quiet");
    expect(golden.find((x) => x.name === "a booted fw- device subtree is busy")?.response.verdict).toBe("busy");
  });
  it("the default parameters are the ones the golden's default cases use", () => {
    const g = golden.find((x) => x.name === "an idle machine is quiet")!;
    expect(g.request.params).toEqual(RES_PARAMS);
  });
});

const TOP = [
  "Processes: 668 total, 11 running, 657 sleeping, 4037 threads ",
  "Load Avg: 40.82, 77.25, 51.13 ",
  "PhysMem: 14G used (2739M wired, 5255M compressor), 942M unused.",
  "VM: 342T vsize, 57G framework vsize, 8217441(0) swapins, 12684670(0) swapouts.",
  "",
  "PID    MEM   CMPRS",
  "92347  1245M 199M ",
  "3093   947M+ 907M ",
  "9722   2G    871M-",
  "101    512K  0B",
  "7      12M   1M",
  "junk line 1 2",
].join("\n");
const PS = [
  "    1     0 /sbin/launchd",
  "92347     1 /Users/x/.nvm/versions/node/v24.22.0/bin/node",
  " 3093 92347 /Applications/Chromium.app/Contents/Frameworks/Chromium Helper (Renderer).app/Contents/MacOS/Chromium Helper (Renderer)",
  " 9722 92347 /Users/x/lean/.lake/build/bin/lean",
  "  101     1 pnpm run build",
].join("\n");
const ARGS = " 9722 /Users/x/lean/.lake/build/bin/lean -R x -o y\n";
const noDev = {};
const SWAP = "total = 6144.00M  used = 5201.62M  free = 942.38M  (encrypted)";
const FREE = "The system has 17179869184 (1048576 pages with a page size of 16384).\nSystem-wide memory free percentage: 38%\n";

describe("parsers", () => {
  it("parseSize reads B/K/M/G/T, ignores a +/- suffix, refuses the rest", () => {
    expect(parseSize("1245M")).toBe(1245);
    expect(parseSize("2G")).toBe(2048);
    expect(parseSize("512K")).toBe(0.5);
    expect(parseSize("0B")).toBe(0);
    expect(parseSize("947M+")).toBe(947);
    expect(parseSize("12")).toBeNull();
    expect(parseSize("M")).toBeNull();
  });
  it("parseTop keeps the process rows and the compressor size, not the header lines", () => {
    const t = parseTop(TOP);
    expect(t.compressorMB).toBe(5255);
    expect(t.rows.map((r) => r.pid)).toEqual([92347, 3093, 9722, 101, 7]);
    expect(t.rows[1]).toEqual({ pid: 3093, memMB: 947, cmprsMB: 907 });
    expect(parseTop(null)).toEqual({ rows: [], compressorMB: null });
  });
  it("parseProcs keeps the parent and paths with spaces; parseArgs keeps the command line", () => {
    const ps = parseProcs(PS);
    expect(ps.find((q) => q.pid === 3093)).toMatchObject({ ppid: 92347, comm: expect.stringMatching(/Chromium Helper \(Renderer\)$/) });
    expect(ps.find((q) => q.pid === 101)).toMatchObject({ ppid: 1, comm: "pnpm run build" });
    expect(parseArgs(ARGS).get(9722)).toBe("/Users/x/lean/.lake/build/bin/lean -R x -o y");
    expect(parseProcs(null)).toEqual([]);
  });
  it("udidOf reads the device id from a launchd_sim command line only", () => {
    const u = "aaaaaaaa-0000-4000-8000-000000000001";
    expect(udidOf({ pid: 1, ppid: 0, comm: "/R/sbin/launchd_sim", args: `/R/sbin/launchd_sim /D/Devices/${u}/data/var/run/x.plist` })).toBe(u);
    expect(udidOf({ pid: 1, ppid: 0, comm: "/usr/bin/top", args: `top ${u}` })).toBeNull();
    expect(udidOf({ pid: 1, ppid: 0, comm: "/R/sbin/launchd_sim", args: "" })).toBeNull();
  });
  it("parseSwap and parseFreePct", () => {
    expect(parseSwap(SWAP)).toEqual({ usedMB: 5201, totalMB: 6144 });
    expect(parseSwap("garbage")).toBeNull();
    expect(parseFreePct(FREE)).toBe(38);
    expect(parseFreePct("no")).toBeNull();
  });
});

const readings = (over: Partial<Parameters<typeof buildSample>[1]> = {}) => ({ top: TOP, ps: PS, args: ARGS, swap: SWAP, free: FREE, deviceNames: noDev, ...over });
const kindMap = (ps: ProcRow[], devs: Device[] = []) => new Map(kindsOf(devs, ps).map((k, i) => [ps[i]!.pid, k] as const));

describe("the sample", () => {
  it("reduceKinds sums count, MEM and CMPRS per kind; an unknown pid is other; the footprint is MEM plus CMPRS", () => {
    const withArgs = joinProcs(parseProcs(PS), ARGS, noDev).procs;
    const k = reduceKinds(parseTop(TOP).rows, kindMap(withArgs));
    expect(k.node).toEqual({ n: 1, memMB: 1245, cmprsMB: 199 });
    expect(k.chromium).toEqual({ n: 1, memMB: 947, cmprsMB: 907 });
    expect(k.leanBuild).toEqual({ n: 1, memMB: 2048, cmprsMB: 871 });
    expect(k.pnpm.n).toBe(1);
    expect(k.other).toEqual({ n: 1, memMB: 12, cmprsMB: 1 });
    expect(Object.keys(k)).toEqual([...PROC_KINDS]);
    expect(footMB(k.chromium)).toBe(947);
    expect(footMB(k.leanBuild)).toBe(2048);
  });
  it("a process whose CMPRS exceeds its MEM keeps both columns; the footprint is MEM (phys_footprint already holds the compressed part)", () => {
    const top = "PhysMem: 1G used (1M wired, 100M compressor), 1M unused.\nPID MEM CMPRS\n9 13M 73M\n";
    const k = reduceKinds(parseTop(top).rows, new Map([[9, "node"]]));
    expect(k.node).toEqual({ n: 1, memMB: 13, cmprsMB: 73 });
    expect(footMB(k.node)).toBe(13);
  });
  it("buildSample: a full set of readings gets a verdict (a lean build and chromium run, free 38 percent: busy)", () => {
    const s = buildSample(1000, readings(), 40.829, 16384, 1500);
    expect(s).toMatchObject({ ts: 1000, verdict: "busy", loadCenti: 4082, ramMB: 16384, swapUsedMB: 5201, swapTotalMB: 6144, compressorMB: 5255, freePct: 38, costMs: 1500, partial: [] });
  });
  it("buildSample: the language server and a system service alone leave the machine quiet; a build of ours makes it busy", () => {
    const top = "PhysMem: 1G used (1M wired, 100M compressor), 1M unused.\nPID MEM CMPRS\n20 900M 10M\n21 500M 0B\n22 90M 0B\n";
    const ps = ["    1     0 /sbin/launchd", "   20     1 /e/bin/lake", "   21    20 /e/bin/lean", "   22     1 /S/com.apple.WebKit.WebContent"].join("\n");
    const swap = SWAP.replace("5201.62", "100.00");
    const serve = buildSample(0, readings({ top, ps, args: "   20 /e/bin/lake serve\n   21 /e/bin/lean --server\n", swap }), 0.5, 16384, 1);
    expect(serve.verdict).toBe("quiet");
    expect(serve.kinds.leanServe).toMatchObject({ n: 2, memMB: 1400 });
    expect(serve.kinds.system.n).toBe(1);
    const build = buildSample(0, readings({ top, ps, args: "   20 /e/bin/lake build\n   21 /e/bin/lean -R x\n", swap }), 0.5, 16384, 1);
    expect(build.verdict).toBe("busy");
    expect(build.kinds.leanBuild.n).toBe(2);
  });
  it("buildSample: the whole launchd_sim subtree of a booted fw- device is simulator, a device not named fw- is not", () => {
    const u = "aaaaaaaa-0000-4000-8000-000000000001";
    const top = "PhysMem: 1G used (1M wired, 100M compressor), 1M unused.\nPID MEM CMPRS\n30 20M 0B\n31 50M 0B\n32 80M 0B\n";
    const ps = ["    1     0 /sbin/launchd", "   30     1 /R/sbin/launchd_sim", "   31    30 /R/usr/libexec/backboardd", "   32    31 /R/usr/libexec/some-sim-daemon"].join("\n");
    const args = `   30 /R/sbin/launchd_sim /D/Devices/${u}/data/var/run/launchd_bootstrap.plist\n`;
    const swap = SWAP.replace("5201.62", "100.00");
    const ours = buildSample(0, readings({ top, ps, args, swap, deviceNames: { [u]: "fw-sim 15 Pro Max" } }), 0.5, 16384, 1);
    expect(ours.kinds.simulator).toMatchObject({ n: 3, memMB: 150 });
    expect(ours.verdict).toBe("busy");
    const theirs = buildSample(0, readings({ top, ps, args, swap, deviceNames: { [u]: "iPhone 17" } }), 0.5, 16384, 1);
    expect(theirs.kinds.simulator.n).toBe(0);
    expect(theirs.verdict).toBe("quiet");
    const unknown = buildSample(0, readings({ top, ps, args, swap, deviceNames: { [u]: null } }), 0.5, 16384, 1);
    expect(unknown.partial).toEqual(["device"]);
    expect(unknown.verdict).toBeNull();
  });
  it("buildSample: swap at 90 percent or free memory at 15 percent is pressured, even with nothing heavy running", () => {
    const top = "PhysMem: 1G used (1M wired, 100M compressor), 1M unused.\nPID MEM CMPRS\n5 10M 1M\n";
    const r = (over: Partial<Parameters<typeof buildSample>[1]>) => readings({ top, ps: "5 1 /usr/bin/top", args: "", ...over });
    expect(buildSample(0, r({ swap: "total = 1000.00M used = 900.00M free = 100.00M" }), 0, 16384, 1).verdict).toBe("pressured");
    expect(buildSample(0, r({ swap: SWAP.replace("5201.62", "100.00"), free: "free percentage: 15%" }), 0, 16384, 1).verdict).toBe("pressured");
    expect(buildSample(0, r({ swap: SWAP.replace("5201.62", "100.00") }), 0.5, 16384, 1).verdict).toBe("quiet");
  });
  it("buildSample: a missing reading gives no verdict and names the reading", () => {
    const s = buildSample(0, readings({ swap: null }), 1, 16384, 1);
    expect(s.verdict).toBeNull();
    expect(s.swapUsedMB).toBeNull();
    expect(s.partial).toEqual(["swap"]);
    expect(buildSample(0, readings({ args: null }), 1, 16384, 1).partial).toEqual(["args"]);
    expect(buildSample(0, { top: null, ps: null, args: "", swap: null, free: null, deviceNames: noDev }, 1, 16384, 1).partial).toEqual(["top", "compressor", "ps", "swap", "free"]);
  });
  it("a sample line carries no command, path or argument", () => {
    const line = JSON.stringify(buildSample(0, readings(), 1, 16384, 1));
    expect(line).not.toMatch(/Users|Applications|\.nvm|pnpm run|Renderer|-R x|\//);
  });
});

const fake = (calls: string[] = []): Runner => async (cmd, args) => {
  calls.push(cmd);
  return cmd === "top" ? TOP : cmd === "ps" ? (args.includes("-p") ? ARGS : PS) : cmd === "sysctl" ? SWAP : cmd === "memory_pressure" ? FREE : null;
};

describe("sampleOnce", () => {
  it("appends one line to the sup-samples file and skips while the file is younger than 15 s", async () => {
    const d = tmp(); const p = pathsIn(d);
    const s = await sampleOnce(p, fake(), 100_000, 15_000, 1, 16384);
    expect(s?.verdict).toBe("busy");
    const f = join(p.consoleDir, SUP_FILE);
    const lines = readFileSync(f, "utf8").trim().split("\n");
    expect(lines).toHaveLength(1);
    expect((JSON.parse(lines[0]!) as SupSample).kinds.node.n).toBe(1);
    expect((JSON.parse(lines[0]!) as SupSample).kinds.leanBuild.n).toBe(1);
    // young file (just written): the next watcher process skips
    expect(await sampleOnce(p, fake(), Date.now(), 15_000, 1, 16384)).toBeNull();
    // old file: samples again
    const old = new Date(Date.now() - 60_000);
    utimesSync(f, old, old);
    expect(await sampleOnce(p, fake(), Date.now(), 15_000, 1, 16384)).not.toBeNull();
    expect(readFileSync(f, "utf8").trim().split("\n")).toHaveLength(2);
  });
  it("a failing runner still gives a line with no verdict, and the call never throws", async () => {
    const d = tmp(); const p = pathsIn(d);
    const s = await sampleOnce(p, async () => null, 1, 15_000, 1, 16384);
    expect(s?.verdict).toBeNull();
    expect(s?.partial).toContain("top");
  });
  it("an unwritable console dir gives null, not an exception", async () => {
    const d = tmp(); const blocker = join(d, "file");
    writeFileSync(blocker, "x");
    expect(await sampleOnce({ ...pathsIn(d), consoleDir: join(blocker, "sub") }, fake(), 1, 15_000, 1, 16384)).toBeNull();
  });
});

describe("ensureSampler", () => {
  it("is idempotent, takes no sample before the first 20 s tick, then one per tick", async () => {
    vi.useFakeTimers();
    const d = tmp(); const p = pathsIn(d); const calls: string[] = [];
    ensureSampler(p, fake(calls), 20_000);
    ensureSampler(p, fake(calls), 20_000);
    await vi.advanceTimersByTimeAsync(19_000);
    expect(calls).toEqual([]);
    expect(existsSync(join(p.consoleDir, SUP_FILE))).toBe(false);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(calls.filter((c) => c === "top")).toHaveLength(1);
    stopSamplers();
  });
  it("FW_SUP_SAMPLER=off starts nothing", async () => {
    vi.useFakeTimers();
    vi.stubEnv("FW_SUP_SAMPLER", "off");
    const calls: string[] = [];
    ensureSampler(pathsIn(tmp()), fake(calls), 20_000);
    await vi.advanceTimersByTimeAsync(60_000);
    expect(calls).toEqual([]);
    vi.unstubAllEnvs();
  });
});

describe("sim-lock.sh events", () => {
  it("acquire and release log the owner's pid and start, the wait and the hold, and no owner name or path", () => {
    const d = tmp();
    spawnSync("git", ["init", "-q"], { cwd: d });
    mkdirSync(join(d, "scripts"));
    const script = join(root, "scripts/sim-lock.sh");
    const { CI: _ci, FW_LOCK_EVENTS: _e, FW_LOCK_EVENTS_FILE: _f, ...env } = process.env;
    const sh = (...a: string[]) => spawnSync("sh", [script, ...a], { cwd: d, env, encoding: "utf8" });
    expect(sh("acquire", "somebody").status).toBe(0);
    expect(sh("acquire", "other").status).toBe(1);
    expect(sh("release").status).toBe(0);
    const ev = readFileSync(join(d, ".fw-console/locks.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Record<string, unknown>);
    expect(ev.map((x) => [x.lock, x.ev, x.kind])).toEqual([["sim", "acquire", "sim"], ["sim", "release", "sim"]]);
    expect(ev[0]!.waitMs).toBe(0);
    expect(ev[1]!.holdMs).toBeGreaterThanOrEqual(0);
    expect(ev[0]!.pid).toBe(ev[1]!.pid);
    expect(ev[0]!.start).toBe(ev[1]!.start);
    expect(readFileSync(join(d, ".fw-console/locks.jsonl"), "utf8")).not.toMatch(/somebody|other|\//);
  });
  it("FW_LOCK_EVENTS=off and CI write nothing; the lock itself still works", () => {
    const d = tmp();
    spawnSync("git", ["init", "-q"], { cwd: d });
    const script = join(root, "scripts/sim-lock.sh");
    const { CI: _ci, FW_LOCK_EVENTS: _e, FW_LOCK_EVENTS_FILE: _f, ...env } = process.env;
    for (const extra of [{ FW_LOCK_EVENTS: "off" }, { CI: "1" }]) {
      expect(spawnSync("sh", [script, "acquire", "a"], { cwd: d, env: { ...env, ...extra } }).status).toBe(0);
      expect(spawnSync("sh", [script, "release"], { cwd: d, env: { ...env, ...extra } }).status).toBe(0);
    }
    expect(existsSync(join(d, ".fw-console/locks.jsonl"))).toBe(false);
  });
});
