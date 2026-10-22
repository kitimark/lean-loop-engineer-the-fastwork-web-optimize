import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import {
  DEFAULT_PARAMS, DEFAULT_WPARAMS, type CacheKey, type Ctl, type Entry, type Kind, type Mem, type Params, type Row, type Sample, type VmMark,
  type WParams, type Window, beginPass, capLease, current, openAt, passStart, predict, stopPass, want, wverdict,
  admitBuild, agentsSeen, availMB, cacheHit, expired, grant, heldOf, keyOf, leanThreads, leaseOr, prune, release, renew, signal, simAction, simBoot,
  simDue, simIdleNext, simQueued, step, stopAct, swapActive, thrash, memLow, verdict, vmNext, withLegacy,
} from "../src/slot-core.ts";
import { WHY_TAGS, noteQueue, queueExtra } from "../src/slot-queue.ts";
import {
  type Deps, type GitFacts, EXIT_REFUSED, SlotUsage, lastHealth, legacyLive, markNext, memOf, parseCompressorMB, parseSysctl, parseVmStat, recoverStale,
  acquire, releaseToken, slotCli, spanRows, startOf, withState, SLOT_MAIN_REL, mainCheckout, resolveSlotMain,
} from "../src/slot.ts";

const golden = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "packages", "contracts", "golden", "sup", "adapt.jsonl");
type Case = { name: string; request: Record<string, unknown> & { op: string }; response: Record<string, unknown> };
const cases = readFileSync(golden, "utf8").trim().split("\n").map((l) => JSON.parse(l) as Case);

function answer(r: Record<string, unknown> & { op: string }): Record<string, unknown> {
  const p: Params = { ...DEFAULT_PARAMS, ...(r.params as Partial<Params> | undefined) };
  const es = r.entries as Entry[];
  switch (r.op) {
    case "adapt.params": return { ...DEFAULT_PARAMS };
    case "adapt.whyTags": return { names: [...WHY_TAGS] };
    case "adapt.step": {
      const c = r.ctl as Ctl, s = r.sample as Sample;
      return { ctl: step(p, c, s), signal: signal(p, c.prev, s) };
    }
    case "adapt.verdict":
      return verdict(p, r.n as number, r.sample as Sample, r.holders as Entry[], r.queue as Entry[], r.me as Entry, r.waited as number);
    case "adapt.threads": return { threads: leanThreads(p, r.cores as number, r.roomMB as number) };
    case "adapt.prune": return { entries: prune(r.now as number, es) };
    case "adapt.expired": return { entries: expired(r.now as number, es) };
    case "adapt.renew": return { entries: renew(p, r.now as number, r.owner as string, r.token as string, r.lease as number | null, es) };
    case "adapt.grant": return { entry: grant(p, r.me as Entry, r.now as number, r.lease as number, r.foot as number) };
    case "adapt.leaseOr": return { leaseS: leaseOr(r.stored as number | null, r.since as number, r.till as number) };
    case "adapt.release": return { entries: release(r.owner as string, r.token as string, es) };
    case "adapt.simBoot": return { boot: simBoot(r.now as number, r.owner as string, r.token as string, r.holders as Entry[]) };
    case "adapt.simAction":
      return { action: simAction(p, r.now as number, r.holders as Entry[], r.booted as boolean, r.legacyHeld as boolean, r.idleSince as number | null) };
    case "adapt.simIdleNext": return { idleSince: simIdleNext(r.now as number, r.held as boolean, r.booted as boolean, r.prev as number | null) };
    case "adapt.simDue": return { due: simDue(p, r.now as number, r.last as number) };
    case "adapt.admitBuild": return admitBuild(p, r.simWaits as boolean, r.availMB as number, r.agents as number | null);
    case "adapt.memLow": {
      const m = r.mem as Mem;
      return { availMB: availMB(m), swapActive: swapActive(p, m), thrash: thrash(p, m), memLow: memLow(p, m) };
    }
    case "adapt.vmNext":
      return { mark: vmNext(p, r.prev as VmMark | null, r.now as number, r.count as number, r.swapCount as number, r.pageB as number) };
    case "adapt.agentsSeen": return { agents: agentsSeen(p, r.now as number, r.reading as { time: number; live: number } | null) };
    case "adapt.simQueued": return { queued: simQueued(r.now as number, r.queue as Entry[]) };
    case "adapt.withLegacy": return { holders: withLegacy(r.now as number, r.legacy as boolean, r.holders as Entry[]) };
    case "adapt.heldOf": return { held: heldOf(r.now as number, r.holders as Entry[], r.kind as Entry["kind"]) };
    case "adapt.stop": return { action: stopAct(p, r.alive as boolean, r.sameStart as boolean, r.termAt as number | null, r.nowMs as number) };
    case "adapt.cacheKey": return { key: keyOf(r.kind as CacheKey["kind"], r.argv as string[], r.tree as string, r.mainSha as string, r.clean as boolean) };
    case "adapt.cacheHit": return { hit: cacheHit(r.recorded as CacheKey, r.exit as number, r.key as CacheKey | null) };
    case "window.params": return { ...DEFAULT_WPARAMS };
    case "window.open": return { window: openAt(r.wparams as WParams, r.owner as string, r.token as string, r.now as number, r.gapS as number) };
    case "window.current": return { window: current(r.now as number, r.holders as Entry[], r.window as Window | null) };
    case "window.verdict":
      return wverdict(r.wparams as WParams, r.window as Window | null, r.pred as number | null, p, r.n as number, r.sample as Sample, r.holders as Entry[],
        r.queue as Entry[], r.me as Entry, r.waited as number);
    case "window.passStart":
      return passStart(r.wparams as WParams, r.window as Window | null, r.now as number, r.holders as Entry[], r.owner as string, r.token as string, r.forS as number);
    case "window.predict": return { predS: predict(r.wparams as WParams, r.kind as Kind, r.rows as Row[]) };
    case "window.edit": {
      const w = r.window as Window, now = r.now as number, x = r.arg as number;
      return { window: r.act === "begin" ? beginPass(w, x) : r.act === "want" ? want(w, now) : stopPass(w, now, x) };
    }
    case "window.capLease": return { leaseS: capLease(r.window as Window, r.now as number, r.lease as number) };
    default: throw new Error(`unknown op ${r.op}`);
  }
}

