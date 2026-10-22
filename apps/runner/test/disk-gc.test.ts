import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, lutimesSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { clsOf, diskGc, diskGcTick, DiskGcUsage, gatherEventFacts, isLink, ownerMarker, parseArgs, worktrees, type Io, type Roots } from "../src/disk-gc.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const cases = readFileSync(join(root, "packages", "contracts", "golden", "ops", "diskgc.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });

describe("ops.diskGc golden vectors replay through fwcore", () => {
  const call = fwcoreCall(root);
  it("covers both ops and every class", () => {
    expect(new Set(cases.map((c) => c.request.op))).toEqual(new Set(["ops.diskGc", "ops.diskGcPath", "ops.diskGcFacts"]));
    const listed = new Set(cases.flatMap((c) => ((c.response.items ?? []) as { num?: number }[]).map((i) => i.num)));
    expect([...listed].sort()).toEqual([1, 2, 3, 4, 5, 6, 7]);
  });
  for (const c of cases) it(c.name, () => {
    if (typeof c.response.error === "string") expect(() => call(c.request)).toThrow(c.response.error);
    else expect(call(c.request)).toEqual(c.response);
  });
});

describe("arguments", () => {
  it("parses classes by number or name, deduplicated; default all", () => {
    expect(parseArgs([]).classes).toEqual(["lake", "landed", "idle", "scratch", "sim", "console", "usertmp"]);
    expect(parseArgs(["--delete", "--class", "1,landed", "--class", "6", "--class", "2"])).toEqual({ mode: "delete", classes: ["lake", "landed", "console"] });
    expect(parseArgs(["--list", "--idle-h", "48", "--keep-days", "3"])).toMatchObject({ mode: "list", idleH: 48, keepDays: 3 });
    expect(clsOf("7")).toBe("usertmp");
    expect(clsOf("8")).toBeNull();
    expect(parseArgs(["--list", "--tmp-h", "3", "--pressure"])).toMatchObject({ tmpH: 3, pressure: true });
    expect(() => parseArgs(["--class", "8"])).toThrow(DiskGcUsage);
    expect(() => parseArgs(["--idle-h"])).toThrow(DiskGcUsage);
    expect(() => parseArgs(["--force"])).toThrow(DiskGcUsage);
  });
});

const env = { ...process.env, GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" };
const g = (cwd: string, ...args: string[]) => execFileSync("git", args, { cwd, env, encoding: "utf8" });
const old = Date.now() / 1000 - 30 * 86400;
const age = (p: string) => utimesSync(p, old, old);
const file = (p: string, text = "x", aged = true) => { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, text); if (aged) { age(p); age(dirname(p)); } };
const UDID = "0a1b2c3d-0000-1111-2222-333344445555";
const temps: string[] = [];
afterAll(() => { for (const t of temps) rmSync(t, { recursive: true, force: true }); });

