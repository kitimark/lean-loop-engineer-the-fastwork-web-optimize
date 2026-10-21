// fw plan overlap: golden vectors of fwcore `plan.overlap` (Fw.Plan.Overlap) and the CLI around it. The golden
// responses come from the fwcore binary; regenerate with
//   FW_WRITE_OVERLAP_GOLDEN=1 pnpm --filter ./apps/runner exec vitest run test/plan-overlap.test.ts
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { overlapCli, overrideCommands, runningOf, type OverlapReply } from "../src/plan-overlap.ts";
import { Command } from "@fw/contracts";
import { coreCandidates, coreCaller } from "../src/watch.ts";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Store } from "../../console-api/src/store.ts";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../../..");
const goldenFile = join(root, "packages/contracts/golden/plan/overlap.jsonl");
const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: root, encoding: "utf8" }).trim();
const bins = coreCandidates(root, join(common, "..")).filter((b) => {
  try { return execFileSync(b, ["--ops"], { encoding: "utf8" }).includes("plan.overlap"); } catch { return false; }
});
const bin = bins[0];

const morph = "apps/site/src/parts/morph.tween/**";
const rows = [
  { id: "waapi-nav-width-tail", writes: ["lean/Fw/Parts/MorphTweenOpt.lean", morph] },
  { id: "morph-scroll-lock", writes: ["lean/Fw/Parts/MorphTweenOpt.lean", morph, "docs/team/handoffs/morph-scroll-lock.md"] },
  { id: "spawn-write-overlap", writes: ["lean/Fw/Plan/Overlap.lean", "apps/runner/src/plan-overlap*.ts", "!apps/runner/src/plan-overlap-x.ts"] },
  { id: "file-only", writes: ["apps/site/src/parts/morph.tween/a/b.ts"] },
  { id: "glob-a", writes: ["apps/site/src/**/morph.tween/*.ts"] },
  { id: "glob-b", writes: ["apps/site/src/parts/**"] },
  { id: "dir-only", writes: ["lean/Fw/Plan"] },
  { id: "docs", writes: ["docs/**"] },
  { id: "no-writes", writes: [] },
];
const req = (running: string[], candidate: string | null, override: string | null = null) =>
  ({ op: "plan.overlap", rows, running, candidate, override });
const cases: [string, Record<string, unknown>][] = [
  ["MorphTweenOpt pair: the file and the morph.tween glob both overlap: refused", req(["waapi-nav-width-tail"], "morph-scroll-lock")],
  ["MorphTweenOpt pair, reversed roles: refused", req(["morph-scroll-lock"], "waapi-nav-width-tail")],
  ["MorphTweenOpt pair with a reason: overridden", req(["waapi-nav-width-tail"], "morph-scroll-lock", "they edit different functions")],
  ["MorphTweenOpt pair with a blank reason: refused", req(["waapi-nav-width-tail"], "morph-scroll-lock", "   ")],
  ["disjoint tasks: clear", req(["waapi-nav-width-tail"], "spawn-write-overlap")],
  ["disjoint, a `!` exclude is not read: clear", req(["docs"], "spawn-write-overlap")],
  ["glob vs file: refused", req(["file-only"], "waapi-nav-width-tail")],
  ["glob vs glob: refused", req(["glob-a"], "glob-b")],
  ["directory vs file below it: refused", req(["dir-only"], "spawn-write-overlap")],
  ["a task without writes overlaps nothing: clear", req(["no-writes"], "waapi-nav-width-tail")],
  ["the candidate itself among the running is skipped: clear", req(["spawn-write-overlap"], "spawn-write-overlap")],
  ["unknown candidate: unknown", req(["docs"], "typo-task")],
  ["unknown running id: unknown", req(["typo-task"], "docs")],
  ["unknown id with a reason is still unknown", req(["typo-task"], "docs", "because")],
  ["no candidate: every running pair, the MorphTweenOpt pair is found", req(["waapi-nav-width-tail", "docs", "morph-scroll-lock"], null)],
  ["no candidate, disjoint running: clear", req(["docs", "spawn-write-overlap"], null)],
  ["nothing running: clear", req([], "morph-scroll-lock")],
];

