// fw reap --stop on real throwaway process trees (task reap-auto-stop): a temp repo laid out like this one
// (<main>/.claude/worktrees/<id>), node processes started with their cwd in a removed worktree, in a live one and in the
// main checkout. One child ends on TERM, one ignores TERM. No test is skipped by platform: `ps` (stat, lstart) and the cwd
// read (/proc on Linux, lsof on macOS) are the same code on both.
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { type Facts, gather, type Io, type Target, realIo, reapCli, reapStopLines, stopSelected } from "../src/reap.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const GRACE_MS = (call({ op: "ops.reapPlan", rows: [], live: [] }) as { graceMs: number }).graceMs;

let tmp = "";
let main = "";
const started: number[] = []; // pgids and pids this test run started: the only ones it ever signals
const git = (cwd: string, ...a: string[]) => execFileSync("git", a, { cwd, encoding: "utf8", env: { ...process.env, GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" } });

beforeAll(() => {
  tmp = realpathSync(mkdtempSync(join(tmpdir(), "reap-stop-")));
  main = join(tmp, "main");
  mkdirSync(main);
  git(main, "init", "-q", "-b", "main");
  writeFileSync(join(main, "f"), "x");
  git(main, "add", "f");
  git(main, "commit", "-qm", "init");
  mkdirSync(join(main, ".claude", "worktrees"), { recursive: true });
  git(main, "worktree", "add", "-q", join(main, ".claude", "worktrees", "live1"), "-b", "live1");
  mkdirSync(join(main, ".claude", "worktrees", "gone1")); // a worktree directory git does not know and with no .git: removed
});
afterEach(() => { for (const p of started.splice(0)) { for (const t of [-p, p]) { try { process.kill(t, "SIGKILL"); } catch { /* gone */ } } } });
afterAll(() => { rmSync(tmp, { recursive: true, force: true }); });

/** The parent script: starts one child per mode (`term` ends on TERM, `ignore` ignores it) with cwd `kidCwd`, prints their pids. */
const PARENT = `
const { spawn } = require("node:child_process");
const modes = JSON.parse(process.argv[1]); const kidCwd = process.argv[2] || process.cwd();
const body = (m) => (m === "ignore" ? 'process.on("SIGTERM", () => {});' : "") + 'console.log("r"); setInterval(() => {}, 1000);';
const kids = modes.map((m) => spawn(process.execPath, ["-e", body(m)], { stdio: ["ignore", "pipe", "inherit"], cwd: kidCwd }));
let n = 0;
for (const k of kids) k.stdout.once("data", () => { if (++n === kids.length) console.log(JSON.stringify(kids.map((x) => x.pid))); });
setInterval(() => {}, 1000);
`;

type Tree = { parent: number; kids: number[] };

/** Start a tree: a group leader parent in `cwd` with one child per mode (cwd `kidCwd` or the parent's). Resolves when ready. */
function startTree(cwd: string, modes: ("term" | "ignore")[], kidCwd = ""): Promise<Tree> {
  return new Promise((resolve, reject) => {
    const c = spawn(process.execPath, ["-e", PARENT, JSON.stringify(modes), kidCwd], { cwd, detached: true, stdio: ["ignore", "pipe", "inherit"] });
    started.push(c.pid!);
    let buf = "";
    c.stdout.on("data", (d: Buffer) => {
      buf += d.toString();
      const line = buf.split("\n").find((l) => l.startsWith("["));
      if (line) resolve({ parent: c.pid!, kids: JSON.parse(line) as number[] });
    });
    c.once("error", reject);
    c.once("exit", () => reject(new Error("tree parent exited early")));
  });
}

/** Whether the pid runs (a zombie, already dead, does not). */
function running(pid: number): boolean {
  const s = spawnSync("ps", ["-o", "stat=", "-p", String(pid)], { encoding: "utf8" }).stdout.trim();
  return s !== "" && !s.startsWith("Z");
}

/** The pids this run started and everything below them: the only rows the tests let Lean see, so a real leftover process of
 *  the machine (selected against this temp repo) is never signalled by a test. */
function mine(): Set<number> {
  const rows = realIo.table() ?? [];
  const s = new Set<number>(started);
  for (let grew = true; grew;) { grew = false; for (const r of rows) if (s.has(r.ppid) && !s.has(r.pid)) { s.add(r.pid); grew = true; } }
  return s;
}
let snapshot = new Set<number>(); // the pids of the trees at the time Lean read the table (a child orphaned by TERM stays in it)
const scoped = (top: string): Facts | null => { const f = gather(top); if (f === null) return null; const m = snapshot = mine(); return { ...f, rows: f.rows.filter((r) => m.has(r.pid)), mcps: [] }; };

const recording = (log: { pid: number; sig: string; group: boolean }[], over: Partial<Io> = {}): Io =>
  ({ ...realIo, signal: (t: Target, sig) => { if (!snapshot.has(t.pid)) throw new Error(`test would signal pid ${t.pid}, which it did not start`); log.push({ pid: t.pid, sig, group: t.group }); realIo.signal(t, sig); }, ...over });

describe("fw reap --stop on real process trees", () => {
  it("TERM path: a tree in a removed worktree whose members end on TERM is stopped without KILL", async () => {
    const t = await startTree(join(main, ".claude", "worktrees", "gone1"), ["term", "term"]);
    const log: { pid: number; sig: string; group: boolean }[] = [];
    const r = stopSelected(main, call, recording(log), scoped)!;
    const all = [t.parent, ...t.kids];
    expect(r.selected.map((s) => s.pid).sort()).toEqual([...all].sort());
    expect(r.termed.length).toBe(3);
    expect(r.killed).toEqual([]);
    expect(r.left).toEqual([]);
    expect(log.every((l) => l.sig === "SIGTERM")).toBe(true);
    expect(log.some((l) => l.group && l.pid === t.parent)).toBe(true); // every row of the group is selected: one group signal
    for (const p of all) expect(running(p)).toBe(false);
    expect(r.byKind[0]!.kind).toBe("removed");
    expect(r.freedKb).toBeGreaterThan(0);
  });

  it("KILL path: a child that ignores TERM is killed only after the grace", async () => {
    const t = await startTree(join(main, ".claude", "worktrees", "gone1"), ["term", "ignore"]);
    const log: { pid: number; sig: string; group: boolean }[] = [];
    const t0 = Date.now();
    const r = stopSelected(main, call, recording(log), scoped)!;
    const elapsed = Date.now() - t0;
    const ignorer = t.kids[1]!;
    expect(r.killed.some((k) => k.pid === ignorer || (k.group && k.pid === t.parent))).toBe(true);
    expect(r.killed.every((k) => k.pid !== t.kids[0])).toBe(true); // the TERM-respecting child is gone before the KILL read
    expect(r.left).toEqual([]);
    expect(running(ignorer)).toBe(false);
    expect(elapsed).toBeGreaterThanOrEqual(GRACE_MS - 200);
    const firstKill = log.findIndex((l) => l.sig === "SIGKILL");
    expect(firstKill).toBeGreaterThan(0);
    expect(log.slice(0, firstKill).every((l) => l.sig === "SIGTERM")).toBe(true);
  });

  it("pid-reuse guard: a pid whose start time changed after TERM is never sent KILL", async () => {
    const t = await startTree(join(main, ".claude", "worktrees", "gone1"), ["ignore"]);
    const victim = t.kids[0]!;
    const log: { pid: number; sig: string; group: boolean }[] = [];
    // the table says `victim` is now another process (same pid, later start), as after a pid reuse
    const io = recording(log, { table: () => realIo.table()!.map((r) => (r.pid === victim ? { ...r, start: r.start + 100 } : r)) });
    const r = stopSelected(main, call, io, scoped)!;
    expect(log.some((l) => l.sig === "SIGKILL")).toBe(false);
    expect(r.killed).toEqual([]);
    expect(running(victim)).toBe(true); // still the real process, which we did not touch after TERM
    expect(r.left.some((l) => l.pid === victim)).toBe(false);
  });

  it("a process in a live checkout, in the main checkout or outside any worktree is never touched", async () => {
    const live = await startTree(join(main, ".claude", "worktrees", "live1"), ["ignore"]);
    const inMain = await startTree(main, ["ignore"]);
    const outside = await startTree(tmp, ["ignore"]);
    const gone = await startTree(join(main, ".claude", "worktrees", "gone1"), ["term"]);
    const log: { pid: number; sig: string; group: boolean }[] = [];
    const r = stopSelected(main, call, recording(log), scoped)!;
    const safe = [live, inMain, outside].flatMap((x) => [x.parent, ...x.kids]);
    expect(r.selected.map((s) => s.pid).sort()).toEqual([gone.parent, ...gone.kids].sort());
    expect(log.every((l) => !safe.includes(l.pid))).toBe(true);
    for (const p of safe) expect(running(p)).toBe(true);
    for (const p of [gone.parent, ...gone.kids]) expect(running(p)).toBe(false);
  });

  it("a tool below a dead owner is stopped even when its own cwd is outside every worktree; a look-alike is not", async () => {
    const t = await startTree(join(main, ".claude", "worktrees", "gone1"), ["term"], tmp);
    const lookalike = await startTree(tmp, ["term"]);
    const r = stopSelected(main, call, recording([]), scoped)!;
    const kinds = Object.fromEntries(r.selected.map((s) => [s.pid, s.kind]));
    expect(kinds[t.parent]).toBe("removed");
    expect(kinds[t.kids[0]!]).toBe("descendant");
    expect(running(t.kids[0]!)).toBe(false);
    for (const p of [lookalike.parent, ...lookalike.kids]) { expect(kinds[p]).toBeUndefined(); expect(running(p)).toBe(true); }
  });

  it("a worktree removed with git while a tree runs in it is stopped by the land hook, which reports and records it", async () => {
    const wt = join(main, ".claude", "worktrees", "landed1");
    git(main, "worktree", "add", "-q", wt, "-b", "landed1");
    const t = await startTree(wt, ["term"]);
    git(main, "worktree", "remove", "--force", wt);
    process.env.FW_CONSOLE_DIR = join(tmp, "console");
    const lines = reapStopLines(main, call, recording([]), scoped);
    delete process.env.FW_CONSOLE_DIR;
    expect(lines[0]).toMatch(/^leftover processes stopped: 2 of 2/);
    for (const p of [t.parent, ...t.kids]) expect(running(p)).toBe(false);
    const rec = readFileSync(join(tmp, "console", "reap.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as { type: string; kind: string; pids: number[]; freedKb: number });
    expect(rec[0]).toMatchObject({ type: "reap.stopped", kind: "removed" });
    expect(rec[0]!.pids.sort()).toEqual([t.parent, ...t.kids].sort());
  });

  it("--stop prints the list and the result; --list alone signals nothing", async () => {
    const t = await startTree(join(main, ".claude", "worktrees", "gone1"), ["term"]);
    const out: string[] = [];
    expect(reapCli(["--list"], main, call, (s) => out.push(s), scoped)).toBe(0);
    expect(out.length).toBe(2);
    expect(running(t.parent)).toBe(true);
    out.length = 0;
    process.env.FW_CONSOLE_DIR = join(tmp, "console2");
    expect(reapCli(["--stop"], main, call, (s) => out.push(s), scoped, recording([]))).toBe(0);
    delete process.env.FW_CONSOLE_DIR;
    expect(out.some((l) => l.startsWith("stopped removed: 2 process(es)"))).toBe(true);
    expect(running(t.parent)).toBe(false);
    out.length = 0;
    expect(reapCli(["--stop"], main, call, (s) => out.push(s), scoped, recording([]))).toBe(0);
    expect(out).toEqual(["reap: nothing leftover"]);
  });
});
