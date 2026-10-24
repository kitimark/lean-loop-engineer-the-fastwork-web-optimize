import { linkSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { awaitAllowed, awaitedPath, canonAwait, canonPath, classify, heldLoops, inodeOf, isCiWait, parseLsofFiles, parseLsofOut, reapCli, reapStopLines, reapTick, select, simSlotFacts, simUdidOf, stopSelected, type Facts, type Io, type ReapRow, type Target } from "../src/reap.ts";
import { reapHeldAlerts } from "../src/watch-reap.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const cases = readFileSync(join(root, "packages", "contracts", "golden", "ops", "reap-one.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: unknown });
const call = fwcoreCall(root);

describe("reap-one.jsonl golden vectors replay through fwcore", () => {
  it("has the three cases of task reap-watch-one-rule and the alert op", () => {
    const ops = new Set(cases.map((c) => c.request.op));
    for (const op of ["ops.lspReap", "ops.reapPlan", "ops.reapHeld"]) expect(ops.has(op)).toBe(true);
    expect(cases.some((c) => c.name.startsWith("E case 1"))).toBe(true);
    expect(cases.some((c) => c.name.startsWith("E case 2"))).toBe(true);
    expect(cases.some((c) => c.name.startsWith("F case 3"))).toBe(true);
  });
  for (const c of cases) it(c.name, () => { expect(call(c.request)).toEqual(c.response); });
});

