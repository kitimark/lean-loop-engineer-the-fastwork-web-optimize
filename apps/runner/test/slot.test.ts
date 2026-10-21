import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import {
  DEFAULT_PARAMS, type CacheKey, type Ctl, type Entry, type Params, type Sample,
  cacheHit, keyOf, leanThreads, prune, release, renew, signal, simAction, simBoot, step, stopAct, verdict,
} from "../src/slot-core.ts";
import { type Deps, type GitFacts, EXIT_REFUSED, SlotUsage, parseCompressorMB, parseFreePct, parseSwapUsedMB, slotCli } from "../src/slot.ts";

// Every vector is generated from Lean (lean/Fw/Sup/AdaptGolden.lean); the TS stand-in must give the same response.
const golden = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "packages", "contracts", "golden", "sup", "adapt.jsonl");
type Case = { name: string; request: Record<string, unknown> & { op: string }; response: Record<string, unknown> };
const cases = readFileSync(golden, "utf8").trim().split("\n").map((l) => JSON.parse(l) as Case);

function answer(r: Record<string, unknown> & { op: string }): Record<string, unknown> {
  const p: Params = { ...DEFAULT_PARAMS, ...(r.params as Partial<Params> | undefined) };
  const es = r.entries as Entry[];
  switch (r.op) {
    case "adapt.params": return { ...DEFAULT_PARAMS };
    case "adapt.step": {
      const c = r.ctl as Ctl, s = r.sample as Sample;
      return { ctl: step(p, c, s), signal: signal(p, c.prev, s) };
    }
    case "adapt.verdict":
      return verdict(p, r.n as number, r.sample as Sample, r.holders as Entry[], r.queue as Entry[], r.me as Entry, r.waited as number);
    case "adapt.threads": return { threads: leanThreads(p, r.cores as number, r.roomMB as number) };
    case "adapt.prune": return { entries: prune(r.now as number, es) };
    case "adapt.renew": return { entries: renew(p, r.now as number, r.owner as string, r.token as string, r.lease as number, es) };
    case "adapt.release": return { entries: release(r.owner as string, r.token as string, es) };
    case "adapt.simBoot": return { boot: simBoot(r.now as number, r.owner as string, r.token as string, r.holders as Entry[]) };
    case "adapt.simAction":
      return { action: simAction(p, r.now as number, r.holders as Entry[], r.booted as boolean, r.legacyHeld as boolean, r.idleSince as number) };
    case "adapt.stop": return { action: stopAct(p, r.alive as boolean, r.sameStart as boolean, r.termAt as number | null, r.nowMs as number) };
    case "adapt.cacheKey": return { key: keyOf(r.kind as CacheKey["kind"], r.argv as string[], r.tree as string, r.mainSha as string, r.clean as boolean) };
    case "adapt.cacheHit": return { hit: cacheHit(r.recorded as CacheKey, r.exit as number, r.key as CacheKey | null) };
    default: throw new Error(`unknown op ${r.op}`);
  }
}

describe("slot-core replays the Fw.Sup.Adapt golden vectors", () => {
  it(`${cases.length} cases, every op covered`, () => {
    expect(new Set(cases.map((c) => c.request.op)).size).toBe(12);
    for (const c of cases) expect(answer(c.request), c.name).toEqual(c.response);
  });
});

describe("probe parsers", () => {
  it("reads memory_pressure, vm.swapusage and vm_stat", () => {
    expect(parseFreePct("System-wide memory free percentage: 46%")).toBe(46);
    expect(parseSwapUsedMB("total = 8192.00M  used = 5040.25M  free = 3151.75M  (encrypted)")).toBe(5040);
    expect(parseCompressorMB("Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages occupied by compressor:   358400.\n")).toBe(5600);
    expect(parseFreePct("")).toBeNull();
    expect(parseCompressorMB("")).toBeNull();
  });
});

const quiet = (): Sample => ({ time: Math.floor(Date.now() / 1000), loadCenti: 100, freeMB: 12000, ramMB: 16384, compressorMB: 0, swapUsedMB: 0, cores: 8 });
const tmps: string[] = [];
afterEach(() => { for (const t of tmps.splice(0)) rmSync(t, { recursive: true, force: true }); });

function deps(over: Partial<Deps> = {}, git: GitFacts = { tree: "t1", clean: true, mainSha: "m1" }) {
  const dir = mkdtempSync(join(tmpdir(), "fw-slot-"));
  tmps.push(dir);
  const out: string[] = [];
  const err: string[] = [];
  const shut: string[] = [];
  const d: Deps = {
    dir: join(dir, "slot"), cacheDir: join(dir, "cache"), eventsFile: join(dir, "locks.jsonl"), legacySimLock: join(dir, "sim"),
    owner: "wt-a", env: { PATH: process.env.PATH }, params: DEFAULT_PARAMS, pollMs: 1, probe: quiet, git: () => git,
    simctl: { booted: () => [{ udid: "U1", name: "fw-iphone" }], shutdown: (u) => { shut.push(u); } },
    out: (s) => { out.push(s); }, err: (s) => { err.push(s); }, ...over,
  };
  return { d, out, err, shut, state: () => JSON.parse(readFileSync(join(d.dir, "state.json"), "utf8")) as { holders: Entry[]; queue: Entry[] } };
}

