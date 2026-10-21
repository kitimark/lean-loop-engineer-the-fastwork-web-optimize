// fw slot (task local-adaptive-queue): one queue for heavy local work. Decisions are slot-core.ts (Fw.Sup.Adapt); this
// file is I/O glue: the probe, the state file under a short mkdir lock, the child process group, and the result cache.
import { type ChildProcess, spawn, spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { appendFileSync, closeSync, existsSync, fstatSync, mkdirSync, openSync, readFileSync, readSync, renameSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import { basename, dirname, join } from "node:path";
import {
  DEFAULT_PARAMS, type BuildVerdict, type CacheKey, type Ctl, type Entry, type Kind, type Params, type Sample, type Verdict,
  admitBuild, agentsSeen, cacheHit, cacheable, heldOf, init, keyOf, kindOf, prune, release, renew, signal, simAction, simBoot,
  simDue, simHeld, simIdleNext, simQueued, step, stopAct, verdict, withLegacy,
} from "./slot-core.ts";

export class SlotUsage extends Error {}

export const SLOT_USAGE = [
  "usage: fw slot run --kind <k> [--cache] [--owner o] -- <command> [args...]   (waits for a slot, runs, releases; exit 75 when refused)",
  "       fw slot acquire --kind <k> [--lease s] [--wait s] [--owner o] [--json]  (holds a slot across tool calls; prints the token)",
  "       fw slot renew --token t [--lease s] [--owner o] | fw slot release --token t [--owner o]",
  "       fw slot status [--json] | fw slot sim [--apply] | fw slot held --kind <k>   (kinds: check test land sim other)",
  "       fw slot admit --kind build [--agents n]   (may the lead start one more builder; VERDICT line, exit 0 admit, 75 wait)",
].join("\n");

export const EXIT_REFUSED = 75;

/** `simIdleSince` is the field of the first slot version, still written for checkouts that read it. */
export type State = { ctl: Ctl; holders: Entry[]; queue: Entry[]; simIdleSince: number; simIdle?: number | null; simCheckedAt?: number };
export type Health = { time: number; live: number };
export type GitFacts = { tree: string; clean: boolean; mainSha: string };
export type SimDevice = { udid: string; name: string };

/** Everything the CLI touches outside its own memory; tests pass temp dirs and fakes. */
export type Deps = {
  dir: string;
  cacheDir: string;
  eventsFile: string | null;
  legacySimLock: string;
  owner: string;
  env: Record<string, string | undefined>;
  params: Params;
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

/** Process start time (epoch s) of `pid`, null when it is gone. */
export function startOf(pid: number): number | null {
  const r = spawnSync("ps", ["-o", "lstart=", "-p", String(pid)], { encoding: "utf8", env: { ...process.env, LC_ALL: "C", TZ: "UTC" } });
  const s = (r.stdout ?? "").trim();
  if (!s) return null;
  const t = Date.parse(`${s} UTC`);
  return Number.isNaN(t) ? null : Math.floor(t / 1000);
}

const alive = (pid: number): boolean => { try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; } };

export const parseFreePct = (out: string): number | null => { const m = /free percentage:\s*(\d+)%/.exec(out); return m ? Number(m[1]) : null; };
export const parseSwapUsedMB = (out: string): number | null => { const m = /used = ([\d.]+)M/.exec(out); return m ? Math.floor(Number(m[1])) : null; };
export function parseCompressorMB(out: string): number | null {
  const page = /page size of (\d+) bytes/.exec(out);
  const occ = /Pages occupied by compressor:\s+(\d+)/.exec(out);
  return page && occ ? Math.floor((Number(occ[1]) * Number(page[1])) / 1048576) : null;
}

const cmd = (c: string, a: string[]): string => { const r = spawnSync(c, a, { encoding: "utf8" }); return r.status === 0 ? r.stdout : ""; };

/** One probe sample of this machine (macOS tools, falling back to Node's view elsewhere). */
export function probe(): Sample {
  const ramMB = Math.floor(os.totalmem() / 1048576);
  const pct = parseFreePct(cmd("memory_pressure", []));
  return {
    time: nowS(),
    loadCenti: Math.floor((os.loadavg()[0] ?? 0) * 100),
    freeMB: pct === null ? Math.floor(os.freemem() / 1048576) : Math.floor((pct * ramMB) / 100),
    ramMB,
    compressorMB: parseCompressorMB(cmd("vm_stat", [])) ?? 0,
    swapUsedMB: parseSwapUsedMB(cmd("sysctl", ["-n", "vm.swapusage"])) ?? 0,
    cores: os.availableParallelism(),
  };
}

function gitIn(cwd: string, args: string[]): string {
  const r = spawnSync("git", args, { cwd, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
}

export function gitFacts(cwd: string): GitFacts {
  const st = spawnSync("git", ["status", "--porcelain"], { cwd, encoding: "utf8" });
  return { tree: gitIn(cwd, ["rev-parse", "HEAD^{tree}"]), clean: st.status === 0 && st.stdout.trim() === "", mainSha: gitIn(cwd, ["rev-parse", "refs/heads/main"]) };
}

function bootedAll(): SimDevice[] {
  const r = spawnSync("xcrun", ["simctl", "list", "devices", "booted", "-j"], { encoding: "utf8" });
  if (r.status !== 0) return [];
  const j = JSON.parse(r.stdout) as { devices: Record<string, { udid: string; name: string; state: string }[]> };
  return Object.values(j.devices).flat().filter((d) => d.state === "Booted").map(({ udid, name }) => ({ udid, name }));
}

/** The last line of the console health log (it grows past 100 MB, so only its tail is read): its time in seconds and the
agents neither done nor gone. */
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

/** The old `scripts/sim-lock.sh` lock is held while its directory exists and its pid, once written, is alive. */
export function legacyLive(dir: string): boolean {
  if (!existsSync(dir)) return false;
  let pid = "";
  try { pid = readFileSync(join(dir, "pid"), "utf8").trim(); } catch { return true; }
  return pid === "" || !/^\d+$/.test(pid) || alive(Number(pid));
}

/** Production dependencies for the checkout at `cwd`. */
export function realDeps(cwd: string, env: Record<string, string | undefined> = process.env): Deps {
  const main = dirname(gitIn(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]));
  const top = gitIn(cwd, ["rev-parse", "--show-toplevel"]) || cwd;
  const con = env.FW_CONSOLE_DIR ?? join(main, ".fw-console");
  const events = env.FW_LOCK_EVENTS === "off" ? null : env.FW_LOCK_EVENTS_FILE ?? (env.CI ? null : join(con, "locks.jsonl"));
  return {
    dir: env.FW_SLOT_DIR ?? join(con, "slot"),
    cacheDir: join(con, "review-cache", "slot"),
    eventsFile: events,
    legacySimLock: join(main, ".local", "locks", "sim"),
    owner: env.FW_SLOT_OWNER ?? basename(top),
    env,
    params: DEFAULT_PARAMS,
    pollMs: 2000,
    probe,
    git: () => gitFacts(cwd),
    simctl: { booted: bootedAll, shutdown: (u) => { spawnSync("xcrun", ["simctl", "shutdown", u], { stdio: "ignore" }); } },
    health: () => lastHealth(join(con, "health.jsonl")),
    out: (s) => process.stdout.write(s),
    err: (s) => process.stderr.write(s),
  };
}

// ---- state file under a short mkdir lock ----

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

/** Move the lock aside before deleting it, so only one waiter recovers a dead owner's lock; a lock that turns out live
is moved back. */
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

function readState(d: Deps): State {
  try { return JSON.parse(readFileSync(join(d.dir, "state.json"), "utf8")) as State; } catch { return { ctl: init(d.params), holders: [], queue: [], simIdleSince: 0 }; }
}

/** Run `f` on the state with the lock held, then write it back atomically. */
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

/** One controller step on `s`, then drop expired holders and tickets; a dropped Simulator holder starts the idle clock. */
function tick(d: Deps, st: State, s: Sample): void {
  st.ctl = step(d.params, st.ctl, s);
  const kept = prune(s.time, st.holders);
  if (st.holders.some((h) => h.kind === "sim" && !kept.includes(h))) st.simIdleSince = s.time;
  st.holders = kept;
  st.queue = prune(s.time, st.queue);
}

function event(d: Deps, ev: string, kind: Kind, extra: Record<string, number>): void {
  if (d.eventsFile === null) return;
  try {
    mkdirSync(dirname(d.eventsFile), { recursive: true });
    appendFileSync(d.eventsFile, `${JSON.stringify({ ts: Date.now(), lock: "slot", ev, kind, pid: process.pid, start: myStart, ...extra })}\n`);
  } catch { /* events never fail a job */ }
}

export function describe(v: Verdict): string {
  switch (v.verdict) {
    case "admit": return `admitted (${v.threads} Lean threads, ${v.footMB} MB)`;
    default: {
      const why = v.why === "queued" ? `${v.ahead} of the same kind ahead` : v.why === "older" ? "an older ticket of another kind goes first"
        : v.why === "full" ? `${v.running} running, limit ${v.limit}` : v.why === "simBusy" ? "the Simulator slot is held"
        : v.why === "drain" ? `${v.others} other holders finish before the Simulator starts`
        : v.why === "simFirst" ? "a Simulator ticket goes first"
        : `needs ${v.needMB} MB, ${v.roomMB} MB free above the floor`;
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
    case "memory": return `wait: ${v.freeMB} MB free, needs ${v.needMB} MB`;
  }
}

export type Grant = { token: string; owner: string; kind: Kind; till: number; verdict: Verdict };

/** Queue a ticket and wait for a verdict: admit (now a holder), timeout, or `waitS` passed (ticket withdrawn). */
export async function acquire(d: Deps, kind: Kind, leaseS: number, waitS: number | null): Promise<Grant> {
  const token = randomUUID().slice(0, 12);
  const t0 = nowS();
  withState(d, (st) => { st.queue.push({ owner: d.owner, token, kind, since: t0, till: t0 + d.params.leaseS, foot: 0 }); });
  let last = "";
  for (;;) {
    const s = d.probe();
    const g = withState(d, (st): Grant => {
      tick(d, st, s);
      let me = st.queue.find((e) => e.token === token);
      if (me === undefined) { me = { owner: d.owner, token, kind, since: t0, till: 0, foot: 0 }; st.queue.push(me); }
      me.till = s.time + d.params.leaseS;
      const hs = withLegacy(s.time, legacyLive(d.legacySimLock), st.holders);
      const v = verdict(d.params, st.ctl.n, s, hs, st.queue, me, Math.max(0, s.time - t0));
      if (v.verdict !== "wait") st.queue = st.queue.filter((e) => e.token !== token);
      const till = s.time + Math.min(leaseS, d.params.leaseMaxS);
      if (v.verdict === "admit") st.holders.push({ owner: d.owner, token, kind, since: s.time, till, foot: v.footMB });
      return { token, owner: d.owner, kind, till, verdict: v };
    });
    const line = describe(g.verdict);
    if (line !== last) { d.err(`slot ${kind}: ${line}\n`); last = line; }
    for (const l of simCheck(d, s.time, true, false)) d.err(`${l}\n`);
    if (g.verdict.verdict === "admit") { event(d, "acquire", kind, { waitMs: (s.time - t0) * 1000 }); return g; }
    if (g.verdict.verdict === "timeout" || (waitS !== null && s.time - t0 >= waitS)) {
      withState(d, (st) => { st.queue = st.queue.filter((e) => e.token !== token); });
      event(d, "refuse", kind, { waitMs: (s.time - t0) * 1000 });
      return g;
    }
    await sleep(d.pollMs);
  }
}

export function renewToken(d: Deps, token: string, leaseS: number): boolean {
  const now = nowS();
  return withState(d, (st) => {
    const r = renew(d.params, now, d.owner, token, leaseS, st.holders);
    if (r !== null) st.holders = r;
    return r !== null;
  });
}

export function releaseToken(d: Deps, token: string): boolean {
  const ok = withState(d, (st) => {
    const gone = st.holders.filter((h) => h.owner === d.owner && h.token === token);
    if (gone.some((h) => h.kind === "sim")) st.simIdleSince = nowS();
    st.holders = release(d.owner, token, st.holders);
    st.queue = release(d.owner, token, st.queue);
    for (const h of gone) event(d, "release", h.kind, { holdMs: (nowS() - h.since) * 1000 });
    return gone.length > 0;
  });
  for (const l of simCheck(d, nowS(), true, false)) d.err(`${l}\n`);
  return ok;
}

// ---- result cache ----

type Record_ = { key: CacheKey; exit: number; stdout: string; stderr: string; at: number };
const CAP = 4 << 20;
const cacheFile = (d: Deps, k: CacheKey): string => join(d.cacheDir, `${createHash("sha256").update(JSON.stringify(k)).digest("hex").slice(0, 32)}.json`);

function readRecord(d: Deps, k: CacheKey): Record_ | null {
  try { return JSON.parse(readFileSync(cacheFile(d, k), "utf8")) as Record_; } catch { return null; }
}

// ---- run ----

/** Stop the child group: TERM, then KILL after the grace while the leader's pid and start are unchanged. */
async function stopGroup(d: Deps, pid: number, start: number | null): Promise<void> {
  let termAt: number | null = null;
  for (;;) {
    const act = stopAct(d.params, alive(pid), start !== null && startOf(pid) === start, termAt, Date.now());
    if (act === "done") return;
    if (act === "term") { try { process.kill(-pid, "SIGTERM"); } catch { /* already gone */ } termAt = Date.now(); }
    if (act === "kill") { try { process.kill(-pid, "SIGKILL"); } catch { /* already gone */ } return; }
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

export async function run(d: Deps, kind: Kind, argv: string[], cache: boolean): Promise<number> {
  if (d.env.FW_SLOT_HELD) return (await exec(d, argv, d.env, false)).exit;
  const g0 = cache ? d.git() : null;
  const key = g0 === null ? null : keyOf(kind, argv, g0.tree, g0.mainSha, g0.clean);
  if (key !== null) {
    const rec = readRecord(d, key);
    if (rec !== null && cacheHit(rec.key, rec.exit, key)) {
      d.out(rec.stdout);
      d.err(rec.stderr);
      d.err(`slot: replayed the result recorded ${new Date(rec.at * 1000).toISOString()} for tree ${key.tree.slice(0, 12)} (same argv, clean tree)\n`);
      return rec.exit;
    }
  }
  const g = await acquire(d, kind, d.params.leaseS, null);
  if (g.verdict.verdict !== "admit") return EXIT_REFUSED;
  const threads = String(g.verdict.threads);
  const env = { ...d.env, FW_SLOT_HELD: "1", FW_SLOT_TOKEN: g.token, FW_SLOT_OWNER: d.owner, ...(kind === "check" ? { LAKE_SLOT_CORES: threads, LEAN_NUM_THREADS: threads } : {}) };
  const timer = setInterval(() => { renewToken(d, g.token, d.params.leaseS); }, Math.max(1, Math.floor(d.params.leaseS / 3)) * 1000);
  try {
    const r = await exec(d, argv, env, key !== null);
    if (key !== null && r.whole && cacheable(r.exit)) {
      const g1 = d.git();
      if (g1.tree === key.tree && g1.clean && g1.mainSha === g0?.mainSha) {
        mkdirSync(d.cacheDir, { recursive: true });
        writeFileSync(cacheFile(d, key), JSON.stringify({ key, exit: r.exit, stdout: r.stdout, stderr: r.stderr, at: nowS() }));
      }
    }
    return r.exit;
  } finally {
    clearInterval(timer);
    releaseToken(d, g.token);
  }
}

// ---- status and the Simulator ----

/** Look at every booted Simulator device when `simDue` (or `force`): advance the idle clock (`simIdleNext`) and, with
`apply`, shut the devices down when `simAction` says so. The decision and the shutdown run under the state lock, so no
Simulator slot is admitted between them. */
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

function status(d: Deps, json: boolean): string[] {
  const s = d.probe();
  const st = withState(d, (x) => { tick(d, x, s); return x; });
  if (json) return [JSON.stringify({ sample: s, signal: signal(d.params, st.ctl.prev, s), ...st })];
  const rows = (es: Entry[]) => es.map((e) => `  ${e.kind.padEnd(6)} ${e.owner} ${e.token} ${e.till - s.time}s left${e.foot ? `, ${e.foot} MB` : ""}`);
  return [`slot: limit ${st.ctl.n}, load ${(s.loadCenti / 100).toFixed(2)}, free ${s.freeMB} MB, swap ${s.swapUsedMB} MB`,
    `holders (${st.holders.length}):`, ...rows(st.holders), `queue (${st.queue.length}):`, ...rows(st.queue)];
}

// ---- CLI ----

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
  if (k === null) throw new SlotUsage(`--kind is one of check test land sim other\n${SLOT_USAGE}`);
  return k;
}

/** `fw slot ...`; resolves to the exit code. */
export async function slotCli(argv: string[], deps: Deps): Promise<number> {
  const dash = argv.indexOf("--");
  const args = dash < 0 ? argv : argv.slice(0, dash);
  const d = { ...deps, owner: flag(args, "--owner") ?? deps.owner };
  switch (args[0]) {
    case "run": {
      const cmdv = dash < 0 ? [] : argv.slice(dash + 1);
      if (cmdv.length === 0) throw new SlotUsage(SLOT_USAGE);
      return run(d, kindArg(args), cmdv, args.includes("--cache"));
    }
    case "acquire": {
      const g = await acquire(d, kindArg(args), num(args, "--lease") ?? d.params.leaseS, num(args, "--wait"));
      const ok = g.verdict.verdict === "admit";
      d.out(args.includes("--json") ? `${JSON.stringify({ ...g, boot: ok && simBoot(nowS(), g.owner, g.token, readState(d).holders) })}\n` : ok ? `${g.token}\n` : "");
      return ok ? 0 : EXIT_REFUSED;
    }
    case "renew": {
      const t = flag(args, "--token");
      if (t === null) throw new SlotUsage(SLOT_USAGE);
      const ok = renewToken(d, t, num(args, "--lease") ?? d.params.leaseS);
      if (!ok) d.err("slot: no live lease for this owner and token (expired or released)\n");
      return ok ? 0 : 1;
    }
    case "release": {
      const t = flag(args, "--token");
      if (t === null) throw new SlotUsage(SLOT_USAGE);
      if (!releaseToken(d, t)) d.err("slot: nothing held under this owner and token\n");
      return 0;
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
      return held ? 0 : 1;
    }
    case "admit": {
      if (flag(args, "--kind") !== "build") throw new SlotUsage(`admit takes --kind build\n${SLOT_USAGE}`);
      const s = d.probe();
      const given = num(args, "--agents", "a whole number");
      const agents = given ?? agentsSeen(d.params, s.time, d.health());
      const v = admitBuild(d.params, simQueued(s.time, readState(d).queue), s.freeMB, agents);
      d.err(`slot admit build: ${describeBuild(v)} (load ${(s.loadCenti / 100).toFixed(2)}, free ${s.freeMB} MB, agents ${agents ?? "unknown"})\n`);
      d.out(`VERDICT ${v.verdict} build\n`);
      return v.verdict === "admit" ? 0 : EXIT_REFUSED;
    }
    default:
      throw new SlotUsage(SLOT_USAGE);
  }
}