describe("slot-core replays the Fw.Sup.Adapt golden vectors", () => {
  it(`${cases.length} cases, every op covered`, () => {
    expect(new Set(cases.map((c) => c.request.op)).size).toBe(33);
    for (const c of cases) expect(answer(c.request), c.name).toEqual(c.response);
  });
});

const fixture = (n: string): string => readFileSync(join(dirname(fileURLToPath(import.meta.url)), "fixtures", n), "utf8");
const busySysctl = "vm.vm_page_filecache_min: 233999\nkern.memorystatus_vm_pressure_level: 1\n"
  + "vm.swapusage: total = 4096.00M  used = 3046.50M  free = 1049.50M  (encrypted)\n";

describe("probe parsers", () => {
  it("reads vm_stat, sysctl and the compressor footprint", () => {
    expect(parseVmStat(fixture("vm_stat-busy.txt"))).toEqual({
      pageB: 16384, free: 13944, spec: 7683, purg: 5581, file: 319116, occupied: 192199, compressions: 1701467470, swapouts: 13043114,
    });
    expect(parseSysctl(busySysctl)).toEqual({ fileMinPages: 233999, press: 1, swapUsedMB: 3046, swapTotalMB: 4096 });
    expect(parseSysctl("")).toEqual({ fileMinPages: null, press: null, swapUsedMB: null, swapTotalMB: null });
    expect(parseCompressorMB(fixture("vm_stat-busy.txt"))).toBe(3003);
    expect(parseVmStat("")).toBeNull();
    expect(parseCompressorMB("")).toBeNull();
  });

  it("the lead's busy window (MEASURED 03:18:44): 1754 MB available, compressing 5309 MB a minute", () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-vm-"));
    try {
      const a = parseVmStat(fixture("vm_stat-busy.txt"))!, b = parseVmStat(fixture("vm_stat-busy-next.txt"))!;
      expect(markNext(dir, DEFAULT_PARAMS, 1792613925, a))
        .toEqual({ time: 1792613925, count: 1701467470, rate: 0, swapCount: 13043114, swapRate: 0 });
      const mark = markNext(dir, DEFAULT_PARAMS, 1792613936, b);
      expect(mark.rate).toBe(5309);
      expect(mark.swapRate).toBe(0);
      const m = memOf(a, parseSysctl(busySysctl), mark);
      expect(m).toEqual({
        freeMB: 217, specMB: 120, purgMB: 87, fileMB: 4986, fileMinMB: 3656, swapUsedMB: 3046, swapTotalMB: 4096, press: 1, comprMBPerMin: 5309,
        swapOutMBPerMin: 0,
      });
      expect(availMB(m)).toBe(1754);
      expect(memLow(DEFAULT_PARAMS, m)).toBe(true);
      expect(memLow(DEFAULT_PARAMS, { ...m, comprMBPerMin: 0 })).toBe(false);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("an idle reading on this Mac and a missing pressure level", () => {
    const m = memOf(parseVmStat(fixture("vm_stat-idle.txt"))!, parseSysctl("vm.vm_page_filecache_min: 276653\n"), { rate: 0, swapRate: 0 });
    expect(availMB(m)).toBe(2536);
    expect(m.press).toBe(1);
    expect(memLow(DEFAULT_PARAMS, m)).toBe(false);
  });

  it("an unread file-cache minimum counts no file cache", () => {
    expect(availMB(memOf(parseVmStat(fixture("vm_stat-busy.txt"))!, parseSysctl(""), { rate: 0, swapRate: 0 }))).toBe(424);
  });

  it("a mark written before swap-out was read counts as a first reading", () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-vm-"));
    try {
      writeFileSync(join(dir, "vm-mark.json"), JSON.stringify({ time: 1792613900, count: 1701000000, rate: 4000 }));
      expect(markNext(dir, DEFAULT_PARAMS, 1792613925, parseVmStat(fixture("vm_stat-busy.txt"))!))
        .toEqual({ time: 1792613925, count: 1701467470, rate: 0, swapCount: 13043114, swapRate: 0 });
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

const mem = (freeMB: number): Mem =>
  ({ freeMB, specMB: 0, purgMB: 0, fileMB: 0, fileMinMB: 0, swapUsedMB: 0, swapTotalMB: 0, press: 1, comprMBPerMin: 0, swapOutMBPerMin: 0 });
const quiet = (): Sample => ({ time: Math.floor(Date.now() / 1000), loadCenti: 100, mem: mem(12000), ramMB: 16384, compressorMB: 0, cores: 8 });
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
    owner: "wt-a", env: { PATH: process.env.PATH }, params: DEFAULT_PARAMS, wparams: DEFAULT_WPARAMS, history: () => [], pollMs: 1, probe: quiet,
    git: () => git,
    simctl: { booted: () => [{ udid: "U1", name: "fw-iphone" }, { udid: "U2", name: "iPhone 17e" }], shutdown: (u) => { shut.push(u); } },
    health: () => ({ time: Math.floor(Date.now() / 1000), live: 3 }),
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

  it("renew without --lease keeps the granted length; --lease sets it", async () => {
    const { d, out, state } = deps();
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "1800"], d)).toBe(0);
    const token = out.join("").trim();
    const t0 = Math.floor(Date.now() / 1000);
    expect(await slotCli(["renew", "--token", token], d)).toBe(0);
    const [h] = state().holders;
    expect(h?.leaseS).toBe(1800);
    expect(h?.till).toBeGreaterThanOrEqual(t0 + 1800);
    expect(await slotCli(["renew", "--token", token, "--lease", "120"], d)).toBe(0);
    expect(state().holders.map((x) => x.leaseS)).toEqual([120]);
    expect(await slotCli(["renew", "--token", token], d)).toBe(0);
    expect(state().holders.map((x) => x.leaseS)).toEqual([120]);
  });

  it("a state entry written before leaseS was stored renews for its whole span", async () => {
    const { d, state } = deps();
    const now = Math.floor(Date.now() / 1000);
    mkdirSync(d.dir, { recursive: true });
    const old = { owner: "wt-a", token: "tok", kind: "sim", since: now - 100, till: now + 1700, foot: 2800 };
    writeFileSync(join(d.dir, "state.json"), JSON.stringify({ ctl: { n: 2, lastChange: 0, prev: null }, holders: [old], queue: [], simIdleSince: 0 }));
    expect(await slotCli(["renew", "--token", "tok"], d)).toBe(0);
    expect(state().holders.map((x) => x.leaseS)).toEqual([1800]);
  });

  it("each holder pruned for expiry logs one expire event in locks.jsonl", async () => {
    const { d, state } = deps();
    const now = Math.floor(Date.now() / 1000);
    mkdirSync(d.dir, { recursive: true });
    const gone = (token: string, kind: Entry["kind"]): Entry => ({ owner: "wt-x", token, kind, since: now - 70, till: now - 10, foot: 0, leaseS: 60 });
    const keep: Entry = { owner: "wt-y", token: "k", kind: "test", since: now, till: now + 600, foot: 0, leaseS: 600 };
    writeFileSync(join(d.dir, "state.json"), JSON.stringify({ ctl: { n: 4, lastChange: 0, prev: null }, holders: [gone("e1", "sim"), keep, gone("e2", "test")], queue: [], simIdleSince: 0 }));
    expect(await slotCli(["status"], d)).toBe(0);
    expect(await slotCli(["status"], d)).toBe(0);
    expect(state().holders.map((h) => h.token)).toEqual(["k"]);
    const evs = readFileSync(d.eventsFile ?? "", "utf8").trim().split("\n").map((l) => JSON.parse(l) as Record<string, unknown>);
    const exp = evs.filter((e) => e.ev === "expire");
    expect(exp.map((e) => [e.lock, e.kind, e.owner, e.token, e.leaseS, e.holdMs])).toEqual([["slot", "sim", "wt-x", "e1", 60, 60000], ["slot", "test", "wt-x", "e2", 60, 60000]]);
    for (const e of exp) {
      expect(e.lateMs as number).toBeGreaterThanOrEqual(10000);
      expect([typeof e.ts, typeof e.pid, typeof e.start]).toEqual(["number", "number", "number"]);
    }
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

describe("state lock recovery", () => {
  const deadPid = (): number => spawnSync("true").pid ?? 0;
  const lockWith = (dir: string, owner: object): string => {
    const lock = join(dir, "state.lock");
    mkdirSync(lock, { recursive: true });
    writeFileSync(join(lock, "owner"), JSON.stringify(owner));
    return lock;
  };

  it("a lock left by a dead owner is moved aside and removed, then the call proceeds", async () => {
    const { d, state } = deps();
    lockWith(d.dir, { pid: deadPid(), start: null });
    expect(await slotCli(["acquire", "--kind", "test", "--lease", "60"], d)).toBe(0);
    expect(state().holders).toHaveLength(1);
    expect(readdirSync(d.dir).filter((f) => f.startsWith("state.lock"))).toEqual([]);
  });

  it("a lock that another waiter already recovered (ENOENT on rename) is left alone", () => {
    const { d } = deps();
    mkdirSync(d.dir, { recursive: true });
    expect(() => recoverStale(join(d.dir, "state.lock"), { pid: deadPid(), start: null })).not.toThrow();
    expect(readdirSync(d.dir)).toEqual([]);
  });

  it("a fresh lock taken after the dead owner was read is moved back, not deleted", () => {
    const { d } = deps();
    const lock = lockWith(d.dir, { pid: process.pid, start: startOf(process.pid) });
    recoverStale(lock, { pid: deadPid(), start: null });
    expect(existsSync(join(lock, "owner"))).toBe(true);
    expect(readdirSync(d.dir)).toEqual(["state.lock"]);
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

describe("acquire behind a live holder", () => {
  it("waits for the sim holder, records the ms per reason on the grant and on the span extras", async () => {
    const { d } = deps();
    const first = await acquire(d, "sim", 900, 0);
    expect(first.verdict.verdict).toBe("admit");
    expect(first.queue).toBeUndefined();
    setTimeout(() => { releaseToken(d, first.token); }, 1500);
    const second = await acquire(d, "sim", 900, null);
    expect(second.verdict.verdict).toBe("admit");
    const q = second.queue!;
    expect(q.kind).toBe("sim");
    expect(q.waitMs).toBeGreaterThanOrEqual(1000);
    expect(q.waits.length).toBeGreaterThan(0);
    for (const w of q.waits) expect(WHY_TAGS).toContain(w.why);
    expect(q.waits.some((w) => w.why === "simBusy")).toBe(true);
    const sum = q.waits.reduce((a, w) => a + w.ms, 0);
    expect(sum).toBeGreaterThan(0);
    expect(sum).toBeLessThanOrEqual(q.waitMs);
    expect(q.waitMs - sum).toBeLessThanOrEqual(d.pollMs + 2000);
    expect(queueExtra()).toEqual({ queue: q });
    noteQueue(null);
  });
  it("a refused acquire carries no queue", async () => {
    const { d } = deps();
    const first = await acquire(d, "sim", 900, 0);
    expect(first.verdict.verdict).toBe("admit");
    const second = await acquire(d, "sim", 900, 0);
    expect(second.verdict.verdict).not.toBe("admit");
    expect(second.queue).toBeUndefined();
  });
});

describe("fw slot sim", () => {
  const idleFor = (d: Deps, s: number): void => { withState(d, (st) => { st.simIdle = Math.floor(Date.now() / 1000) - s; }); };

  it("starts the idle clock at the first sighting, keeps under a live sim slot or the old lock, shuts every device once idle", async () => {
    const held = deps();
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "900"], held.d)).toBe(0);
    idleFor(held.d, 700);
    held.out.length = 0;
    expect(await slotCli(["sim", "--apply"], held.d)).toBe(0);
    expect(held.out.join("")).toContain("action keep");
    expect(held.shut).toEqual([]);
    const fresh = deps();
    expect(await slotCli(["sim", "--apply"], fresh.d)).toBe(0);
    expect(fresh.out.join("")).toContain("2 booted device(s), action keep");
    expect(fresh.shut).toEqual([]);
    idleFor(fresh.d, 700);
    expect(await slotCli(["sim"], fresh.d)).toBe(0);
    expect(fresh.out.join("")).toContain("action shutdown");
    expect(fresh.shut).toEqual([]);
    expect(await slotCli(["sim", "--apply"], fresh.d)).toBe(0);
    expect(fresh.shut).toEqual(["U1", "U2"]);
    const legacy = deps();
    mkdirSync(legacy.d.legacySimLock, { recursive: true });
    writeFileSync(join(legacy.d.legacySimLock, "pid"), String(process.pid));
    idleFor(legacy.d, 700);
    expect(await slotCli(["sim", "--apply"], legacy.d)).toBe(0);
    expect(legacy.shut).toEqual([]);
  });

  it("release and acquire run the Simulator check themselves: the release starts the idle clock, a later poll shuts down", async () => {
    const { d, out, shut } = deps();
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "900"], d)).toBe(0);
    const token = out.join("").trim();
    withState(d, (st) => { st.simCheckedAt = 0; });
    expect(await slotCli(["release", "--token", token], d)).toBe(0);
    expect(shut).toEqual([]);
    withState(d, (st) => { st.simIdle = Math.floor(Date.now() / 1000) - 700; st.simCheckedAt = 0; });
    expect(await slotCli(["acquire", "--kind", "test", "--wait", "0"], d)).toBe(0);
    expect(shut).toEqual(["U1", "U2"]);
  });
});

describe("the old sim-lock and the slot", () => {
  it("a live old lock makes a sim ticket wait as simBusy; a dead pid frees it", async () => {
    const { d, err } = deps();
    mkdirSync(d.legacySimLock, { recursive: true });
    expect(legacyLive(d.legacySimLock)).toBe(true);
    writeFileSync(join(d.legacySimLock, "pid"), String(process.pid));
    expect(await slotCli(["acquire", "--kind", "sim", "--wait", "0"], d)).toBe(EXIT_REFUSED);
    expect(err.join("")).toContain("the Simulator slot is held");
    writeFileSync(join(d.legacySimLock, "pid"), String(spawnSync("true").pid ?? 0));
    expect(legacyLive(d.legacySimLock)).toBe(false);
    expect(await slotCli(["acquire", "--kind", "sim", "--wait", "0"], d)).toBe(0);
  });

  it("fw slot held reports a live holder of a kind by exit code", async () => {
    const { d } = deps();
    expect(await slotCli(["held", "--kind", "sim"], d)).toBe(3);
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "900"], d)).toBe(0);
    expect(await slotCli(["held", "--kind", "sim"], d)).toBe(0);
    expect(await slotCli(["held", "--kind", "test"], d)).toBe(3);
  });

  it("sim-lock.sh refuses while a slot sim holder is live and takes the lock once it is gone", async () => {
    const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
    const repo = mkdtempSync(join(tmpdir(), "fw-simlock-"));
    tmps.push(repo);
    spawnSync("git", ["init", "-q"], { cwd: repo });
    const { CI: _ci, FW_SLOT_DIR: _s, FW_CONSOLE_DIR: _c, ...env } = process.env;
    const sh = (...a: string[]) => spawnSync("sh", [join(root, "scripts", "sim-lock.sh"), ...a], { cwd: repo, env: { ...env, FW_LOCK_EVENTS: "off" }, encoding: "utf8" });
    const { d, out } = deps({ dir: join(repo, ".fw-console", "slot"), legacySimLock: join(repo, ".local", "locks", "sim") });
    expect(await slotCli(["acquire", "--kind", "sim", "--lease", "900"], d)).toBe(0);
    const r = sh("acquire", "a");
    expect(r.status).toBe(1);
    expect(r.stderr).toContain("a Simulator slot of fw slot");
    expect(sh("status").stdout).toBe("free\n");
    expect(await slotCli(["release", "--token", out.join("").trim()], d)).toBe(0);
    expect(sh("acquire", "a").status).toBe(0);
    expect(sh("release").status).toBe(0);
  });
});