const exitCases = readFileSync(join(root, "packages", "contracts", "golden", "ops", "reap-exit.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: unknown });
describe("reap-exit.jsonl golden vectors (the exit rule for E and F) replay through fwcore", () => {
  for (const c of exitCases) it(c.name, () => {
    const err = (c.response as { error?: string }).error;
    if (err !== undefined) expect(() => call(c.request)).toThrow(err);
    else expect(call(c.request)).toEqual(c.response);
  });
  it("neither E nor F is promoted by an empty log: both stay out of autoKinds", () => {
    const empty = exitCases.find((c) => c.name === "an empty log promotes nothing")!;
    expect((call(empty.request) as { promote: string[] }).promote).toEqual([]);
  });
});

describe("facts of branches E and F", () => {
  it("classifies an until-loop shell and a Simulator device", () => {
    expect(classify("/bin/zsh -c source x && eval 'until [ -s /tmp/mwm-wait.log ]; do sleep 5; done'")).toBe("untilLoop");
    expect(classify("/bin/sh -c echo until")).toBe("other");
    expect(classify("/usr/bin/grep until [ -s x ]")).toBe("other");
    const udid = ["AAAAAAAA", "BBBB", "CCCC", "DDDD", "EEEEEEEEEEEE"].join("-");
    expect(classify(`/x/launchd_sim /u/Library/Developer/CoreSimulator/Devices/${udid}/data/var/run/launchd_bootstrap.plist`)).toBe("simDevice");
    expect(simUdidOf(`launchd_sim /CoreSimulator/Devices/${udid.toLowerCase()}/data`)).toBe(udid);
    expect(simUdidOf("launchd_sim /nowhere")).toBeNull();
  });
  it("reads the awaited path", () => {
    expect(awaitedPath("zsh -c until [ -s '/tmp/x.log' ]; do sleep 5; done")).toBe("/tmp/x.log");
    expect(awaitedPath("zsh -c until [ -f /tmp/y ]; do sleep 5; done")).toBe("/tmp/y");
    expect(awaitedPath("zsh -c while true; do :; done")).toBeNull();
  });
  it("finds a fw ci wait and the file its stdout goes to", () => {
    expect(isCiWait("node /r/scripts/fw.mjs ci wait --branch ci/x")).toBe(true);
    expect(isCiWait("pnpm -s fw ci wait 40032804511")).toBe(true);
    expect(isCiWait("pnpm -s fw ci push")).toBe(false);
    expect([...parseLsofOut("p23868\nf1\nn/tmp/mwm-wait.log\nf2\nn/tmp/mwm-wait.log\np5\nf1\nn/dev/null\np6\nf1\nn->0xabc\n")]).toEqual([[23868, "/tmp/mwm-wait.log"]]);
  });
  it("lsof -Fpfin gives path and inode in either field order", () => {
    expect([...parseLsofFiles("p7\nf1\ni55\nn/tmp/a.log\nf2\ni55\nn/tmp/a.log\np8\nf1\nn/tmp/b.log\ni66\np9\nf1\ni3\nn/dev/null\n")])
      .toEqual([[7, { path: "/tmp/a.log", ino: "55" }], [8, { path: "/tmp/b.log", ino: "66" }]]);
  });
  it("inodeOf: a hard link has the inode of the file; a missing file has none", () => {
    const d = mkdtempSync(join(tmpdir(), "reap-ino-"));
    writeFileSync(join(d, "a.log"), "x");
    linkSync(join(d, "a.log"), join(d, "b.log"));
    expect(inodeOf(join(d, "a.log"))).not.toBe("");
    expect(inodeOf(join(d, "a.log"))).toBe(inodeOf(join(d, "b.log")));
    expect(inodeOf(join(d, "missing.log"))).toBe("");
    rmSync(d, { recursive: true, force: true });
  });
  it("reads the sim slot facts from state.json", () => {
    const d = mkdtempSync(join(tmpdir(), "reap-one-"));
    mkdirSync(d, { recursive: true });
    writeFileSync(join(d, "state.json"), JSON.stringify({ simIdleSince: 1200, holders: [{ kind: "sim", till: 2000 }, { kind: "sim", till: 100 }, { kind: "check", till: 2000 }] }));
    expect(simSlotFacts(d, 1500)).toEqual({ simIdleSince: 1200, simAcquired: null, simHolders: 1, simUdids: [] });
    writeFileSync(join(d, "state.json"), JSON.stringify({ simIdleSince: 1200, simAcquired: 900, simUdids: ["aa-1"], holders: [] }));
    expect(simSlotFacts(d, 1500)).toEqual({ simIdleSince: 1200, simAcquired: 900, simHolders: 0, simUdids: ["AA-1"] });
    expect(simSlotFacts(join(d, "missing"), 1500)).toEqual({ simIdleSince: null, simAcquired: null, simHolders: 0, simUdids: [] });
    rmSync(d, { recursive: true, force: true });
  });
  it("canonical paths: a path through a symlinked directory and the real path are one string (/private/tmp/x vs /tmp/x)", () => {
    const d = mkdtempSync(join(tmpdir(), "reap-canon-"));
    const real = join(d, "real");
    mkdirSync(real);
    symlinkSync(real, join(d, "link"));
    expect(canonPath(join(d, "link", "x.log"))).toBe(canonPath(join(real, "x.log")));
    expect(canonPath(join(d, "link", "x.log"))).toBe(join(realpathSync(real), "x.log"));
    expect(canonPath(join(d, "gone", "x.log"))).toBe(join(d, "gone", "x.log"));
    const f = facts();
    f.loops = [{ pid: 2846, start: 1000, awaits: "/tmp/other.log", callLive: false },
      { pid: 40204, start: 1000, awaits: canonPath(join(d, "link", "x.log")), callLive: false }];
    f.waiters = [{ pid: 23868, start: 1100, wt: "w", writes: canonPath(join(real, "x.log")) }];
    expect(select(f, call).map((s) => s.pid)).toEqual([2846, 3100]);
    f.waiters = [{ pid: 23868, start: 1100, wt: "w", writes: join(real, "x.log") }];
    f.loops[1]!.awaits = join(d, "link", "x.log");
    expect(select(f, call).map((s) => s.pid)).toEqual([2846, 40204, 3100]);
    rmSync(d, { recursive: true, force: true });
  });
  it("the awaited path allowlist: letters, digits, . _ / - only; backtick, glob, bracket, tilde keep the loop", () => {
    for (const ok of ["/tmp/mwm-wait.log", "/tmp/a_b/c.1"]) expect(awaitAllowed(ok)).toBe(true);
    for (const bad of ["out.log", "$HOME/x", "/tmp/`x`.log", "/tmp/*.log", "/tmp/?.log", "/tmp/[a].log", "~/x", "/tmp/a b", "/tmp/a;b", "/tmp/a\nb"]) {
      expect(awaitAllowed(bad)).toBe(false);
      expect(canonAwait(bad)).toBe(bad);
      const f = facts();
      f.loops = [{ pid: 2846, start: 1000, awaits: bad, callLive: false }];
      expect(select(f, call).map((x) => x.pid)).toEqual([3100]);
    }
  });
  it("writer evidence by inode: another name for the same file is a writer; the same name for another file is not", () => {
    const f = facts();
    f.loops = [{ pid: 40204, start: 1000, awaits: "/tmp/mwm-wait.log", callLive: false, inode: "55" }];
    f.waiters = [{ pid: 23868, start: 1100, wt: "w", writes: "/tmp/alias.log", inode: "55" }];
    expect(select(f, call).map((x) => x.pid)).toEqual([3100]);
    f.waiters = [{ pid: 23868, start: 1100, wt: "w", writes: "/tmp/mwm-wait.log", inode: "56" }];
    expect(select(f, call).map((x) => x.pid)).toEqual([40204, 3100]);
    f.loops = [{ pid: 40204, start: 1000, awaits: "/tmp/mwm-wait.log", callLive: false, inode: "" }];
    expect(select(f, call).map((x) => x.pid)).toEqual([3100]);
  });
  it("a relative or $-bearing awaited path stays raw and its loop is kept", () => {
    expect(canonAwait("out.log")).toBe("out.log");
    expect(canonAwait("$HOME/x")).toBe("$HOME/x");
    for (const awaits of [canonAwait("out.log"), canonAwait("$HOME/x")]) {
      const f = facts();
      f.loops = [{ pid: 2846, start: 1000, awaits, callLive: false }];
      expect(select(f, call).map((s) => s.pid)).toEqual([3100]);
    }
  });
  it("a held legacy sim-lock keeps the Simulator; a missing legacyHeld fact keeps it too", () => {
    expect(select({ ...facts(), legacyHeld: true }, call).map((s) => s.pid)).toEqual([2846]);
    const { legacyHeld: _, ...noFact } = facts();
    expect(select(noFact, call).map((s) => s.pid)).toEqual([2846]);
  });
});

const row = (pid: number, start: number, kind: string, extra: Partial<ReapRow> = {}): ReapRow =>
  ({ pid, ppid: 1, pgid: pid, start, cwd: 5, kind, wt: "w", inRepo: true, ...extra });
const facts = (): Facts => ({
  rows: [row(2846, 1000, "untilLoop", { wt: "w2" }), row(40204, 1000, "untilLoop"),
    row(23868, 1100, "other"), row(3100, 1000, "simDevice", { wt: null, inRepo: false })],
  live: [1], mcps: [], keep: [], liveIds: ["w", "w2"], now: 1800,
  loops: [{ pid: 2846, start: 1000, awaits: "/tmp/mwm-wait.log", callLive: false }, { pid: 40204, start: 1000, awaits: "/tmp/mwm-wait.log", callLive: false }],
  waiters: [{ pid: 23868, start: 1100, wt: "w", writes: "/tmp/mwm-wait.log" }], simIdleSince: 1200, simAcquired: 900, simHolders: 0, ownSims: [{ pid: 3100, start: 1000 }],
  legacyHeld: false,
});

describe("the watch alert and fw reap read one rule", () => {
  it("--list names the orphan loop and the Simulator, not the loop with a live writer", () => {
    const out: string[] = [];
    const io: Io = { signal: () => { throw new Error("no signal in a test"); }, sleep: () => {}, table: () => null, rss: () => new Map() };
    expect(reapCli(["--list"], root, call, (s) => out.push(s), facts, io)).toBe(0);
    expect(out.map((l) => l.split(" ")[0])).toEqual(["2846", "3100"]);
  });
  it("the alert names pid and start of the loop that --stop TERMs, and nothing else", () => {
    const alerts = heldLoops(facts(), call);
    expect(alerts.map((a) => [a.pid, a.start, a.subject])).toEqual([[2846, 1000, "w2"]]);
    const sent: [number, string][] = [];
    const sims: number[] = [];
    const io: Io = { signal: (t: Target, sig) => { sent.push([t.pid, sig]); }, sleep: () => {}, table: () => facts().rows, rss: () => new Map(),
      simStop: (t: Target) => { sims.push(t.pid); } };
    expect(stopSelected(root, call, io, facts, [2846, 3100], false)).not.toBeNull();
    expect(sent.filter(([, s]) => s === "SIGTERM").map(([p]) => p)).toEqual([2846]);
    expect(sims).toEqual([3100]);
    expect(sent.some(([p]) => p === 40204 || p === 3100)).toBe(false);
    expect(select(facts(), call).map((s) => s.pid)).toEqual([2846, 3100]);
  });
  it("the watch tick (auto plan) stops neither the orphan loop nor the Simulator while the alert still names the loop", () => {
    const sent: number[] = [];
    const io: Io = { signal: (t: Target) => { sent.push(t.pid); }, sleep: () => {}, table: () => facts().rows, rss: () => new Map(),
      simStop: (t: Target) => { sent.push(t.pid); } };
    const con = mkdtempSync(join(tmpdir(), "reap-con-"));
    const env = { FW_CONSOLE_DIR: con };
    expect(reapTick(root, env, io, facts, () => call, [2846, 3100])).toEqual([expect.stringContaining("REAP advice simBooted 3100")]);
    expect(reapTick(root, env, io, facts, () => call, [2846, 3100])).toEqual([]);
    const log = readFileSync(join(con, "reap.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as { type: string; kind: string; pid: number; start: number });
    expect(log.map((r) => [r.type, r.kind, r.pid, r.start])).toEqual(
      [["reap.held", "orphanLoop", 2846, 1000], ["reap.held", "simBooted", 3100, 1000], ["reap.held", "orphanLoop", 2846, 1000], ["reap.held", "simBooted", 3100, 1000]]);
    rmSync(con, { recursive: true, force: true });
    expect(stopSelected(root, call, io, facts, [2846, 3100])?.termed).toEqual([]);
    expect(sent).toEqual([]);
    expect(heldLoops(facts(), call).map((a) => [a.pid, a.start])).toEqual([[2846, 1000]]);
  });
  it("reapHeldAlerts raises agent.held with the identity and the command that applies it; FW_WATCH_REAP=0 silences it", () => {
    const a = reapHeldAlerts(root, {}, facts, () => call);
    expect(a).toHaveLength(2);
    expect(a[1]).toMatchObject({ code: "agent.held", subject: "sim 3100" });
    expect(a[1]!.detail).toContain("simBooted pid=3100 start=1000");
    expect(a[0]).toMatchObject({ code: "agent.held", subject: "w2" });
    expect(a[0]!.detail).toContain("killOrphan pid=2846 start=1000");
    expect(a[0]!.detail).toContain("fw reap --stop");
    expect(reapHeldAlerts(root, { FW_WATCH_REAP: "0" }, facts, () => call)).toEqual([]);
    expect(reapHeldAlerts(root, {}, () => null, () => call)).toEqual([]);
  });
});

describe("a mixed auto plan: an A-D target in the process group of an orphan loop", () => {
  const mixed = (): Facts => ({
    rows: [row(7000, 1000, "untilLoop", { wt: "w2", pgid: 7000 }), row(7001, 1000, "tool", { wt: "gone", pgid: 7000 }), row(23868, 1100, "other")],
    live: [1], mcps: [], keep: [], liveIds: ["w", "w2"], now: 1800,
    loops: [{ pid: 7000, start: 1000, awaits: "/tmp/mwm-wait.log", callLive: false }], waiters: [], legacyHeld: false,
  });
  const run = (gone: { v: boolean }) => {
    const sent: [number, boolean, string][] = [];
    const io: Io = {
      signal: (t: Target, sig) => { sent.push([t.pid, t.group, sig]); if (t.pid === 7001) gone.v = true; },
      sleep: () => {}, rss: () => new Map(),
      table: () => mixed().rows.filter((r) => !(gone.v && r.pid === 7001)),
    };
    return { sent, io };
  };
  it("the loop gets no signal; the tool is signalled by pid, not by group; the default scope is the plan targets", () => {
    const gone = { v: false };
    const { sent, io } = run(gone);
    const r = stopSelected(root, call, io, mixed, undefined, true)!;
    expect(r.selected.map((s) => s.pid).sort()).toEqual([7000, 7001]);
    expect(r.targets.map((t) => [t.pid, t.group])).toEqual([[7001, false]]);
    expect(r.held.map((h) => [h.pid, h.kind])).toEqual([[7000, "orphanLoop"]]);
    expect(r.refused).toEqual([]);
    expect(sent).toEqual([[7001, false, "SIGTERM"]]);
  });
  it("a signal on the loop is refused by the guard because the scope is the targets, not the selection", () => {
    const gone = { v: false };
    const { io } = run(gone);
    const g = call({ op: "ops.reapGuard", scope: [7001], rows: mixed().rows, target: { pid: 7000, start: 1000, group: false } }) as { allowed: boolean };
    expect(g.allowed).toBe(false);
    expect(io.table()).not.toBeNull();
  });
  it("reapStopLines counts the targets (1 of 1) and names the loop as advice on its own line", () => {
    const gone = { v: false };
    const { io } = run(gone);
    const con = mkdtempSync(join(tmpdir(), "reap-lines-"));
    const before = process.env.FW_CONSOLE_DIR;
    process.env.FW_CONSOLE_DIR = con;
    let lines: string[];
    try { lines = reapStopLines(root, call, io, mixed, undefined); } finally {
      if (before === undefined) delete process.env.FW_CONSOLE_DIR; else process.env.FW_CONSOLE_DIR = before;
      rmSync(con, { recursive: true, force: true });
    }
    expect(lines[0]).toBe("leftover processes stopped: 1 of 1");
    expect(lines.at(-1)).toBe("not stopped (advice, fw reap --stop applies it): orphanLoop 7000");
  });
  it("a plan with only advice rows prints the advice line and no stop count", () => {
    const f = (): Facts => ({ ...mixed(), rows: mixed().rows.filter((r) => r.pid !== 7001) });
    const lines = reapStopLines(root, call, { signal: () => { throw new Error("no signal"); }, sleep: () => {}, rss: () => new Map(), table: () => f().rows }, f);
    expect(lines).toEqual(["not stopped (advice, fw reap --stop applies it): orphanLoop 7000"]);
  });
});