function fwcore(reqs: Record<string, unknown>[]): Record<string, unknown>[] {
  const out = spawnSync(bin!, [], { input: reqs.map((r) => JSON.stringify(r)).join("\n") + "\n", encoding: "utf8", env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" } });
  return out.stdout.trim().split("\n").map((l) => { const { id: _, ...rest } = JSON.parse(l); return rest; });
}
const stored = () => readFileSync(goldenFile, "utf8").trim().split("\n").map((l) => JSON.parse(l)) as { name: string; request: unknown; response: OverlapReply }[];
const verdictOf = (name: string) => stored().find((l) => l.name.startsWith(name))!.response;

describe("plan.overlap golden (packages/contracts/golden/plan/overlap.jsonl)", () => {
  it("fwcore with plan.overlap is built (cd lean && lake build)", () => expect(bin).toBeTruthy());

  it("the file holds exactly the cases above, and fwcore gives every stored response", () => {
    const reqs = cases.map(([, r]) => JSON.parse(JSON.stringify(r)) as Record<string, unknown>);
    const got = fwcore(reqs);
    if (process.env.FW_WRITE_OVERLAP_GOLDEN) {
      writeFileSync(goldenFile, cases.map(([name], i) => JSON.stringify({ name, request: reqs[i], response: got[i] })).join("\n") + "\n");
    }
    expect(stored().map((l) => l.name)).toEqual(cases.map(([n]) => n));
    expect(stored().map((l) => l.request)).toEqual(reqs);
    expect(got).toEqual(stored().map((l) => l.response));
  });

  it("the MorphTweenOpt pair is caught on the file and on the glob, in both roles", () => {
    for (const n of ["MorphTweenOpt pair: the file", "MorphTweenOpt pair, reversed"]) {
      const r = verdictOf(n);
      expect(r.verdict).toBe("refused");
      expect(r.conflicts.map((c) => c.ga).sort()).toEqual(["apps/site/src/parts/morph.tween/**", "lean/Fw/Parts/MorphTweenOpt.lean"]);
    }
  });

  it("disjoint tasks pass; glob vs file and glob vs glob are caught", () => {
    expect(verdictOf("disjoint tasks").verdict).toBe("clear");
    expect(verdictOf("disjoint, a `!`").verdict).toBe("clear");
    expect(verdictOf("glob vs file")).toMatchObject({ verdict: "refused", conflicts: [{ ga: morph, gb: "apps/site/src/parts/morph.tween/a/b.ts" }] });
    expect(verdictOf("glob vs glob")).toMatchObject({ verdict: "refused", conflicts: [{ ga: "apps/site/src/parts/**", gb: "apps/site/src/**/morph.tween/*.ts" }] });
  });

  it("an override needs a non-blank reason, and an unknown id is never overridden", () => {
    expect(verdictOf("MorphTweenOpt pair with a reason").verdict).toBe("overridden");
    expect(verdictOf("MorphTweenOpt pair with a blank").verdict).toBe("refused");
    expect(verdictOf("unknown id with a reason").verdict).toBe("unknown");
    expect(verdictOf("unknown candidate").unknown).toEqual(["typo-task"]);
  });
});

describe("fw plan overlap (CLI)", () => {
  const core = coreCaller(bins);
  const lines: string[] = [];
  const run = (args: string[], recorded: Command[][] = [], ok = true) =>
    overlapCli(args, root, { core, board: async () => [], log: (l) => lines.push(l), record: async (c) => { recorded.push(c); return ok; } });

  it("the real work graph: morph-scroll-lock over a running waapi-nav-width-tail is refused (exit 1)", async () => {
    expect(await run(["morph-scroll-lock", "--running", "waapi-nav-width-tail"])).toBe(1);
    expect(lines.join("\n")).toContain("lean/Fw/Parts/MorphTweenOpt.lean");
  });

  it("the real work graph: this task against waapi-nav-width-tail is clear (exit 0)", async () => {
    expect(await run(["spawn-write-overlap", "--running", "waapi-nav-width-tail"])).toBe(0);
  });

  it("running tasks come from the board: a live agent without evidence", async () => {
    expect(runningOf([{ id: "a", agent: "x", evidence: null }, { id: "b", agent: null }, { id: "c", agent: "y", evidence: "abc" }, { id: "d" }])).toEqual(["a"]);
    const code = await overlapCli(["morph-scroll-lock"], root, { core, board: async () => [{ id: "waapi-nav-width-tail", agent: "w" }], log: (l) => lines.push(l) });
    expect(code).toBe(1);
  });

  it("an override with a reason is recorded as a closed step and exits 0", async () => {
    const rec: Command[][] = [];
    expect(await run(["morph-scroll-lock", "--running", "waapi-nav-width-tail", "--override", "different functions"], rec)).toBe(0);
    expect(rec).toHaveLength(1);
    const [post, done] = rec[0]!.map((c) => Command.parse(c));
    expect(post).toMatchObject({ type: "step.post", audience: "lead", card: null });
    expect(done).toMatchObject({ type: "step.done", note: "different functions" });
    expect((post as { title: string }).title).toContain("morph-scroll-lock over waapi-nav-width-tail");
  });

  it("the recorded override passes the real reducer: the step is posted and closed (inc: actor lead may not cause step.done)", async () => {
    const store = await Store.open(join(mkdtempSync(join(tmpdir(), "fw-overlap-")), ".fw-console"), selectCore(), () => 1_700_000_000_000);
    try {
      const rec: Command[][] = [];
      expect(await run(["morph-scroll-lock", "--running", "waapi-nav-width-tail", "--override", "real reducer"], rec)).toBe(0);
      const replies = [];
      for (const c of rec[0]!) replies.push(await store.submit(Command.parse(c)));
      expect(replies.map((r) => r.ok)).toEqual([true, true]);
    } finally { store.close(); }
  });

  it("an override the event log did not accept is not a start (exit 2)", async () => {
    expect(await run(["morph-scroll-lock", "--running", "waapi-nav-width-tail", "--override", "r"], [], false)).toBe(2);
  });

  it("an unknown task id exits 2 and a blank reason is still refused", async () => {
    expect(await run(["nope", "--running", "waapi-nav-width-tail"])).toBe(2);
    expect(await run(["morph-scroll-lock", "--running", "waapi-nav-width-tail", "--override", " "])).toBe(1);
  });

  it("override commands are idempotent for the same pairs and reason", () => {
    const r: OverlapReply = { verdict: "overridden", unknown: [], conflicts: [{ a: "x", b: "y", ga: "g", gb: "g" }] };
    expect(overrideCommands("x", "why", r)).toEqual(overrideCommands("x", "why", r));
    expect(overrideCommands("x", "other", r)[0]).not.toEqual(overrideCommands("x", "why", r)[0]);
  });
});
