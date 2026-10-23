// obs.slow subjects keyed on work (golden/obs/timing-slow.jsonl, Fw.Wire.Obs.TimingSlow) and the checks member of the
// `fw polish commit` span (polish.ts stagedChecks).
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { slowAlerts } from "../src/next.ts";
import { polishSpanExtra, stagedChecks } from "../src/polish.ts";
import { parseSamples } from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");
type Case = { name: string; request: { op: string; params: unknown; samples: Record<string, unknown>[] }; response: { slow: string[] } };
const golden = readFileSync(join(root, "packages/contracts/golden/obs/timing-slow.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Case);
const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

describe.skipIf(!existsSync(fwcore))("obs.slow against Fw.Wire.Obs.TimingSlow (golden/obs/timing-slow.jsonl)", () => {
  const input = golden.map((g, i) => JSON.stringify({ id: i, ...g.request })).join("\n") + "\n";
  const r = spawnSync(fwcore, [], { input, encoding: "utf8", timeout: 120_000, maxBuffer: 64 << 20 });
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
  it.skipIf(!existsSync(fwcore))("with fwcore: a staged Lean module runs lake build", async () => {
    const call = async (req: Record<string, unknown>) => {
      const r = spawnSync(fwcore, [], { input: JSON.stringify({ id: 1, ...req }) + "\n", encoding: "utf8" });
      return JSON.parse(r.stdout.split("\n")[0]!) as Record<string, unknown>;
    };
    expect((await stagedChecks(dir, git, call))?.kinds).toContain("lakeBuild");
  });
  it("adds no checks member to a span line before a commit", () => expect(polishSpanExtra()).toEqual({}));
});