describe("fw slot admit --kind build", () => {
  it("prints a VERDICT line: admit (0), wait on a queued sim ticket, too many agents or low memory (75)", async () => {
    const ok = deps();
    expect(await slotCli(["admit", "--kind", "build"], ok.d)).toBe(0);
    expect(ok.out.join("")).toBe("VERDICT admit build\n");
    const many = deps();
    expect(await slotCli(["admit", "--kind", "build", "--agents", "8"], many.d)).toBe(EXIT_REFUSED);
    expect(many.out.join("")).toBe("VERDICT wait build\n");
    expect(many.err.join("")).toContain("8 live agents, limit 8");
    const stale = deps({ health: () => ({ time: 0, live: 1 }) });
    expect(await slotCli(["admit", "--kind", "build"], stale.d)).toBe(EXIT_REFUSED);
    expect(stale.err.join("")).toContain("no recent health reading");
    const low = deps({ probe: () => ({ ...quiet(), mem: mem(3000) }) });
    expect(await slotCli(["admit", "--kind", "build"], low.d)).toBe(EXIT_REFUSED);
    const sim = deps();
    withState(sim.d, (st) => { const t = Math.floor(Date.now() / 1000); st.queue.push({ owner: "o", token: "q", kind: "sim", since: t, till: t + 60, foot: 0, leaseS: 60 }); });
    expect(await slotCli(["admit", "--kind", "build"], sim.d)).toBe(EXIT_REFUSED);
    expect(sim.err.join("")).toContain("a Simulator ticket is queued");
    await expect(slotCli(["admit", "--kind", "test"], ok.d)).rejects.toThrow(SlotUsage);
  });

  it("reads the live-agent count from the tail of the health log", () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-health-"));
    tmps.push(dir);
    const f = join(dir, "health.jsonl");
    expect(lastHealth(f)).toBeNull();
    const line = (at: number, counts: object) => `${JSON.stringify({ at, input: {}, output: { counts } })}\n`;
    writeFileSync(f, line(1000, { active: 1 }) + line(2_000_500, { active: 4, done: 45, gone: 1, idle: 1, parked: 1, stalled: 0 }));
    expect(lastHealth(f)).toEqual({ time: 2000, live: 6 });
  });
});

