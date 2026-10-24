import { type ChildProcess, spawn, spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { appendFileSync, closeSync, existsSync, fstatSync, mkdirSync, openSync, readFileSync, readSync, renameSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import { SLOT_SUBS, WAIT_TOOL, runLabel, waitStep } from "./slot-span.ts";
import { type Queue, type WaitMs, addWait, noteQueue, queueOf } from "./slot-queue.ts";
import { begin, timingsFile } from "./timing.ts";
import { basename, dirname, join } from "node:path";
import {
  DEFAULT_PARAMS, DEFAULT_WPARAMS, type BuildVerdict, type CacheKey, type Ctl, type Entry, type Kind, type Mem, type Params, type PassVerdict, type Row,
  type Sample, type Verdict, type VmMark, type WParams, type Window, KINDS, admitBuild, agentsSeen, avail, beginPass, cacheHit, cacheable, capLease,
  current, expired, grant, heldOf, init, keyOf, kindOf, leaseOr, nestedSkips, openAt, passLive, passStart, predict, prune, release, renew, signal, simAction, simBoot,
  simDue, simHeld, simIdleNext, simQueued, step, stopAct, stopPass, vmNext, want, withLegacy, wverdict,
} from "./slot-core.ts";

export class SlotUsage extends Error {}

export const SLOT_USAGE = [
  "usage: fw slot run --kind <k> [--cache] [--owner o] -- <command> [args...]   (waits for a slot, runs, releases; exit 75 when refused)",
  "       fw slot acquire --kind <k> [--lease s] [--wait s] [--next s] [--owner o] [--json]  (holds a slot across tool calls; prints the token)",
  "       fw slot renew --token t [--lease s] [--owner o] | fw slot release --token t [--owner o]",
  "       fw slot pass start --token t [--for s] [--wait s] [--owner o] | fw slot pass stop --token t [--next s] [--owner o]",
  "       fw slot status [--json] | fw slot sim [--apply] | fw slot held --kind <k>   (kinds: check test land sim other measure)",
  "       fw slot admit --kind build [--agents n]   (may the lead start one more builder; VERDICT line, exit 0 admit, 75 wait)",
].join("\n");

export const EXIT_REFUSED = 75;
export const EXIT_ERROR = 70;

export type State = {
  ctl: Ctl; holders: Entry[]; queue: Entry[]; simIdleSince: number; simAcquired?: number; simUdids?: string[]; simIdle?: number | null; simCheckedAt?: number; window?: Window | null;
};
export type Health = { time: number; live: number };
export type GitFacts = { tree: string; clean: boolean; mainSha: string };
export type SimDevice = { udid: string; name: string };

export type Deps = {
  dir: string;
  cacheDir: string;
  eventsFile: string | null;
  legacySimLock: string;
  owner: string;
  env: Record<string, string | undefined>;
  params: Params;
  wparams: WParams;
  history: () => Row[];
  pollMs: number;
  probe: () => Sample;
  git: () => GitFacts;
  simctl: { booted: () => SimDevice[]; shutdown: (udid: string) => void };
  health: () => Health | null;
  out: (s: string) => void;
  err: (s: string) => void;
};

const nowS = (): number => Math.floor(Date.now() / 1000);
const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));
const sleepSync = (ms: number): void => { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); };

export function startOf(pid: number): number | null {
  const r = spawnSync("ps", ["-o", "lstart=", "-p", String(pid)], { encoding: "utf8", env: { ...process.env, LC_ALL: "C", TZ: "UTC" } });
  const s = (r.stdout ?? "").trim();
  if (!s) return null;
  const t = Date.parse(`${s} UTC`);
  return Number.isNaN(t) ? null : Math.floor(t / 1000);
}

const alive = (pid: number): boolean => { try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; } };

export type VmStat = {
  pageB: number; free: number; spec: number; purg: number; file: number; occupied: number; compressions: number; swapouts: number;
};

export function parseVmStat(out: string): VmStat | null {
  const page = /page size of (\d+) bytes/.exec(out);
  const n = (label: string): number | null => {
    const m = new RegExp(`^${label}:\\s+(\\d+)\\.?$`, "m").exec(out);
    return m ? Number(m[1]) : null;
  };
  const v = {
    free: n("Pages free"), spec: n("Pages speculative"), purg: n("Pages purgeable"), file: n("File-backed pages"),
    occupied: n("Pages occupied by compressor"), compressions: n("Compressions"), swapouts: n("Swapouts"),
  };
  if (page === null || Object.values(v).some((x) => x === null)) return null;
  return { pageB: Number(page[1]), ...(v as Record<keyof typeof v, number>) };
}

export type Sysctl = { fileMinPages: number | null; press: number | null; swapUsedMB: number | null; swapTotalMB: number | null };

