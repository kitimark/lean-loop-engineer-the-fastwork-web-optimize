import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { awaitedPath, canonPath, classify, heldLoops, isCiWait, parseLsofOut, reapCli, select, simSlotFacts, simUdidOf, stopSelected, type Facts, type Io, type ReapRow, type Target } from "../src/reap.ts";
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
  it("reads the sim slot facts from state.json", () => {
    const d = mkdtempSync(join(tmpdir(), "reap-one-"));
    mkdirSync(d, { recursive: true });
    writeFileSync(join(d, "state.json"), JSON.stringify({ simIdleSince: 1200, holders: [{ kind: "sim", till: 2000 }, { kind: "sim", till: 100 }, { kind: "check", till: 2000 }] }));
    expect(simSlotFacts(d, 1500)).toEqual({ simIdleSince: 1200, simAcquired: null, simHolders: 1 });
    writeFileSync(join(d, "state.json"), JSON.stringify({ simIdleSince: 1200, simAcquired: 900, holders: [] }));
    expect(simSlotFacts(d, 1500)).toEqual({ simIdleSince: 1200, simAcquired: 900, simHolders: 0 });
    expect(simSlotFacts(join(d, "missing"), 1500)).toEqual({ simIdleSince: null, simAcquired: null, simHolders: 0 });
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
});

const row = (pid: number, start: number, kind: string, extra: Partial<ReapRow> = {}): ReapRow =>
  ({ pid, ppid: 1, pgid: pid, start, cwd: 5, kind, wt: "w", inRepo: true, ...extra });
const facts = (): Facts => ({
  rows: [row(2846, 1000, "untilLoop", { wt: "w2" }), row(40204, 1000, "untilLoop"),
    row(23868, 1100, "other"), row(3100, 1000, "simDevice", { wt: null, inRepo: false })],
  live: [1], mcps: [], keep: [], liveIds: ["w", "w2"], now: 1800,
  loops: [{ pid: 2846, start: 1000, awaits: "/tmp/mwm-wait.log", callLive: false }, { pid: 40204, start: 1000, awaits: "/tmp/mwm-wait.log", callLive: false }],
  waiters: [{ pid: 23868, start: 1100, wt: "w", writes: "/tmp/mwm-wait.log" }], simIdleSince: 1200, simAcquired: 900, simHolders: 0, ownSims: [{ pid: 3100, start: 1000 }],
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
    expect(stopSelected(root, call, io, facts, [2846, 3100])).not.toBeNull();
    expect(sent.filter(([, s]) => s === "SIGTERM").map(([p]) => p)).toEqual([2846]);
    expect(sims).toEqual([3100]);
    expect(sent.some(([p]) => p === 40204 || p === 3100)).toBe(false);
    expect(select(facts(), call).map((s) => s.pid)).toEqual([2846, 3100]);
  });
  it("reapHeldAlerts raises agent.held with the identity and the command that applies it; FW_WATCH_REAP=0 silences it", () => {
    const a = reapHeldAlerts(root, {}, facts, () => call);
    expect(a).toHaveLength(1);
    expect(a[0]).toMatchObject({ code: "agent.held", subject: "w2" });
    expect(a[0]!.detail).toContain("killOrphan pid=2846 start=1000");
    expect(a[0]!.detail).toContain("fw reap --stop");
    expect(reapHeldAlerts(root, { FW_WATCH_REAP: "0" }, facts, () => call)).toEqual([]);
    expect(reapHeldAlerts(root, {}, () => null, () => call)).toEqual([]);
  });
});
