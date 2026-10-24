import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { LOG_TAIL, readLog, reapCli, recordHeld, type StopResult } from "../src/reap.ts";
import { fwcoreCall } from "../src/run.ts";
import { childrenOf, type Raw } from "../src/next.ts";
import { simNew } from "../src/slot-core.ts";
import { parseBooted } from "../src/slot.ts";
import { reapHeldAlerts } from "../src/watch-reap.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
type Case = { name: string; request: Record<string, unknown>; response: unknown };
const cases: Case[] = readFileSync(join(root, "packages", "contracts", "golden", "ops", "reap-fold.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Case);

describe("reap-fold.jsonl golden vectors (the log fold, held/dedupe, Simulator diff) replay through fwcore", () => {
  for (const c of cases) it(c.name, () => { expect(call(c.request)).toEqual(c.response); });
  it("the 7-day coverage leg reports the shortfall for a short log", () => {
    expect(cases.some((c) => (c.response as { verdict?: string }).verdict === "not yet 7 days of coverage")).toBe(true);
  });
});

describe("simNew (TS twin of Fw.Ops.Reap.simNew) agrees with the golden rows", () => {
  for (const c of cases.filter((x) => x.request.op === "ops.reapSimNew")) it(c.name, () => {
    const q = c.request as { before: string[]; after: string[] };
    expect({ udids: simNew(q.before, q.after) }).toEqual(c.response);
  });
});

describe("parseBooted", () => {
  it("bad JSON or a missing devices map gives no devices", () => {
    expect(parseBooted("not json {")).toEqual([]);
    expect(parseBooted("{}")).toEqual([]);
    expect(parseBooted(JSON.stringify({ devices: { r: [{ udid: "A", name: "n", state: "Booted" }, { udid: "B", name: "m", state: "Shutdown" }] } }))).toEqual([{ udid: "A", name: "n" }]);
  });
});

const sel = (pid: number, start: number, kind: string) => ({ pid, start, kind, group: true, reason: "r" });
const result = (selected: ReturnType<typeof sel>[]): StopResult => ({ selected } as unknown as StopResult);

describe("the reap log: reap.held once per identity, a reap.tick per pass, a bounded tail", () => {
  it("records an identity once, then only ticks", () => {
    const con = mkdtempSync(join(tmpdir(), "reap-fold-"));
    const env = { FW_CONSOLE_DIR: con };
    const r = result([sel(10, 100, "orphanLoop"), sel(11, 100, "removed")]);
    recordHeld(root, r, call, 5000, env);
    recordHeld(root, r, call, 6000, env);
    const rows = readLog(root, env) as { type: string; at: number; kind?: string; live?: unknown[] }[];
    expect(rows.map((x) => [x.type, x.at])).toEqual([["reap.held", 5000], ["reap.tick", 5000], ["reap.tick", 6000]]);
    expect(rows[0]!.kind).toBe("orphanLoop");
    expect(rows[1]!.live).toEqual([{ kind: "orphanLoop", pid: 10, start: 100 }]);
    rmSync(con, { recursive: true, force: true });
  });
  it("reads only the last LOG_TAIL bytes: the cut first line and a torn row are dropped", () => {
    const con = mkdtempSync(join(tmpdir(), "reap-fold-"));
    mkdirSync(con, { recursive: true });
    const p = join(con, "reap.jsonl");
    const row = JSON.stringify({ type: "reap.tick", at: 1, live: [] }) + "\n";
    writeFileSync(p, "");
    for (let n = 0; n < Math.ceil(LOG_TAIL / row.length) + 5; n++) appendFileSync(p, row);
    appendFileSync(p, "{torn\n");
    const rows = readLog(root, { FW_CONSOLE_DIR: con });
    expect(rows.length).toBeLessThanOrEqual(Math.floor(LOG_TAIL / row.length) + 1);
    expect(rows.length).toBeGreaterThan(1000);
    expect(rows.every((x) => x.type === "reap.tick")).toBe(true);
    rmSync(con, { recursive: true, force: true });
  });
  it("fw reap --exit prints the verdict of an empty log", () => {
    const con = mkdtempSync(join(tmpdir(), "reap-fold-"));
    const out: string[] = [];
    const prev = process.env.FW_CONSOLE_DIR;
    process.env.FW_CONSOLE_DIR = con;
    try { expect(reapCli(["--exit"], root, call, (s) => out.push(s))).toBe(0); } finally { if (prev === undefined) delete process.env.FW_CONSOLE_DIR; else process.env.FW_CONSOLE_DIR = prev; }
    expect(out.join("\n")).toContain("not yet 7 days of coverage");
    rmSync(con, { recursive: true, force: true });
  });
});

describe("a child fact carries the start of its process", () => {
  const raw = (starts: Map<number, number>): Raw => ({
    now: 100_000, session: 1, agents: [], procs: [{ pid: 50, agent: "a", pids: [50] } as never], ps: [{ pid: 50, ppid: 1, ageMs: 5000, comm: "sleep" }],
    alive: () => true, file: () => null, queuedText: "", ci: [], board: new Map(), starts,
  });
  it("start is set when the table knows the pid, omitted otherwise", () => {
    expect(childrenOf(raw(new Map([[50, 777]])), "a")[0]!.start).toBe(777);
    expect("start" in childrenOf(raw(new Map()), "a")[0]!).toBe(false);
  });
});

describe("reapHeldAlerts from one pass", () => {
  it("names the worktree or pid-N, and the Simulator by pid", () => {
    const h = (pid: number, wt: string | null) => ({ pid, start: 9, kind: "k", group: true, reason: "r", wt });
    const a = reapHeldAlerts({ held: [h(1, "w"), h(2, null)], heldSim: [h(3, null)], starts: new Map() });
    expect(a.map((x) => x.subject)).toEqual(["w", "pid-2", "sim 3"]);
  });
});