export function parseSysctl(out: string): Sysctl {
  const v = (name: string): number | null => {
    const m = new RegExp(`^${name.replaceAll(".", "\\.")}:\\s*(\\d+)\\s*$`, "m").exec(out);
    return m ? Number(m[1]) : null;
  };
  const used = /used = ([\d.]+)M/.exec(out);
  const total = /total = ([\d.]+)M/.exec(out);
  return {
    fileMinPages: v("vm.vm_page_filecache_min"), press: v("kern.memorystatus_vm_pressure_level"),
    swapUsedMB: used ? Math.floor(Number(used[1])) : null, swapTotalMB: total ? Math.floor(Number(total[1])) : null,
  };
}

export function memOf(vm: VmStat, sc: Sysctl, mark: Pick<VmMark, "rate" | "swapRate">): Mem {
  const mb = (pages: number): number => Math.floor((pages * vm.pageB) / 1048576);
  return {
    freeMB: mb(vm.free), specMB: mb(vm.spec), purgMB: mb(vm.purg), fileMB: mb(vm.file), fileMinMB: sc.fileMinPages === null ? mb(vm.file) : mb(sc.fileMinPages),
    swapUsedMB: sc.swapUsedMB ?? 0, swapTotalMB: sc.swapTotalMB ?? 0, press: sc.press ?? 1, comprMBPerMin: mark.rate,
    swapOutMBPerMin: mark.swapRate,
  };
}

export function parseCompressorMB(out: string): number | null {
  const vm = parseVmStat(out);
  return vm ? Math.floor((vm.occupied * vm.pageB) / 1048576) : null;
}

const cmd = (c: string, a: string[]): string => { const r = spawnSync(c, a, { encoding: "utf8" }); return r.status === 0 ? r.stdout : ""; };

const isMark = (x: unknown): x is VmMark =>
  typeof x === "object" && x !== null && (["time", "count", "rate", "swapCount", "swapRate"] as const).every((k) => typeof (x as Record<string, unknown>)[k] === "number");

export function markNext(dir: string, p: Params, now: number, vm: VmStat): VmMark {
  const file = join(dir, "vm-mark.json");
  let prev: VmMark | null = null;
  try { const j: unknown = JSON.parse(readFileSync(file, "utf8")); prev = isMark(j) ? j : null; } catch { prev = null; }
  const next = vmNext(p, prev, now, vm.compressions, vm.swapouts, vm.pageB);
  if (next !== prev) {
    try {
      mkdirSync(dir, { recursive: true });
      const tmp = join(dir, `.vm-mark-${process.pid}.tmp`);
      writeFileSync(tmp, JSON.stringify(next));
      renameSync(tmp, file);
    } catch {}
  }
  return next;
}

export function probe(dir: string, p: Params = DEFAULT_PARAMS): Sample {
  const time = nowS();
  const vm = parseVmStat(cmd("vm_stat", []));
  const mem: Mem = vm === null
    ? { freeMB: Math.floor(os.freemem() / 1048576), specMB: 0, purgMB: 0, fileMB: 0, fileMinMB: 0, swapUsedMB: 0, swapTotalMB: 0, press: 1, comprMBPerMin: 0, swapOutMBPerMin: 0 }
    : memOf(vm, parseSysctl(["vm.vm_page_filecache_min", "kern.memorystatus_vm_pressure_level", "vm.swapusage"].map((o) => cmd("sysctl", [o])).join("")),
      markNext(dir, p, time, vm));
  return {
    time,
    loadCenti: Math.floor((os.loadavg()[0] ?? 0) * 100),
    mem,
    ramMB: Math.floor(os.totalmem() / 1048576),
    compressorMB: vm === null ? 0 : Math.floor((vm.occupied * vm.pageB) / 1048576),
    cores: os.availableParallelism(),
  };
}