function tree() {
  const t = realpathSync(mkdtempSync(join(tmpdir(), "diskgc")));
  temps.push(t);
  const repo = join(t, "repo");
  mkdirSync(repo);
  g(repo, "init", "-q", "-b", "main");
  writeFileSync(join(repo, ".gitignore"), "node_modules/\n.lake/\n.fw-console/\n.claude/\n");
  file(join(repo, "notes.md"), "kept: scratchpad/cited.\n", false);
  g(repo, "add", "-A"); g(repo, "commit", "-q", "-m", "init");
  const wt = join(repo, ".claude", "worktrees");
  g(repo, "worktree", "add", "-q", "-b", "landed-b", join(wt, "w1"), "main");
  file(join(wt, "w1", "a.txt"), "a", false);
  g(join(wt, "w1"), "add", "-A"); g(join(wt, "w1"), "commit", "-q", "-m", "a");
  g(repo, "merge", "-q", "--no-ff", "-m", "land", "landed-b");
  g(repo, "worktree", "add", "-q", "-b", "idle-b", join(wt, "w2"), "main");
  file(join(wt, "w2", "b.txt"), "b", false);
  g(join(wt, "w2"), "add", "-A");
  execFileSync("git", ["commit", "-q", "-m", "b"], { cwd: join(wt, "w2"), env: { ...env, GIT_COMMITTER_DATE: `${Math.floor(old)} +0000` } });
  file(join(wt, "w2", "node_modules", "pkg", "i.js"));
  file(join(wt, "w2", "lean", ".lake", "build", "o.olean"));
  g(repo, "worktree", "add", "-q", "-b", "fresh-b", join(wt, "w3"), "main");
  const scratch = join(t, "claude-1", "proj");
  const pad = join(scratch, "s1", "scratchpad");
  file(join(pad, "old", "f.txt"));
  file(join(pad, "cited", "f.txt"));
  file(join(pad, "fable-x", "f.txt"));
  file(join(pad, "busy", "f.txt"));
  file(join(pad, "young", "f.txt"), "y", false);
  file(join(pad, "loose.txt"));
  mkdirSync(join(t, "outside"));
  file(join(t, "outside", "keep.txt"), "keep", false);
  symlinkSync(join(t, "outside"), join(pad, "link"));
  const croot = join(repo, ".fw-console");
  file(join(croot, "tmp", "chromium-1", "x"));
  file(join(croot, "land-logs", "t-abc.log"));
  file(join(croot, "land-logs", "u-new.log"), "n", false);
  symlinkSync(join(t, "outside"), join(croot, "tmp", "escape"));
  lutimesSync(join(croot, "tmp", "escape"), old, old);
  const lake = join(t, "cache", "artifacts");
  file(join(lake, "a.olean"));
  const devices = join(t, "CoreSimulator", "Devices");
  file(join(devices, UDID, "device.plist"));
  const utmp = join(t, "var", "folders", "ab", "cdef", "T");
  file(join(utmp, "fw-a", "f.txt"));
  file(join(utmp, "instruments-1.ktrace", "f.txt"));
  file(join(utmp, "other-app", "f.txt"));
  file(join(utmp, "fw-young", "f.txt"), "y", false);
  file(join(utmp, "fw-ours.txt"));
  symlinkSync(join(t, "outside"), join(utmp, "fw-link"));
  lutimesSync(join(utmp, "fw-link"), old, old);
  const roots: Roots = { repo, lake, scratch, devices, utmp };
  const deleted: string[] = [];
  const io: Io = {
    opens: () => [join(pad, "busy", "f.txt"), "/elsewhere/x"],
    procs: () => [],
    lakeProcs: () => [],
    devices: () => [{ udid: UDID, name: "fw-old", state: "Shutdown" }, { udid: "1a1b2c3d-0000-1111-2222-333344445555", name: "iPhone", state: "Shutdown" }],
    deleteDevice: (u) => { deleted.push(u); rmSync(join(devices, u), { recursive: true }); return true; },
    lakeRoot: () => lake,
  };
  return { t, repo, wt, pad, croot, lake, devices, utmp, roots, io, deleted };
}

