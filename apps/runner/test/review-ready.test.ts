// fw review ready|verdict: golden vectors of fwcore `plan.reviewReady` and `plan.reviewVerdict` (Fw.Plan.ReviewReady) and the CLI
// around them. The golden responses come from the fwcore binary; regenerate with
//   FW_WRITE_REVIEW_READY_GOLDEN=1 pnpm --filter ./apps/runner exec vitest run test/review-ready.test.ts
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { READY_EXIT, readyCli } from "../src/review-ready.ts";
import { coreCandidates, coreCaller } from "../src/watch.ts";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../../..");
const goldenFile = join(root, "packages/contracts/golden/plan/review-ready.jsonl");
const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: root, encoding: "utf8" }).trim();
const bins = coreCandidates(root, join(common, "..")).filter((b) => {
  try { return execFileSync(b, ["--ops"], { encoding: "utf8" }).includes("plan.reviewReady"); } catch { return false; }
});
const bin = bins[0];

const dry = "VERDICT dry t";
const item = (status: string, evidence: string, id = "x") => ({ id, status, evidence });
const ready = (items: unknown[], runs: unknown[] = [], d: string | null = dry) => ({ op: "plan.reviewReady", items, runs, task: "t", dry: d });
const verdict = (severities: string[], audited?: boolean) => ({ op: "plan.reviewVerdict", severities, ...(audited === undefined ? {} : { audited }) });
const cases: [string, Record<string, unknown>][] = [
  ["review: a done item with a file:line", ready([item("done", "lean/Fw/Plan/ReviewReady.lean:12-30")])],
  ["review: a done item citing a run id", ready([item("done", "run:123456, apps/runner/src/fw.ts:10")])],
  ["review: a follow-up item needs no evidence", ready([item("followUp", "")])],
  ["review: a pending item whose run completed", ready([item("pending", "run:7")], [{ id: "7", state: "complete" }])],
  ["returnToBuilder: the dry line is missing", ready([item("done", "a.ts:1")], [], null)],
  ["returnToBuilder: the dry land was refused", ready([item("done", "a.ts:1")], [], "VERDICT scope t")],
  ["returnToBuilder: the dry line is another task's", ready([item("done", "lean/Fw/X.lean:12")], [], "VERDICT dry other")],
  ["returnToBuilder: the dry line has no task id", ready([item("done", "lean/Fw/X.lean:12")], [], "VERDICT dry ")],
  ["returnToBuilder: no items", ready([])],
  ["returnToBuilder: a done item without file:line or run id", ready([item("done", "see the summary")])],
  ["returnToBuilder: a path without a line number", ready([item("done", "lean/Fw/X.lean")])],
  ["returnToBuilder: an undelivered unit item", ready([item("undelivered", "")])],
  ["returnToBuilder: an unknown status word", ready([item("finished", "a.ts:1")])],
  ["returnToBuilder: a pending item with an unknown run", ready([item("pending", "run:9")])],
  ["returnToBuilder: a pending item whose run failed", ready([item("pending", "run:9")], [{ id: "9", state: "failed" }])],
  ["returnToBuilder: a builder fault hides a dispatch", ready([item("dispatch", "gh workflow run x"), item("done", "nothing")])],
  ["dispatch: the lead must start a run", ready([item("dispatch", "gh workflow run x"), item("done", "a.ts:1")])],
  ["dispatch: a dispatch hides a wait", ready([item("pending", "run:1"), item("dispatch", "cmd")], [{ id: "1", state: "running" }])],
  ["returnToBuilder: a blank dispatch command is a builder fault", ready([item("dispatch", "  ")])],
  ["wait: a named run is still running", ready([item("pending", "run:1"), item("done", "a.ts:1")], [{ id: "1", state: "running" }])],
  ["verdict: only follow-ups accept", verdict(["follow-up", "follow-up"])],
  ["verdict: no findings accept", verdict([])],
  ["verdict: a blocker refuses", verdict(["follow-up", "blocker"])],
  ["verdict: fix-before-land refuses until the audit", verdict(["fix-before-land"])],
  ["verdict: fix-before-land accepts after the audit, with a re-check", verdict(["fix-before-land", "follow-up"], true)],
  ["verdict: a blocker refuses after the audit too", verdict(["blocker", "fix-before-land"], true)],
  ["verdict: an unknown word is a blocker", verdict(["high"], true)],
];

