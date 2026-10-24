// obs.slow subjects keyed on work (golden/obs/timing-slow.jsonl, Fw.Wire.Obs.TimingSlow) and the checks member of the
// `fw polish commit` span (polish.ts stagedChecks).
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { slowAlerts } from "../src/next.ts";
import { NO_CHECKS, polishCli, realRun, stagedChecks, stagedSpan } from "../src/polish.ts";
import { begin, noteSpan, spanWork } from "../src/timing.ts";
import { parseSamples } from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");
type Case = { name: string; request: { op: string; params: unknown; samples: Record<string, unknown>[] }; response: { slow: string[] } };
const golden = readFileSync(join(root, "packages/contracts/golden/obs/timing-slow.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Case);
const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

describe.skipIf(!existsSync(fwcore))("obs.slow against Fw.Wire.Obs.TimingSlow (golden/obs/timing-slow.jsonl)", () => {
  const input = golden.map((g, i) => JSON.stringify({ id: i, ...g.request })).join("\n") + "\n";
  const r = spawnSync(fwcore, [], { input, encoding: "utf8", maxBuffer: 64 << 20 });
  const byId = new Map((r.stdout ?? "").split("\n").filter(Boolean).map((l) => { const m = JSON.parse(l) as { id: number; slow: string[] }; return [m.id, m.slow]; }));
  it("has a work-keyed subject, a bare one and an overflow bucket with no alert", () => {
    const all = golden.flatMap((g) => g.response.slow);
    expect(all).toContain("fw/polish commit [checks=lakeBuild]");
    expect(all).toContain("fw/polish commit");
    expect(golden.some((g) => g.request.samples.every((s) => s.step === "slot run check") && g.response.slow.length === 0)).toBe(true);
  });
  golden.forEach((g, i) => {
    it(`replays: ${g.name.slice(0, 70)}`, () => expect(byId.get(i)).toEqual(g.response.slow));
  });
  it("the subject is the alert subject: one timing.slow per subject", () => {
    expect(slowAlerts(["fw/polish commit [checks=lakeBuild]"])).toMatchObject([{ code: "timing.slow", subject: "fw/polish commit [checks=lakeBuild]" }]);
  });
  it("span lines with a checks member reach fwcore as the golden samples' work", () => {
    const g = golden.find((x) => x.response.slow.includes("fw/polish commit [checks=lakeBuild]"))!;
    const kindsOf: Record<string, string[]> = { light: ["nodeCheck"], lakeBuild: ["lakeBuild", "shParse"] };
    const lines = g.request.samples.map((s, i) => {
      const c = (s.work as Record<string, string> | undefined)?.checks;
      const kinds = c === undefined ? undefined : (kindsOf[c] ?? c.split("+"));
      return JSON.stringify({ tool: s.tool, step: s.step, startMs: i, durMs: s.durMs, exit: s.exit, host: s.host, load: s.load, ...(kinds ? { checks: { n: kinds.length, kinds } } : {}) });
    });
    expect(parseSamples(lines.join("\n")).map((s) => s.work)).toEqual(g.request.samples.map((s) => s.work));
  });
});

describe("stagedChecks: the checks of the staged files, asked of ops.checkMap", () => {
  const dir = mkdtempSync(join(tmpdir(), "fw-staged-checks-")); dirs.push(dir);
  const g = (...a: string[]) => execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", ...a], { cwd: dir, encoding: "utf8" });
  const git = (cwd: string, args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8" });
  g("init", "-q", "-b", "main");
  writeFileSync(join(dir, "gone.sh"), "true\n");
  g("add", "."); g("commit", "-q", "-m", "base");
  writeFileSync(join(dir, "a.lean"), "def x := 1\n");
  writeFileSync(join(dir, "b.sh"), "true\n");
  g("add", "a.lean", "b.sh"); g("rm", "-q", "gone.sh");
  it("sends the added paths and the deletions; counts the commands and sorts their kinds", async () => {
    const seen: Record<string, unknown>[] = [];
    const call = async (req: Record<string, unknown>) => {
      seen.push(req);
      return { cmds: [{ check: "shParse" }, { check: "lakeBuild" }, { check: "shParse" }] };
    };
    expect(await stagedChecks(dir, git, call)).toEqual({ n: 3, kinds: ["lakeBuild", "shParse"] });
    expect(seen).toEqual([{ op: "ops.checkMap", paths: ["a.lean", "b.sh"], deleted: ["gone.sh"] }]);
  });
  it("gives null when fwcore fails or answers without a command list", async () => {
    expect(await stagedChecks(dir, git, async () => { throw new Error("no fwcore"); })).toBeNull();
    expect(await stagedChecks(dir, git, async () => ({ error: "x" }))).toBeNull();
  });
  it("stagedSpan runs the lake build command in its cwd and counts the modules it built", async () => {
    const ran: [string, string[]][] = [];
    const run = (cwd: string, argv: string[]) => { ran.push([cwd, argv]); return "✔ [1/3] Built Fw.A (1s)\n✔ [2/3] Built fwcore:exe (1s)\n✔ [3/3] Built Fw.B (2s)\n"; };
    const call = async () => ({ cmds: [{ check: "shParse", cwd: ".", argv: ["sh", "-n"] }, { check: "lakeBuild", cwd: "lean", argv: ["lake", "build"] }] });
    expect(await stagedSpan(dir, git, call, run)).toEqual({ checks: { n: 2, kinds: ["lakeBuild", "shParse"] }, lake: { built: 2 } });
    expect(ran).toEqual([[join(dir, "lean"), ["lake", "build"]]]);
  });
  it("stagedSpan runs nothing and records no lake member without a lake build command", async () => {
    const run = () => { throw new Error("ran"); };
    expect(await stagedSpan(dir, git, async () => ({ cmds: [{ check: "shParse", cwd: ".", argv: ["sh", "-n"] }] }), run))
      .toEqual({ checks: { n: 1, kinds: ["shParse"] } });
    expect(await stagedSpan(dir, git, async () => ({ error: "x" }), run)).toBeNull();
  });
  it("stagedSpan records no lake member when the build run did not exit 0 (a failed build made only some modules)", async () => {
    const call = async () => ({ cmds: [{ check: "lakeBuild", cwd: "lean", argv: ["lake", "build"] }] });
    expect(await stagedSpan(dir, git, call, () => null)).toEqual({ checks: { n: 1, kinds: ["lakeBuild"] } });
    expect(await stagedSpan(dir, git, call, () => "✔ [1/3] Built Fw.A (1s)\n")).toEqual({ checks: { n: 1, kinds: ["lakeBuild"] }, lake: { built: 1 } });
  });
  it("realRun gives the output of a command that exits 0 and null for one that fails, however much it printed", () => {
    expect(realRun(dir, ["sh", "-c", "echo '[1/2] Built Fw.A (1s)'"])).toBe("[1/2] Built Fw.A (1s)\n");
    expect(realRun(dir, ["sh", "-c", "echo '[1/2] Built Fw.A (1s)'; exit 1"])).toBeNull();
    expect(realRun(dir, ["fw-no-such-command-x"])).toBeNull();
  });
  it.skipIf(!existsSync(fwcore))("with fwcore: a staged Lean module runs lake build", async () => {
    const call = async (req: Record<string, unknown>) => {
      const r = spawnSync(fwcore, [], { input: JSON.stringify({ id: 1, ...req }) + "\n", encoding: "utf8" });
      return JSON.parse(r.stdout.split("\n")[0]!) as Record<string, unknown>;
    };
    expect((await stagedChecks(dir, git, call))?.kinds).toContain("lakeBuild");
  });
});

describe("a polish commit that keeps nothing", () => {
  it("is keyed checks=light, so Lean judges it against the light commits, not as an unkeyed span", () => {
    expect(spanWork({ checks: NO_CHECKS })).toEqual({ work: { checks: "light" } });
  });
  it("polishCli writes checks {n:0,kinds:[]} on its `fw`/`polish commit` line", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-polish-nothing-")); dirs.push(dir);
    const file = join(dir, "timings.jsonl");
    const git = (_cwd: string, raw: string[]) => {
      const args = raw[0] === "-c" ? raw.slice(2) : raw;
      if (args[0] === "rev-parse") return args.includes("--absolute-git-dir") ? "/wt/.git\n" : "/wt\n";
      return "";
    };
    const answers: Record<string, Record<string, unknown>> = {
      "plan.polishPlan": { classes: [], keep: [], restore: [] },
      "plan.polishHunks": { ranges: [], blocked: [], edits: [] },
      "plan.polishSettle": { restore: [], remove: [] },
    };
    const seeded: Record<string, string> = { "/wt/.git/fw-polish-untracked": "", "/wt/.git/fw-polish-dirty": "" };
    const log: string[] = [];
    const deps = { core: async (q: Record<string, unknown>) => answers[String(q.op)] ?? { error: String(q.op) }, log: (l: string) => log.push(l), git,
      read: (p: string) => seeded[p] ?? null, write: () => {}, remove: () => {}, gen: async () => [], worktree: () => "/wt" };
    const prev = process.env.FW_TIMINGS_FILE;
    process.env.FW_TIMINGS_FILE = file;
    try {
      const end = begin("fw", "polish commit", dir);
      end(await polishCli(["commit", "--branch", "b", "--task", "t"], "/root", deps));
    } finally {
      if (prev === undefined) delete process.env.FW_TIMINGS_FILE; else process.env.FW_TIMINGS_FILE = prev;
    }
    expect(log.at(-1)).toBe("VERDICT polish-commit t nothing");
    const [line] = readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l) as Record<string, unknown>);
    expect([line!.step, line!.exit, line!.checks]).toEqual(["polish commit", 0, { n: 0, kinds: [] }]);
  });
});