describe("fw slot acquire, renew, release", () => {
  it("a holder survives across calls by owner and lease; another owner cannot renew it", async () => {
    const { d, out, state } = deps();
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "900"], d)).toBe(0);
    const token = out.join("").trim();
    expect(state().holders.map((h) => [h.owner, h.kind])).toEqual([["wt-a", "sim"]]);
    expect(await slotCli(["renew", "--token", token], d)).toBe(0);
    expect(await slotCli(["renew", "--token", token, "--owner", "wt-b"], d)).toBe(1);
    expect(await slotCli(["release", "--token", token, "--owner", "wt-b"], d)).toBe(0);
    expect(state().holders).toHaveLength(1);
    expect(await slotCli(["release", "--token", token], d)).toBe(0);
    expect(state().holders).toEqual([]);
  });

  it("a second sim slot waits while the first is live, and the ticket is withdrawn after --wait", async () => {
    const { d, err, state } = deps();
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "900"], d)).toBe(0);
    expect(await slotCli(["acquire", "--kind", "sim", "--wait", "0", "--owner", "wt-b"], d)).toBe(EXIT_REFUSED);
    expect(err.join("")).toContain("the Simulator slot is held");
    expect(state().queue).toEqual([]);
  });

  it("--json reports the verdict and whether this owner may boot the Simulator", async () => {
    const { d, out } = deps();
    expect(await slotCli(["acquire", "--kind", "sim", "--json"], d)).toBe(0);
    expect(JSON.parse(out.join(""))).toMatchObject({ owner: "wt-a", kind: "sim", boot: true, verdict: { verdict: "admit" } });
  });

  it("refuses bad usage", async () => {
    const { d } = deps();
    await expect(slotCli(["acquire", "--kind", "lake"], d)).rejects.toThrow(SlotUsage);
    await expect(slotCli(["run", "--kind", "test"], d)).rejects.toThrow(SlotUsage);
    await expect(slotCli(["renew"], d)).rejects.toThrow(SlotUsage);
    await expect(slotCli(["acquire", "--kind", "test", "--wait", "soon"], d)).rejects.toThrow(SlotUsage);
  });
});

describe("fw slot run", () => {
  const node = process.execPath;
  it("runs the command with the slot env, releases after, and passes the exit code", async () => {
    const { d, out, state } = deps();
    const code = await slotCli(["run", "--kind", "check", "--", node, "-e", "console.log(process.env.FW_SLOT_HELD, process.env.LEAN_NUM_THREADS); process.exit(3)"], d);
    expect(code).toBe(3);
    expect(out.join("")).toBe("1 8\n");
    expect(state().holders).toEqual([]);
  });

  it("a nested run inside a held slot runs at once", async () => {
    const { d, out } = deps({ env: { PATH: process.env.PATH, FW_SLOT_HELD: "1" }, probe: () => { throw new Error("no probe when held"); } });
    expect(await slotCli(["run", "--kind", "test", "--", node, "-e", "console.log('in')"], d)).toBe(0);
    expect(out.join("")).toBe("in\n");
  });

  it("--cache replays a passing run on the same clean tree and argv, never a failing or dirty one", async () => {
    const { d, out, err } = deps();
    const argv = ["run", "--kind", "land", "--cache", "--", node, "-e", "console.log('VERDICT dry x'); console.log(Math.random())"];
    expect(await slotCli(argv, d)).toBe(0);
    const first = out.join("");
    out.length = 0;
    expect(await slotCli(argv, d)).toBe(0);
    expect(out.join("")).toBe(first);
    expect(err.join("")).toContain("replayed the result");
    const moved = deps({ cacheDir: d.cacheDir }, { tree: "t1", clean: true, mainSha: "m2" });
    expect(await slotCli(argv, moved.d)).toBe(0);
    expect(moved.out.join("")).not.toBe(first);
    const dirty = deps({ cacheDir: d.cacheDir }, { tree: "t1", clean: false, mainSha: "m1" });
    expect(await slotCli(argv, dirty.d)).toBe(0);
    expect(dirty.err.join("")).not.toContain("replayed");
    const fail = deps();
    const fargv = ["run", "--kind", "test", "--cache", "--", node, "-e", "process.exit(1)"];
    expect(await slotCli(fargv, fail.d)).toBe(1);
    expect(readdirSync(fail.d.dir).includes("state.json")).toBe(true);
    expect(() => readdirSync(fail.d.cacheDir)).toThrow();
  });
});

describe("fw slot sim", () => {
  it("keeps the Simulator under a live sim slot or the old lock, shuts down fw-* devices once idle", async () => {
    const held = deps();
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "900"], held.d)).toBe(0);
    held.out.length = 0;
    expect(await slotCli(["sim", "--apply"], held.d)).toBe(0);
    expect(held.out.join("")).toContain("action keep");
    expect(held.shut).toEqual([]);
    const idle = deps();
    expect(await slotCli(["sim", "--apply"], idle.d)).toBe(0);
    expect(idle.shut).toEqual(["U1"]);
    const listOnly = deps();
    expect(await slotCli(["sim"], listOnly.d)).toBe(0);
    expect(listOnly.out.join("")).toContain("action shutdown");
    expect(listOnly.shut).toEqual([]);
  });
});
