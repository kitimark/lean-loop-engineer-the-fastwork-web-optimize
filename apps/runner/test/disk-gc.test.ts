import { execFileSync } from "node:child_process";
import { existsSync, lutimesSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { clsOf, diskGc, diskGcTick, DiskGcUsage, parseArgs, worktrees, type Io, type Roots } from "../src/disk-gc.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const cases = readFileSync(join(root, "packages", "contracts", "golden", "ops", "diskgc.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });

describe("ops.diskGc golden vectors replay through fwcore", () => {
  const call = fwcoreCall(root);
  it("covers both ops and every class", () => {
    expect(new Set(cases.map((c) => c.request.op))).toEqual(new Set(["ops.diskGc", "ops.diskGcPath"]));
    const listed = new Set(cases.flatMap((c) => ((c.response.items ?? []) as { num?: number }[]).map((i) => i.num)));
    expect([...listed].sort()).toEqual([1, 2, 3, 4, 5, 6]);
  });
  for (const c of cases) it(c.name, () => {
    if (typeof c.response.error === "string") expect(() => call(c.request)).toThrow(c.response.error);
    else expect(call(c.request)).toEqual(c.response);
  });
});

describe("arguments", () => {
  it("parses classes by number or name, deduplicated; default all", () => {
    expect(parseArgs([]).classes).toEqual(["lake", "landed", "idle", "scratch", "sim", "console"]);
    expect(parseArgs(["--delete", "--class", "1,landed", "--class", "6", "--class", "2"])).toEqual({ mode: "delete", classes: ["lake", "landed", "console"] });
    expect(parseArgs(["--list", "--idle-h", "48", "--keep-days", "3"])).toMatchObject({ mode: "list", idleH: 48, keepDays: 3 });
    expect(clsOf("7")).toBeNull();
    expect(() => parseArgs(["--class", "7"])).toThrow(DiskGcUsage);
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

/** A main checkout with a landed worktree, an unlanded idle one, a scratch root, console entries, a Lake artifacts dir
 *  and a devices dir, all under one temp directory. */
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
  const roots: Roots = { repo, lake, scratch, devices };
  const deleted: string[] = [];
  const io: Io = {
    opens: () => [join(pad, "busy", "f.txt"), "/elsewhere/x"],
    procs: () => [],
    lakeProcs: () => [],
    devices: () => [{ udid: UDID, name: "fw-old", state: "Shutdown" }, { udid: "1a1b2c3d-0000-1111-2222-333344445555", name: "iPhone", state: "Shutdown" }],
    deleteDevice: (u) => { deleted.push(u); rmSync(join(devices, u), { recursive: true }); return true; },
    lakeRoot: () => lake,
  };
  return { t, repo, wt, pad, croot, lake, devices, roots, io, deleted };
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
      "6 repo/.fw-console/tmp/escape",
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
    expect(r.reply.items.map((i) => i.num).sort()).toEqual([6, 6, 6]);
    expect(r.reply.classes.map((c) => c.num)).toEqual([2, 5, 6]);
  });

  it("--delete removes the list, keeps everything else, and records one event", () => {
    const x = tree();
    const r = diskGc({ repo: x.repo, args: parseArgs(["--delete"]), call, io: x.io, roots: x.roots, uid });
    expect(r.deleted).toBe(8);
    expect(r.failed).toBe(1);
    expect(r.lines.some((l) => l.includes("tmp/escape: path resolves elsewhere"))).toBe(true);
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
    expect(ev[0]).toMatchObject({ type: "diskgc.run", mode: "delete", deleted: 8, failed: 1 });
    expect(ev[0].classes).toHaveLength(6);
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
    expect(ok).toEqual(["DISKGC classes 6: 6 console 3 (0.00 GiB); deleted 2, failed 1"]);
  });
});