function gitIn(cwd: string, args: string[]): string {
  const r = spawnSync("git", args, { cwd, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
}

export const SLOT_MAIN_REL = join("apps", "runner", "src", "slot-main.ts");

export function mainCheckout(cwd: string): string | null {
  const out = gitIn(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  return out === "" ? null : dirname(out);
}

export function resolveSlotMain(local: string, main: string | null, exists: (p: string) => boolean = existsSync): string {
  if (main === null) return local;
  const shared = join(main, SLOT_MAIN_REL);
  return exists(shared) ? shared : local;
}

export function slotMainPath(local: string, cwd: string): string {
  return resolveSlotMain(local, mainCheckout(cwd));
}

export function gitFacts(cwd: string): GitFacts {
  const st = spawnSync("git", ["status", "--porcelain"], { cwd, encoding: "utf8" });
  return { tree: gitIn(cwd, ["rev-parse", "HEAD^{tree}"]), clean: st.status === 0 && st.stdout.trim() === "", mainSha: gitIn(cwd, ["rev-parse", "refs/heads/main"]) };
}

export function simctlShutdown(udid: string): void { spawnSync("xcrun", ["simctl", "shutdown", udid], { stdio: "ignore" }); }

function bootedAll(): SimDevice[] {
  const r = spawnSync("xcrun", ["simctl", "list", "devices", "booted", "-j"], { encoding: "utf8", timeout: 10_000 });
  if (r.error || r.status !== 0) return [];
  const j = JSON.parse(r.stdout) as { devices: Record<string, { udid: string; name: string; state: string }[]> };
  return Object.values(j.devices).flat().filter((d) => d.state === "Booted").map(({ udid, name }) => ({ udid, name }));
}

export function lastHealth(file: string): Health | null {
  let fd: number;
  try { fd = openSync(file, "r"); } catch { return null; }
  try {
    const size = fstatSync(fd).size;
    const len = Math.min(size, 1 << 20);
    const buf = Buffer.alloc(len);
    readSync(fd, buf, 0, len, size - len);
    const line = buf.toString("utf8").trimEnd().split("\n").at(-1) ?? "";
    const j = JSON.parse(line) as { at?: number; output?: { counts?: Record<string, number> } };
    const c = j.output?.counts;
    if (typeof j.at !== "number" || c === undefined) return null;
    const all = Object.values(c).reduce((a, n) => a + n, 0);
    return { time: Math.floor(j.at / 1000), live: Math.max(0, all - (c.done ?? 0) - (c.gone ?? 0)) };
  } catch {
    return null;
  } finally {
    closeSync(fd);
  }
}

export function legacyLive(dir: string): boolean {
  if (!existsSync(dir)) return false;
  let pid = "";
  try { pid = readFileSync(join(dir, "pid"), "utf8").trim(); } catch { return true; }
  return pid === "" || !/^\d+$/.test(pid) || alive(Number(pid));
}

const HISTORY_BYTES = 4 << 20;

export function spanRows(file: string | null): Row[] {
  if (file === null) return [];
  let fd: number;
  try { fd = openSync(file, "r"); } catch { return []; }
  try {
    const size = fstatSync(fd).size;
    const len = Math.min(size, HISTORY_BYTES);
    const buf = Buffer.alloc(len);
    readSync(fd, buf, 0, len, size - len);
    const rows: Row[] = [];
    for (const l of buf.toString("utf8").split("\n")) {
      if (!l.includes('"slot run ')) continue;
      try {
        const j = JSON.parse(l) as { tool?: unknown; step?: unknown; durMs?: unknown; exit?: unknown; host?: unknown };
        if (j.tool !== "fw" || typeof j.step !== "string" || typeof j.durMs !== "number" || typeof j.host !== "string") continue;
        rows.push({ step: j.step, durMs: Math.max(0, Math.round(j.durMs)), exit: typeof j.exit === "number" ? j.exit : null, host: j.host });
      } catch {}
    }
    return rows;
  } finally {
    closeSync(fd);
  }
}

export function realDeps(cwd: string, env: Record<string, string | undefined> = process.env): Deps {
  const main = dirname(gitIn(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]));
  const top = gitIn(cwd, ["rev-parse", "--show-toplevel"]) || cwd;
  const con = env.FW_CONSOLE_DIR ?? join(main, ".fw-console");
  const events = env.FW_LOCK_EVENTS === "off" ? null : env.FW_LOCK_EVENTS_FILE ?? (env.CI ? null : join(con, "locks.jsonl"));
  const dir = env.FW_SLOT_DIR ?? join(con, "slot");
  return {
    dir,
    cacheDir: join(con, "review-cache", "slot"),
    eventsFile: events,
    legacySimLock: join(main, ".local", "locks", "sim"),
    owner: env.FW_SLOT_OWNER ?? basename(top),
    env,
    params: DEFAULT_PARAMS,
    wparams: DEFAULT_WPARAMS,
    history: () => spanRows(timingsFile(cwd)),
    pollMs: 2000,
    probe: () => probe(dir),
    git: () => gitFacts(cwd),
    simctl: { booted: bootedAll, shutdown: simctlShutdown },
    health: () => lastHealth(join(con, "health.jsonl")),
    out: (s) => process.stdout.write(s),
    err: (s) => process.stderr.write(s),
  };
}

const myStart = startOf(process.pid);

function takeLock(lock: string): void {
  for (;;) {
    try {
      mkdirSync(lock);
      writeFileSync(join(lock, "owner"), JSON.stringify({ pid: process.pid, start: myStart }));
      return;
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
    }
    const o = readOwner(lock);
    if (o !== null && dead(o)) recoverStale(lock, o);
    else sleepSync(20);
  }
}

export type Owner = { pid: number; start: number | null };

function readOwner(dir: string): Owner | null {
  try { return JSON.parse(readFileSync(join(dir, "owner"), "utf8")) as Owner; } catch { return null; }
}

const dead = (o: Owner): boolean => !alive(o.pid) || startOf(o.pid) !== o.start;

export function recoverStale(lock: string, seen: Owner): void {
  const aside = `${lock}.stale-${process.pid}`;
  try {
    renameSync(lock, aside);
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return;
    throw e;
  }
  const o = readOwner(aside);
  if (o !== null && o.pid === seen.pid && o.start === seen.start) {
    rmSync(aside, { recursive: true, force: true });
    return;
  }
  try { renameSync(aside, lock); } catch { rmSync(aside, { recursive: true, force: true }); }
}

const withLease = (e: Omit<Entry, "leaseS"> & { leaseS?: number }): Entry => ({ ...e, leaseS: leaseOr(e.leaseS ?? null, e.since, e.till) });

function readState(d: Deps): State {
  let st: State;
  try { st = JSON.parse(readFileSync(join(d.dir, "state.json"), "utf8")) as State; } catch { return { ctl: init(d.params), holders: [], queue: [], simIdleSince: 0 }; }
  return { ...st, holders: st.holders.map(withLease), queue: st.queue.map(withLease) };
}

export function withState<T>(d: Deps, f: (st: State) => T): T {
  mkdirSync(d.dir, { recursive: true });
  const lock = join(d.dir, "state.lock");
  takeLock(lock);
  try {
    const st = readState(d);
    const r = f(st);
    const tmp = join(d.dir, `.state-${process.pid}.tmp`);
    writeFileSync(tmp, JSON.stringify(st));
    renameSync(tmp, join(d.dir, "state.json"));
    return r;
  } finally {
    rmSync(lock, { recursive: true, force: true });
  }
}

function bootedUdids(d: Deps): string[] {
  try { return d.simctl.booted().map((b) => b.udid.toUpperCase()); } catch { return []; }
}

const acquiredOf = (gone: Entry[]): number => Math.min(...gone.filter((h) => h.kind === "sim").map((h) => h.since));

function tick(d: Deps, st: State, s: Sample): void {
  st.ctl = step(d.params, st.ctl, s);
  const gone = expired(s.time, st.holders);
  if (gone.some((h) => h.kind === "sim")) { st.simIdleSince = s.time; st.simAcquired = acquiredOf(gone); st.simUdids = bootedUdids(d); }
  for (const h of gone) {
    event(d, "expire", h.kind, { owner: h.owner, token: h.token, leaseS: h.leaseS, holdMs: (h.till - h.since) * 1000, lateMs: (s.time - h.till) * 1000 });
  }
  st.holders = prune(s.time, st.holders);
  st.queue = prune(s.time, st.queue);
  st.window = current(s.time, st.holders, st.window ?? null);
}

function event(d: Deps, ev: string, kind: Kind, extra: Record<string, number | string>): void {
  if (d.eventsFile === null) return;
  try {
    mkdirSync(dirname(d.eventsFile), { recursive: true });
    appendFileSync(d.eventsFile, `${JSON.stringify({ ts: Date.now(), lock: "slot", ev, kind, pid: process.pid, start: myStart, ...extra })}\n`);
  } catch {}
}

export function describe(v: Verdict): string {
  switch (v.verdict) {
    case "admit": return `admitted (${v.threads} Lean threads, ${v.footMB} MB)`;
    default: {
      const why = v.why === "queued" ? `${v.ahead} of the same kind ahead` : v.why === "older" ? "an older ticket of another kind goes first"
        : v.why === "full" ? `${v.running} running, limit ${v.limit}` : v.why === "simBusy" ? "the Simulator slot is held"
        : v.why === "drain" ? `${v.others} other holders finish before the Simulator starts`
        : v.why === "simFirst" ? "a Simulator ticket goes first"
        : v.why === "memLow" ? `memory is short (${v.availMB} MB available, or pressure, swap or compression high)`
        : v.why === "memory" ? `needs ${v.needMB} MB, ${v.roomMB} MB available above the floor`
        : v.why === "pass" ? "a measure pass is live"
        : v.why === "gap" ? `needs ${v.needS} s (p90 of its runs + settle), ${v.leftS} s left before the next measure pass`
        : v.why === "unknown" ? "a measure window is open and this kind has too few recorded runs to fit a gap"
        : "another measure lease is held";
      return `${v.verdict === "timeout" ? "refused" : "waiting"}: ${why}`;
    }
  }
}

export function describeBuild(v: BuildVerdict): string {
  if (v.verdict === "admit") return "admit";
  switch (v.why) {
    case "simWaits": return "wait: a Simulator ticket is queued";
    case "agentsUnknown": return "wait: no recent health reading (pass --agents n)";
    case "agents": return `wait: ${v.live} live agents, limit ${v.max}`;
    case "memory": return `wait: ${v.availMB} MB available, needs ${v.needMB} MB`;
  }
}

export type Grant = { token: string; owner: string; kind: Kind; till: number; verdict: Verdict; queue?: Queue };

export function predictor(d: Deps): (k: Kind) => number | null {
  let rows: Row[] | null = null;
  return (k) => predict(d.wparams, k, (rows ??= d.history()));
}

export async function acquire(d: Deps, kind: Kind, leaseS: number, waitS: number | null, gapS = 0): Promise<Grant> {
  const token = randomUUID().slice(0, 12);
  const pred = predictor(d);
  const t0 = nowS();
  withState(d, (st) => { st.queue.push({ owner: d.owner, token, kind, since: t0, till: t0 + d.params.leaseS, foot: 0, leaseS: d.params.leaseS }); });
  let last = "";
  let waits: WaitMs[] = [];
  let prev = t0;
  for (;;) {
    const s = d.probe();
    const g = withState(d, (st): Grant => {
      tick(d, st, s);
      let me = st.queue.find((e) => e.token === token);
      if (me === undefined) { me = { owner: d.owner, token, kind, since: t0, till: 0, foot: 0, leaseS: d.params.leaseS }; st.queue.push(me); }
      me.till = s.time + d.params.leaseS;
      const hs = withLegacy(s.time, legacyLive(d.legacySimLock), st.holders);
      const w = current(s.time, hs, st.window ?? null);
      const v = wverdict(d.wparams, w, w === null ? null : pred(kind), d.params, st.ctl.n, s, hs, st.queue, me, Math.max(0, s.time - t0));
      if (v.verdict !== "wait") st.queue = st.queue.filter((e) => e.token !== token);
      const opened = v.verdict === "admit" && kind === "measure" ? openAt(d.wparams, d.owner, token, s.time, gapS) : null;
      const held = grant(d.params, me, s.time, opened === null ? leaseS : capLease(opened, s.time, leaseS), v.verdict === "admit" ? v.footMB : 0);
      if (v.verdict === "admit") st.holders.push(held);
      if (opened !== null) st.window = opened;
      return { token, owner: d.owner, kind, till: held.till, verdict: v };
    });
    if (g.verdict.verdict === "wait") waits = addWait(waits, g.verdict.why, (s.time - prev) * 1000);
    prev = s.time;
    const line = describe(g.verdict);
    if (line !== last) { d.err(`slot ${kind}: ${line}\n`); last = line; }
    for (const l of simCheck(d, s.time, true, false)) d.err(`${l}\n`);
    if (g.verdict.verdict === "admit") {
      const queue = queueOf(kind, waits, (s.time - t0) * 1000);
      noteQueue(queue);
      event(d, "acquire", kind, { waitMs: (s.time - t0) * 1000 });
      return queue === null ? g : { ...g, queue };
    }
    if (g.verdict.verdict === "timeout" || (waitS !== null && s.time - t0 >= waitS)) {
      withState(d, (st) => { st.queue = st.queue.filter((e) => e.token !== token); });
      event(d, "refuse", kind, { waitMs: (s.time - t0) * 1000 });
      return g;
    }
    await sleep(d.pollMs);
  }
}

export function renewToken(d: Deps, token: string, leaseS: number | null): boolean {
  const now = nowS();
  return withState(d, (st) => {
    const w = st.window ?? null;
    const mine = w !== null && w.token === token && w.owner === d.owner;
    const own = st.holders.find((h) => h.owner === d.owner && h.token === token);
    const lease = mine && own !== undefined ? capLease(w, now, leaseS ?? own.leaseS) : leaseS;
    if (mine && lease === 0) return false;
    const r = renew(d.params, now, d.owner, token, lease, st.holders);
    if (r !== null) st.holders = r;
    return r !== null;
  });
}

export function releaseToken(d: Deps, token: string): boolean {
  const ok = withState(d, (st) => {
    const gone = st.holders.filter((h) => h.owner === d.owner && h.token === token);
    if (gone.some((h) => h.kind === "sim")) { st.simIdleSince = nowS(); st.simAcquired = acquiredOf(gone); st.simUdids = bootedUdids(d); }
    st.holders = release(d.owner, token, st.holders);
    st.queue = release(d.owner, token, st.queue);
    if (st.window?.token === token && st.window.owner === d.owner) st.window = null;
    for (const h of gone) event(d, "release", h.kind, { holdMs: (nowS() - h.since) * 1000 });
    return gone.length > 0;
  });
  for (const l of simCheck(d, nowS(), true, false)) d.err(`${l}\n`);
  return ok;
}

export function describePass(v: PassVerdict): string {
  switch (v.pass) {
    case "start": return `pass live until ${new Date(v.till * 1000).toISOString()}`;
    case "wait": return `pass waits: ${v.others} other holder(s) still live`;
    case "gone": return "no live measure lease for this owner and token";
  }
}

export async function passStartCli(d: Deps, token: string, forS: number, waitS: number): Promise<PassVerdict> {
  const t0 = nowS();
  let last = "";
  for (;;) {
    const s = d.probe();
    const v = withState(d, (st): PassVerdict => {
      tick(d, st, s);
      const w = st.window ?? null;
      if (w !== null && w.token === token && w.owner === d.owner) st.window = want(w, s.time);
      const r = passStart(d.wparams, st.window ?? null, s.time, withLegacy(s.time, legacyLive(d.legacySimLock), st.holders), d.owner, token, forS);
      if (r.pass === "start" && st.window) st.window = beginPass(st.window, r.till);
      return r;
    });
    const line = describePass(v);
    if (line !== last) { d.err(`slot pass: ${line}\n`); last = line; }
    if (v.pass !== "wait" || s.time - t0 >= waitS) {
      event(d, v.pass === "start" ? "pass-start" : "pass-refuse", "measure", { token, waitMs: (s.time - t0) * 1000 });
      return v;
    }
    await sleep(d.pollMs);
  }
}

export function passStopCli(d: Deps, token: string, gapS: number): boolean {
  const now = nowS();
  return withState(d, (st) => {
    const w = current(now, st.holders, st.window ?? null);
    if (w === null || w.token !== token || w.owner !== d.owner) return false;
    st.window = stopPass(w, now, gapS);
    event(d, "pass-stop", "measure", { token, gapS });
    return true;
  });
}

type Record_ = { key: CacheKey; exit: number; stdout: string; stderr: string; at: number };
const CAP = 4 << 20;
const cacheFile = (d: Deps, k: CacheKey): string => join(d.cacheDir, `${createHash("sha256").update(JSON.stringify(k)).digest("hex").slice(0, 32)}.json`);

function readRecord(d: Deps, k: CacheKey): Record_ | null {
  try { return JSON.parse(readFileSync(cacheFile(d, k), "utf8")) as Record_; } catch { return null; }
}

async function stopGroup(d: Deps, pid: number, start: number | null): Promise<void> {
  let termAt: number | null = null;
  for (;;) {
    const act = stopAct(d.params, alive(pid), start !== null && startOf(pid) === start, termAt, Date.now());
    if (act === "done") return;
    if (act === "term") { try { process.kill(-pid, "SIGTERM"); } catch {} termAt = Date.now(); }
    if (act === "kill") { try { process.kill(-pid, "SIGKILL"); } catch {} return; }
    await sleep(200);
  }
}

async function exec(d: Deps, argv: string[], env: Record<string, string | undefined>, keep: boolean): Promise<{ exit: number; stdout: string; stderr: string; whole: boolean }> {
  const [c, ...a] = argv;
  if (c === undefined) return { exit: 2, stdout: "", stderr: "", whole: false };
  const child: ChildProcess = spawn(c, a, { stdio: ["inherit", "pipe", "pipe"], env, detached: true });
  const start = child.pid === undefined ? null : startOf(child.pid);
  const bufs = { stdout: [] as Buffer[], stderr: [] as Buffer[] };
  let size = 0;
  const tee = (name: "stdout" | "stderr", w: (s: string) => void) => (b: Buffer) => {
    w(b.toString());
    size += b.length;
    if (keep && size <= CAP) bufs[name].push(b);
  };
  child.stdout?.on("data", tee("stdout", d.out));
  child.stderr?.on("data", tee("stderr", d.err));
  const onSig = () => { if (child.pid !== undefined) void stopGroup(d, child.pid, start); };
  process.on("SIGINT", onSig);
  process.on("SIGTERM", onSig);
  const exit = await new Promise<number>((res) => {
    child.on("error", (e: Error) => { d.err(`slot: ${e.message}\n`); res(127); });
    child.on("close", (code, sig) => res(code ?? (sig ? 128 + (os.constants.signals[sig] ?? 0) : 1)));
  });
  process.off("SIGINT", onSig);
  process.off("SIGTERM", onSig);
  return { exit, stdout: Buffer.concat(bufs.stdout).toString(), stderr: Buffer.concat(bufs.stderr).toString(), whole: size <= CAP };
}

export function nestedHeld(d: Deps, kind: Kind): boolean {
  const token = d.env.FW_SLOT_TOKEN;
  return nestedSkips(nowS(), kind, token ? { owner: d.owner, token } : null, readState(d).holders);
}

export async function run(d: Deps, kind: Kind, argv: string[], cache: boolean): Promise<number> {
  const label = runLabel(kind, argv, argv.includes("--dry"));
  if (nestedHeld(d, kind)) {
    const end = begin("fw", label);
    let r = EXIT_ERROR;
    try { r = (await exec(d, argv, d.env, false)).exit; } finally { end(r); }
    return r;
  }
  const g0 = cache ? d.git() : null;
  const key = g0 === null ? null : keyOf(kind, argv, g0.tree, g0.mainSha, g0.clean);
  if (key !== null) {
    const rec = readRecord(d, key);
    if (rec !== null && cacheHit(rec.key, rec.exit, key)) {
      const endCached = begin("fw", `${label} cached`);
      d.out(rec.stdout);
      d.err(rec.stderr);
      d.err(`slot: replayed the result recorded ${new Date(rec.at * 1000).toISOString()} for tree ${key.tree.slice(0, 12)} (same argv, clean tree)\n`);
      endCached(rec.exit);
      return rec.exit;
    }
  }
  const endWait = begin(WAIT_TOOL, waitStep(kind));
  let g: Awaited<ReturnType<typeof acquire>>;
  try { g = await acquire(d, kind, d.params.leaseS, null); } catch (e) { endWait(EXIT_ERROR); throw e; }
  endWait(g.verdict.verdict === "admit" ? 0 : EXIT_REFUSED, g.queue ? { queue: g.queue } : {});
  if (g.verdict.verdict !== "admit") return EXIT_REFUSED;
  const threads = String(g.verdict.threads);
  const env = { ...d.env, FW_SLOT_HELD: "1", FW_SLOT_TOKEN: g.token, FW_SLOT_OWNER: d.owner, ...(kind === "check" ? { LAKE_SLOT_CORES: threads, LEAN_NUM_THREADS: threads } : {}) };
  const timer = setInterval(() => { renewToken(d, g.token, null); }, Math.max(1, Math.floor(d.params.leaseS / 3)) * 1000);
  const endRun = begin("fw", label);
  let exit = EXIT_ERROR;
  try {
    const r = await exec(d, argv, env, key !== null);
    exit = r.exit;
    endRun(exit);
    if (key !== null && r.whole && cacheable(r.exit)) {
      const g1 = d.git();
      if (g1.tree === key.tree && g1.clean && g1.mainSha === g0?.mainSha) {
        mkdirSync(d.cacheDir, { recursive: true });
        writeFileSync(cacheFile(d, key), JSON.stringify({ key, exit: r.exit, stdout: r.stdout, stderr: r.stderr, at: nowS() }));
      }
    }
    return r.exit;
  } finally {
    endRun(exit);
    clearInterval(timer);
    releaseToken(d, g.token);
  }
}

export function simCheck(d: Deps, now: number, apply: boolean, force: boolean): string[] {
  const due = withState(d, (st) => {
    if (!force && !simDue(d.params, now, st.simCheckedAt ?? 0)) return false;
    st.simCheckedAt = now;
    return true;
  });
  if (!due) return [];
  const booted = d.simctl.booted();
  return withState(d, (st) => {
    const legacy = legacyLive(d.legacySimLock);
    st.simIdle = simIdleNext(now, legacy || simHeld(now, st.holders), booted.length > 0, st.simIdle ?? null);
    const act = simAction(d.params, now, st.holders, booted.length > 0, legacy, st.simIdle);
    const lines = [`sim: ${booted.length} booted device(s), action ${act}`];
    if (apply && act === "shutdown") {
      for (const b of booted) { d.simctl.shutdown(b.udid); lines.push(`sim: shut down ${b.name}`); }
      st.simIdle = null;
    }
    return force || act === "shutdown" ? lines : [];
  });
}

export function windowLine(now: number, w: Window | null): string {
  if (w === null) return "measure window: none";
  const phase = passLive(now, w) ? `pass live, ${w.passTill! - now}s left` : w.next > now ? `gap, next pass in ${w.next - now}s` : "gap closed, next pass due";
  return `measure window: ${w.owner} ${w.token}, ${phase}, deadline in ${w.deadline - now}s`;
}

function status(d: Deps, json: boolean): string[] {
  const s = d.probe();
  const st = withState(d, (x) => { tick(d, x, s); return x; });
  const hs = withLegacy(s.time, legacyLive(d.legacySimLock), st.holders);
  const w = current(s.time, hs, st.window ?? null);
  const pred = predictor(d);
  const why = st.queue.map((e) => ({
    token: e.token,
    verdict: wverdict(d.wparams, w, w === null ? null : pred(e.kind), d.params, st.ctl.n, s, hs, st.queue, e, Math.max(0, s.time - e.since)),
  }));
  if (json) return [JSON.stringify({ sample: s, signal: signal(d.params, st.ctl.prev, s), ...st, why })];
  const rows = (es: Entry[]) => es.map((e) => `  ${e.kind.padEnd(7)} ${e.owner} ${e.token} ${e.till - s.time}s left${e.foot ? `, ${e.foot} MB` : ""}`);
  const queued = st.queue.map((e, i) => `  ${e.kind.padEnd(7)} ${e.owner} ${e.token} queued ${s.time - e.since}s, ${describe(why[i]!.verdict)}`);
  const m = s.mem;
  return [`slot: limit ${st.ctl.n}, load ${(s.loadCenti / 100).toFixed(2)}, available ${avail(s)} MB, pressure ${m.press}, `
    + `swap ${m.swapUsedMB}/${m.swapTotalMB} MB, swapping out ${m.swapOutMBPerMin} MB/min, compressing ${m.comprMBPerMin} MB/min`,
    windowLine(s.time, w), `holders (${st.holders.length}):`, ...rows(st.holders), `queue (${st.queue.length}):`, ...queued];
}

function flag(args: string[], name: string): string | null {
  const i = args.indexOf(name);
  if (i < 0) return null;
  const v = args[i + 1];
  if (v === undefined || v.startsWith("--")) throw new SlotUsage(`${name} needs a value\n${SLOT_USAGE}`);
  return v;
}

function num(args: string[], name: string, unit = "whole seconds"): number | null {
  const v = flag(args, name);
  if (v === null) return null;
  if (!/^\d+$/.test(v)) throw new SlotUsage(`${name} takes ${unit}\n${SLOT_USAGE}`);
  return Number(v);
}

function kindArg(args: string[]): Kind {
  const k = kindOf(flag(args, "--kind") ?? "");
  if (k === null) throw new SlotUsage(`--kind is one of ${KINDS.join(" ")}\n${SLOT_USAGE}`);
  return k;
}

export async function slotCli(argv: string[], deps: Deps): Promise<number> {
  const dash = argv.indexOf("--");
  const args = dash < 0 ? argv : argv.slice(0, dash);
  const d = { ...deps, owner: flag(args, "--owner") ?? deps.owner };
  if (!(SLOT_SUBS as readonly string[]).includes(args[0] ?? "")) throw new SlotUsage(SLOT_USAGE);
  switch (args[0]) {
    case "run": {
      const cmdv = dash < 0 ? [] : argv.slice(dash + 1);
      if (cmdv.length === 0) throw new SlotUsage(SLOT_USAGE);
      return run(d, kindArg(args), cmdv, args.includes("--cache"));
    }
    case "acquire": {
      const g = await acquire(d, kindArg(args), num(args, "--lease") ?? d.params.leaseS, num(args, "--wait"), num(args, "--next") ?? 0);
      const ok = g.verdict.verdict === "admit";
      d.out(args.includes("--json") ? `${JSON.stringify({ ...g, boot: ok && simBoot(nowS(), g.owner, g.token, readState(d).holders) })}\n` : ok ? `${g.token}\n` : "");
      return ok ? 0 : EXIT_REFUSED;
    }
    case "renew": {
      const t = flag(args, "--token");
      if (t === null) throw new SlotUsage(SLOT_USAGE);
      const ok = renewToken(d, t, num(args, "--lease"));
      if (!ok) d.err("slot: no live lease for this owner and token (expired or released)\n");
      return ok ? 0 : 1;
    }
    case "release": {
      const t = flag(args, "--token");
      if (t === null) throw new SlotUsage(SLOT_USAGE);
      if (!releaseToken(d, t)) d.err("slot: nothing held under this owner and token\n");
      return 0;
    }
    case "pass": {
      const t = flag(args, "--token");
      const act = args[1];
      if (t === null || (act !== "start" && act !== "stop")) throw new SlotUsage(SLOT_USAGE);
      if (act === "stop") {
        const ok = passStopCli(d, t, num(args, "--next") ?? 0);
        if (!ok) d.err("slot pass: no live measure lease for this owner and token\n");
        return ok ? 0 : 1;
      }
      const v = await passStartCli(d, t, num(args, "--for") ?? d.wparams.passMaxS, num(args, "--wait") ?? 300);
      d.out(`VERDICT ${v.pass} pass${v.pass === "start" ? ` ${v.till}` : ""}\n`);
      return v.pass === "start" ? 0 : v.pass === "wait" ? EXIT_REFUSED : 1;
    }
    case "status":
      for (const l of status(d, args.includes("--json"))) d.out(`${l}\n`);
      return 0;
    case "sim":
      for (const l of simCheck(d, nowS(), args.includes("--apply"), true)) d.out(`${l}\n`);
      return 0;
    case "held": {
      const k = kindArg(args);
      const held = withState(d, (st) => heldOf(nowS(), st.holders, k));
      d.out(`slot ${k}: ${held ? "held" : "free"}\n`);
      return held ? 0 : 3;
    }
    case "admit": {
      if (flag(args, "--kind") !== "build") throw new SlotUsage(`admit takes --kind build\n${SLOT_USAGE}`);
      const s = d.probe();
      const given = num(args, "--agents", "a whole number");
      const agents = given ?? agentsSeen(d.params, s.time, d.health());
      const v = admitBuild(d.params, simQueued(s.time, readState(d).queue), avail(s), agents);
      d.err(`slot admit build: ${describeBuild(v)} (load ${(s.loadCenti / 100).toFixed(2)}, available ${avail(s)} MB, agents ${agents ?? "unknown"})\n`);
      d.out(`VERDICT ${v.verdict} build\n`);
      return v.verdict === "admit" ? 0 : EXIT_REFUSED;
    }
    default:
      throw new SlotUsage(SLOT_USAGE);
  }
}