function fwcore(reqs: Record<string, unknown>[]): Record<string, unknown>[] {
  const out = spawnSync(bin!, [], { input: reqs.map((r) => JSON.stringify(r)).join("\n") + "\n", encoding: "utf8", env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" } });
  return out.stdout.trim().split("\n").map((l) => { const { id: _, ...rest } = JSON.parse(l); return rest; });
}
const stored = () => readFileSync(goldenFile, "utf8").trim().split("\n").map((l) => JSON.parse(l)) as { name: string; request: unknown; response: Record<string, unknown> }[];

describe("plan.reviewReady / plan.reviewVerdict golden (packages/contracts/golden/plan/review-ready.jsonl)", () => {
  it("fwcore with the ops is built (cd lean && lake build)", () => expect(bin).toBeTruthy());

  it("the file holds exactly the cases above, and fwcore gives every stored response", () => {
    const reqs = cases.map(([, r]) => JSON.parse(JSON.stringify(r)) as Record<string, unknown>);
    const got = fwcore(reqs);
    if (process.env.FW_WRITE_REVIEW_READY_GOLDEN) {
      writeFileSync(goldenFile, cases.map(([name], i) => JSON.stringify({ name, request: reqs[i], response: got[i] })).join("\n") + "\n");
    }
    expect(stored().map((l) => l.name)).toEqual(cases.map(([n]) => n));
    expect(stored().map((l) => l.request)).toEqual(reqs);
    expect(got).toEqual(stored().map((l) => l.response));
  });

  it("each case name starts with the answer it must have (one answer per branch is covered)", () => {
    for (const l of stored()) {
      const [kind, rest] = l.name.split(": ");
      if (kind === "verdict") continue;
      expect(l.response.ready, rest).toBe(kind);
    }
    const kinds = new Set(stored().map((l) => l.response.ready).filter(Boolean));
    expect([...kinds].sort()).toEqual(["dispatch", "returnToBuilder", "review", "wait"]);
  });

  it("the verdict branches: accept, refuse, recheck", () => {
    const v = (n: string) => stored().find((l) => l.name.startsWith(n))!.response;
    expect(v("verdict: only follow-ups")).toMatchObject({ verdict: "accept", recheck: false });
    expect(v("verdict: a blocker refuses")).toMatchObject({ verdict: "refuse", blockers: 1 });
    expect(v("verdict: fix-before-land refuses")).toMatchObject({ verdict: "refuse", recheck: true });
    expect(v("verdict: fix-before-land accepts")).toMatchObject({ verdict: "accept", recheck: true, fixes: 1 });
    expect(v("verdict: a blocker refuses after")).toMatchObject({ verdict: "refuse", recheck: false });
    expect(v("verdict: an unknown word")).toMatchObject({ verdict: "refuse", blockers: 1 });
  });
});

describe("fw review ready|verdict CLI", () => {
  const call = coreCaller(bins);
  const tmp = mkdtempSync(join(tmpdir(), "rr-"));
  const file = (name: string, v: unknown) => { const p = join(tmp, name); writeFileSync(p, JSON.stringify(v)); return p; };
  async function run(argv: string[]) {
    const lines: string[] = [];
    const code = await readyCli(argv, root, { core: call, log: (l) => lines.push(l) });
    return { code, lines };
  }

  it("a sound report prints the review line and exits 0", async () => {
    const r = await run(["ready", "--report", file("ok.json", { items: [item("done", "a.ts:1")], dry }), "--task", "t"]);
    expect(r.code).toBe(0);
    expect(r.lines).toEqual(["VERDICT review-ready t review"]);
  });

  it("each answer has its own exit code and the line is last", async () => {
    const cases2: [unknown, string][] = [
      [{ items: [item("pending", "run:1")], runs: [{ id: "1", state: "running" }], dry }, "wait"],
      [{ items: [item("dispatch", "cmd")], dry }, "dispatch"],
      [{ items: [item("done", "nope", "bad")], dry }, "returnToBuilder"],
    ];
    for (const [rep, want] of cases2) {
      const r = await run(["ready", "--report", file("c.json", rep), "--task", "t"]);
      expect(r.code).toBe(READY_EXIT[want as keyof typeof READY_EXIT]);
      expect(r.lines.at(-1)).toBe(`VERDICT review-ready t ${want}`);
    }
  });

  it("a report without the dry line names it and goes back", async () => {
    const r = await run(["ready", "--report", file("nodry.json", { items: [item("done", "a.ts:1")] })]);
    expect(r.code).toBe(23);
    expect(r.lines.join("\n")).toContain("must carry exactly `VERDICT dry -`");
  });

  it("the item that holds the gate is named", async () => {
    const r = await run(["ready", "--report", file("n.json", { items: [item("done", "a.ts:1", "ok"), item("done", "prose", "bad")], dry }), "--task", "t"]);
    expect(r.lines.join("\n")).toContain("item bad (done): returnToBuilder");
    expect(r.lines.join("\n")).not.toContain("item ok");
  });

  it("a dry line of another task goes back (exit 23)", async () => {
    const r = await run(["ready", "--report", file("o.json", { items: [item("done", "a.ts:1")], dry: "VERDICT dry other" }), "--task", "t"]);
    expect(r.code).toBe(23);
    expect(r.lines.at(-1)).toBe("VERDICT review-ready t returnToBuilder");
  });

  it("fwcore errors still print exactly one VERDICT line, last (ready: returnToBuilder 23, verdict: refuse 1)", async () => {
    const boom = async () => { throw new Error("fwcore obs.health failed: unknown op plan.reviewReady"); };
    const lines: string[] = [];
    const log = (l: string) => lines.push(l);
    const rep = file("e.json", { items: [item("done", "a.ts:1")], dry });
    expect(await readyCli(["ready", "--report", rep, "--task", "t"], root, { core: boom, log })).toBe(23);
    expect(lines).toEqual(["  fwcore: fwcore obs.health failed: unknown op plan.reviewReady", "VERDICT review-ready t returnToBuilder"]);
    lines.length = 0;
    const fnd = file("ef.json", [{ severity: "follow-up" }]);
    expect(await readyCli(["verdict", "--findings", fnd, "--task", "t"], root, { core: boom, log })).toBe(1);
    expect(lines).toEqual(["  fwcore: fwcore obs.health failed: unknown op plan.reviewReady", "VERDICT review-verdict t refuse"]);
    expect(lines.filter((l) => l.startsWith("VERDICT")).length).toBe(1);
  });

  it("a later fwcore error or a missing answer still ends in one returnToBuilder line (exit 23)", async () => {
    let n = 0;
    const second = async () => { if (++n === 1) return { ready: "returnToBuilder" }; throw new Error("boom on call 2"); };
    const empty = async () => ({});
    const rep = file("e2.json", { items: [item("done", "a.ts:1")], dry });
    for (const core of [second, empty]) {
      const lines: string[] = [];
      expect(await readyCli(["ready", "--report", rep, "--task", "t"], root, { core, log: (l) => lines.push(l) })).toBe(23);
      expect(lines.at(-1)).toBe("VERDICT review-ready t returnToBuilder");
      expect(lines.filter((l) => l.startsWith("VERDICT")).length).toBe(1);
    }
  });

  it("verdict: blockers refuse (exit 1), follow-ups accept (exit 0), fix-before-land follows the audit flag", async () => {
    const f = (sev: string[]) => file("f.json", { findings: sev.map((severity) => ({ severity, where: "x", what: "y" })) });
    expect((await run(["verdict", "--findings", f(["follow-up"])])).code).toBe(0);
    expect((await run(["verdict", "--findings", f(["blocker"])])).code).toBe(1);
    expect((await run(["verdict", "--findings", f(["fix-before-land"])])).code).toBe(1);
    const a = await run(["verdict", "--findings", f(["fix-before-land"]), "--audited", "yes", "--task", "t"]);
    expect(a.code).toBe(0);
    expect(a.lines.at(-1)).toBe("VERDICT review-verdict t accept");
    expect(a.lines.join("\n")).toContain("checker re-checks");
  });
});