describe("noteSpan: the checks member reaches the line of its own span only", () => {
  it("merges the note into the `fw`/`polish commit` line and into no other", () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-note-span-")); dirs.push(dir);
    const file = join(dir, "timings.jsonl");
    const prev = process.env.FW_TIMINGS_FILE;
    process.env.FW_TIMINGS_FILE = file;
    try {
      const commit = begin("fw", "polish commit", dir), other = begin("fw", "polish check", dir);
      noteSpan("fw", "polish commit", { checks: { n: 2, kinds: ["lakeBuild", "shParse"] }, lake: { built: 24 } });
      commit(0); other(0);
    } finally {
      if (prev === undefined) delete process.env.FW_TIMINGS_FILE; else process.env.FW_TIMINGS_FILE = prev;
    }
    const text = readFileSync(file, "utf8");
    const lines = text.trim().split("\n").map((l) => JSON.parse(l) as Record<string, unknown>);
    expect(lines.map((l) => [l.step, l.checks, l.lake])).toEqual([["polish commit", { n: 2, kinds: ["lakeBuild", "shParse"] }, { built: 24 }], ["polish check", undefined, undefined]]);
    expect(parseSamples(text).map((s) => s.work)).toEqual([{ checks: "lakeBuild", mods: "16" }, undefined]);
  });
});