describe("fw slot acquire --kind measure and its pass windows", () => {
  const checkRuns: Row[] = [5000, 6000, 7000].map((durMs) => ({ step: "slot run check lake", durMs, exit: 0, host: "local" }));
  const tokenOf = (out: string[]): string => out.join("").trim().split("\n").at(-1)!;
  type WState = { window: Window | null; holders: Entry[] };

  it("a live pass makes every other request wait; a gap admits a job that fits; the pass waits for it", async () => {
    const { d, out, err, state } = deps({ history: () => checkRuns });
    expect(await slotCli(["acquire", "--kind", "measure", "--lease", "600"], d)).toBe(0);
    const m = tokenOf(out);
    const w0 = (state() as unknown as WState).window!;
    expect(w0.token).toBe(m);
    expect(w0.deadline - w0.next).toBe(DEFAULT_WPARAMS.measureMaxS);
    expect(await slotCli(["acquire", "--kind", "check", "--wait", "0"], d)).toBe(EXIT_REFUSED);
    expect(err.join("")).toContain("left before the next measure pass");
    expect(await slotCli(["pass", "stop", "--token", m, "--next", "600"], d)).toBe(0);
    expect(await slotCli(["acquire", "--kind", "check", "--wait", "0"], d)).toBe(0);
    const c = tokenOf(out);
    expect(await slotCli(["pass", "start", "--token", m, "--for", "300", "--wait", "0"], d)).toBe(EXIT_REFUSED);
    expect(out.join("")).toContain("VERDICT wait pass");
    expect(err.join("")).toContain("1 other holder(s) still live");
    expect(await slotCli(["acquire", "--kind", "test", "--wait", "0"], d)).toBe(EXIT_REFUSED);
    expect(await slotCli(["release", "--token", c], d)).toBe(0);
    expect(await slotCli(["pass", "start", "--token", m, "--for", "300", "--wait", "0"], d)).toBe(0);
    expect(out.join("")).toMatch(/VERDICT start pass \d+/);
    expect(await slotCli(["acquire", "--kind", "sim", "--wait", "0"], d)).toBe(EXIT_REFUSED);
    expect(err.join("")).toContain("a measure pass is live");
    expect(await slotCli(["acquire", "--kind", "measure", "--wait", "0"], d)).toBe(EXIT_REFUSED);
    expect(await slotCli(["release", "--token", m], d)).toBe(0);
    expect((state() as unknown as WState).window).toBeNull();
    expect(await slotCli(["acquire", "--kind", "test", "--wait", "0"], d)).toBe(0);
  });

  it("a kind without recorded runs waits in a gap; status shows the window and each ticket's reason", async () => {
    const { d, out } = deps();
    expect(await slotCli(["acquire", "--kind", "measure", "--next", "900"], d)).toBe(0);
    const t = Math.floor(Date.now() / 1000);
    withState(d, (st) => { st.queue.push({ owner: "wt-b", token: "q1", kind: "test", since: t, till: t + 60, foot: 0, leaseS: 60 }); });
    out.length = 0;
    expect(await slotCli(["status"], d)).toBe(0);
    const text = out.join("");
    expect(text).toMatch(/measure window: wt-a \S+, gap, next pass in \d+s, deadline in \d+s/);
    expect(text).toContain("q1 queued");
    expect(text).toContain("too few recorded runs");
  });

  it("renew never extends a measure lease past the window deadline; pass calls of a foreign owner are refused", async () => {
    const { d, out, state } = deps();
    expect(await slotCli(["acquire", "--kind", "measure", "--lease", "600"], d)).toBe(0);
    const m = tokenOf(out);
    const now = Math.floor(Date.now() / 1000);
    withState(d, (st) => { st.window = { ...st.window!, deadline: now + 100 }; });
    expect(await slotCli(["renew", "--token", m, "--lease", "600"], d)).toBe(0);
    expect(state().holders[0]!.till).toBeLessThanOrEqual(now + 101);
    expect(await slotCli(["pass", "stop", "--token", m, "--owner", "wt-b"], d)).toBe(1);
    expect(await slotCli(["pass", "start", "--token", m, "--owner", "wt-b", "--wait", "0"], d)).toBe(1);
    withState(d, (st) => { st.window = { ...st.window!, deadline: now }; });
    expect(await slotCli(["renew", "--token", m], d)).toBe(1);
    await expect(slotCli(["pass", "begin", "--token", m], d)).rejects.toThrow(SlotUsage);
  });

  it("spanRows reads fw slot run spans from the tail of the timings log", () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-spans-"));
    tmps.push(dir);
    const f = join(dir, "timings.jsonl");
    expect(spanRows(f)).toEqual([]);
    expect(spanRows(null)).toEqual([]);
    const l = (o: object) => `${JSON.stringify(o)}\n`;
    writeFileSync(f, l({ tool: "fw", step: "slot run check lake", durMs: 61000.4, exit: 0, host: "local" }) + "not json \"slot run x\n"
      + l({ tool: "fw wait", step: "slot run check", durMs: 1, exit: 0, host: "local" }) + l({ tool: "fw", step: "slot run test", durMs: 9, exit: null, host: "ci" })
      + l({ tool: "fw", step: "land dry", durMs: 9, exit: 0, host: "local" }));
    expect(spanRows(f)).toEqual([
      { step: "slot run check lake", durMs: 61000, exit: 0, host: "local" }, { step: "slot run test", durMs: 9, exit: null, host: "ci" },
    ]);
  });
});