describe("fw disk-gc on a temp tree", () => {
  const call = fwcoreCall(root);
  const uid = process.getuid!();

  it("--list names exactly what each class allows", () => {
    const x = tree();
    const r = diskGc({ repo: x.repo, args: parseArgs(["--list"]), call, io: x.io, roots: x.roots, uid });
    const got = r.reply.items.map((i) => `${i.num} ${i.path.slice(x.t.length + 1)}`).sort();
    expect(got).toEqual([
      "1 cache/artifacts/a.olean",
      "2 repo/.claude/worktrees/w1",
      "3 repo/.claude/worktrees/w2/lean/.lake",
      "3 repo/.claude/worktrees/w2/node_modules",
      "4 claude-1/proj/s1/scratchpad/old",
      "5 CoreSimulator/Devices/" + UDID,
      "6 repo/.fw-console/land-logs/t-abc.log",
      "6 repo/.fw-console/tmp/chromium-1",
      "7 var/folders/ab/cdef/T/fw-a",
      "7 var/folders/ab/cdef/T/fw-ours.txt",
      "7 var/folders/ab/cdef/T/instruments-1.ktrace",
    ]);
    expect(r.reply.items.find((i) => i.cls === "landed")!.bytes).toBeGreaterThan(0);
    expect(r.lines).toHaveLength(r.reply.items.length);
    expect(existsSync(join(x.pad, "old"))).toBe(true);
  });

  it("a held Simulator lock, a queued land and the class filter each keep their candidates", () => {
    const x = tree();
    mkdirSync(join(x.repo, ".local", "locks", "sim"), { recursive: true });
    writeFileSync(join(x.croot, "land-queue.jsonl"), JSON.stringify({ ev: "enq", task: "t", branch: "landed-b", allow: [] }) + "\n");
    const r = diskGc({ repo: x.repo, args: parseArgs(["--list", "--class", "2,5,6"]), call, io: x.io, roots: x.roots, uid });
    expect(r.reply.items.map((i) => i.num).sort()).toEqual([6, 6]);
    expect(r.reply.classes.map((c) => c.num)).toEqual([2, 5, 6]);
  });

  it("--delete removes the list, keeps everything else, and records one event", () => {
    const x = tree();
    const r = diskGc({ repo: x.repo, args: parseArgs(["--delete"]), call, io: x.io, roots: x.roots, uid });
    expect(r.deleted).toBe(11);
    expect(r.failed).toBe(0);
    expect(r.freed.map((f) => f.num).sort()).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(r.lines.some((l) => l.startsWith("disk-gc: freed class 7 usertmp:"))).toBe(true);
    expect(lstatSync(join(x.croot, "tmp", "escape")).isSymbolicLink()).toBe(true);
    for (const d of ["other-app", "fw-young", "fw-link"]) expect(existsSync(join(x.utmp, d))).toBe(true);
    for (const d of ["fw-a", "fw-ours.txt", "instruments-1.ktrace"]) expect(existsSync(join(x.utmp, d))).toBe(false);
    expect(existsSync(x.utmp)).toBe(true);
    expect(existsSync(join(x.t, "outside", "keep.txt"))).toBe(true);
    expect(worktrees(x.repo)!.map((w) => w.path.slice(x.wt.length + 1))).not.toContain("w1");
    expect(g(x.repo, "branch", "--list", "landed-b").trim()).toContain("landed-b");
    expect(existsSync(join(x.wt, "w2", "b.txt"))).toBe(true);
    expect(existsSync(join(x.wt, "w2", "node_modules"))).toBe(false);
    expect(existsSync(join(x.wt, "w3"))).toBe(true);
    for (const d of ["cited", "fable-x", "busy", "young", "loose.txt", "link"]) expect(existsSync(join(x.pad, d))).toBe(true);
    expect(existsSync(join(x.pad, "old"))).toBe(false);
    expect(x.deleted).toEqual([UDID]);
    expect(existsSync(join(x.croot, "land-logs", "u-new.log"))).toBe(true);
    expect(existsSync(join(x.lake, "a.olean"))).toBe(false);
    const ev = readFileSync(join(x.croot, "disk-gc.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
    expect(ev).toHaveLength(1);
    expect(ev[0]).toMatchObject({ type: "diskgc.run", mode: "delete", deleted: 11, failed: 0 });
    expect(ev[0].classes).toHaveLength(7);
    expect(ev[0].freed.length).toBe(7);
  });

  it("no open-file table keeps every candidate the opens guard covers", () => {
    const x = tree();
    const r = diskGc({ repo: x.repo, args: parseArgs(["--list"]), call, io: { ...x.io, opens: () => null }, roots: x.roots, uid });
    expect(r.reply.items).toEqual([]);
  });

  it("the trigger is off with FW_DISK_GC=0 and reports a failure as one line", () => {
    const x = tree();
    expect(diskGcTick(x.repo, ["console"], call, { FW_DISK_GC: "0" }, { io: x.io, roots: x.roots })).toEqual([]);
    expect(existsSync(join(x.croot, "tmp", "chromium-1"))).toBe(true);
    const bad = diskGcTick(x.repo, ["console"], () => { throw new Error("no fwcore"); }, {}, { io: x.io, roots: x.roots });
    expect(bad).toEqual(["DISKGC error no fwcore"]);
    const ok = diskGcTick(x.repo, ["console"], call, {}, { io: x.io, roots: x.roots, uid: process.getuid!() });
    expect(ok).toEqual(["DISKGC classes 6: 6 console 2 (0.00 GiB); deleted 2, failed 0; freed 6 0.00 GiB"]);
  });

  it("a path of unknown owner is kept; the pressure floor and the owner marker lower the scratch age", () => {
    const x = tree();
    const hoursAgo = (p: string, h: number) => { const t = Date.now() / 1000 - h * 3600; utimesSync(p, t, t); };
    file(join(x.pad, "mid", "f.txt"), "m", false);
    hoursAgo(join(x.pad, "mid", "f.txt"), 3); hoursAgo(join(x.pad, "mid"), 3);
    file(join(x.pad, "owned", "f.txt"), "o", false);
    writeFileSync(join(x.pad, "owned", ".fw-owner"), JSON.stringify({ task: "t1", run: "wf_1" }));
    hoursAgo(join(x.pad, "owned", "f.txt"), 2); hoursAgo(join(x.pad, "owned", ".fw-owner"), 2); hoursAgo(join(x.pad, "owned"), 2);
    const num = (a: string[]) => diskGc({ repo: x.repo, args: parseArgs(a), call, io: x.io, roots: x.roots, uid }).reply.items.map((i) => i.path.slice(x.pad.length + 1)).sort();
    expect(ownerMarker(join(x.pad, "owned"))).toEqual({ task: "t1", run: "wf_1" });
    expect(ownerMarker(join(x.pad, "mid"))).toBeNull();
    expect(num(["--list", "--class", "4"])).toEqual(["old"]);
    expect(num(["--list", "--class", "4", "--pressure"])).toEqual(["old"]);
    const events = [
      { seq: 1, type: "agent.label", agent: "a1", name: "mid", key: "wfid-label:wf_9:a1" },
      { seq: 2, type: "agent.label", agent: "a2", name: "other", key: "wfid-label:wf_9:a2" },
    ].map((e) => JSON.stringify(e)).join("\n") + "\n";
    mkdirSync(x.croot, { recursive: true });
    writeFileSync(join(x.croot, "events.jsonl"), events);
    expect(gatherEventFacts(x.repo, call)!.liveAgents.sort()).toEqual(["mid", "other"]);
    expect(num(["--list", "--class", "4", "--pressure"])).toEqual(["old", "owned"]);
    writeFileSync(join(x.croot, "events.jsonl"), JSON.stringify({ seq: 2, type: "agent.label", agent: "a2", name: "other", key: "wfid-label:wf_9:a2" }) + "\n");
    expect(num(["--list", "--class", "4"])).toEqual(["old"]);
    expect(num(["--list", "--class", "4", "--pressure"])).toEqual(["mid", "old", "owned"]);
    writeFileSync(join(x.croot, "events.jsonl"), [
      { seq: 3, type: "task.done", task: "t1", key: "td:t1" },
      { seq: 4, type: "agent.stop", agent: "a3", key: "wfr-end:wf_1" },
    ].map((e) => JSON.stringify(e)).join("\n") + "\n");
    expect(gatherEventFacts(x.repo, call)).toEqual({ liveAgents: [], landedTasks: ["t1"], finishedRuns: ["wf_1"] });
    expect(num(["--list", "--class", "4"])).toEqual(["old", "owned"]);
  });

  it("gatherEventFacts is null without an event log", () => {
    const x = tree();
    expect(gatherEventFacts(x.repo, call)).toBeNull();
  });

  it("gatherEventFacts orders stop and resume by seq, and fails closed on a line without seq or a refusing fwcore", () => {
    const x = tree();
    mkdirSync(x.croot, { recursive: true });
    const log = (es: object[]) => writeFileSync(join(x.croot, "events.jsonl"), es.map((e) => JSON.stringify(e)).join("\n") + "\n");
    log([{ seq: 7, type: "agent.spawn", agent: "a" }, { seq: 1, type: "agent.stop", agent: "a" }, { seq: 2, type: "agent.label", agent: "a", name: "n" }]);
    expect(gatherEventFacts(x.repo, call)!.liveAgents).toEqual(["n"]);
    log([{ seq: 7, type: "agent.stop", agent: "a" }, { seq: 1, type: "agent.spawn", agent: "a" }, { seq: 2, type: "agent.label", agent: "a", name: "n" }]);
    expect(gatherEventFacts(x.repo, call)!.liveAgents).toEqual([]);
    log([{ type: "agent.stop", agent: "a" }]);
    expect(gatherEventFacts(x.repo, call)).toBeNull();
    log([{ seq: 1, type: "agent.stop", agent: "a" }]);
    expect(gatherEventFacts(x.repo, () => { throw new Error("no fwcore"); })).toBeNull();
  });
});

describe("isLink", () => {
  it("gives no fact when lstat fails, so the candidate carries no sym and is kept", () => {
    expect(isLink("/nonexistent/fw-disk-gc-missing")).toBeUndefined();
    expect(JSON.stringify({ sym: isLink("/nonexistent/fw-disk-gc-missing") })).toBe("{}");
  });
});