const resDirs: string[] = [];
afterEach(() => { for (const d of resDirs.splice(0)) rmSync(d, { recursive: true, force: true }); });
const runIn = (cwd: string, ...a: string[]) => spawnSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", ...a], { cwd, stdio: "ignore" });

describe("resolveSlotMain: callers run the main checkout's slot code", () => {
  it("prefers the main checkout's file", () => {
    expect(resolveSlotMain("/wt/slot-main.ts", "/main", () => true)).toBe(join("/main", SLOT_MAIN_REL));
  });
  it("falls back to the local file when main's is missing or there is no main", () => {
    expect(resolveSlotMain("/wt/slot-main.ts", "/main", () => false)).toBe("/wt/slot-main.ts");
    expect(resolveSlotMain("/wt/slot-main.ts", null, () => true)).toBe("/wt/slot-main.ts");
  });
  it("a worktree on an older branch resolves to the main checkout's file", () => {
    const root = realpathSync(mkdtempSync(join(tmpdir(), "slotres-")));
    resDirs.push(root);
    const main = join(root, "main");
    mkdirSync(join(main, "apps/runner/src"), { recursive: true });
    writeFileSync(join(main, SLOT_MAIN_REL), "// new\n");
    runIn(main, "init", "-q", "-b", "main");
    runIn(main, "add", ".");
    runIn(main, "commit", "-qm", "a");
    const wt = join(root, "wt");
    runIn(main, "worktree", "add", "-q", "-b", "old", wt);
    writeFileSync(join(wt, SLOT_MAIN_REL), "// old\n");
    expect(mainCheckout(wt)).toBe(main);
    expect(resolveSlotMain(join(wt, SLOT_MAIN_REL), mainCheckout(wt))).toBe(join(main, SLOT_MAIN_REL));
    expect(mainCheckout(root)).toBeNull();
  });
});
