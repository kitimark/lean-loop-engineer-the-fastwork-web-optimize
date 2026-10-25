import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { lanePool, placeCmArtifacts, readGhBusy, realRoute, routeCells, type CmDeps } from "../src/ci-pool-tier.ts";
import { fwcoreCall, type PlanJob } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const SHA = "a".repeat(40);
const idle = { ghMacBusy: 0, ghTotalBusy: 0 };
const facts = { cmUsed: 0, cmBusy: 0 };
const cell = (vms: number, busy = idle, f = facts, target = "original") => routeCells(call, { sha: SHA, key: "0".repeat(64), target, vms, busy, facts: f });

describe("routeCells: the Lean route at dispatch time", () => {
  it("github first: idle GitHub keeps every cell", () => {
    const r = cell(3);
    expect(r.codemagic).toBe(0);
    expect(r.github).toBe(3);
  });
  it("overflow only when full: all 5 slots busy sends one cell to Codemagic, the rest wait on GitHub", () => {
    const r = cell(3, { ghMacBusy: 5, ghTotalBusy: 5 });
    expect(r.codemagic).toBe(1);
    expect(r.github).toBe(2);
    expect(r.rows.filter((x) => x.decision === "codemagic")).toHaveLength(1);
  });
  it("Codemagic busy: nothing to overflow to", () => {
    expect(cell(2, { ghMacBusy: 5, ghTotalBusy: 5 }, { cmUsed: 0, cmBusy: 1 }).codemagic).toBe(0);
  });
  it("budget stop: 400 used refuses, 399 admits at most the capped cell", () => {
    const full = { ghMacBusy: 5, ghTotalBusy: 5 };
    expect(cell(1, full, { cmUsed: 400, cmBusy: 0 }).codemagic).toBe(0);
    expect(cell(1, full, { cmUsed: 360, cmBusy: 0 }).codemagic).toBe(1);
    expect(cell(1, full, { cmUsed: 361, cmBusy: 0 }).codemagic).toBe(0);
  });
  it("the rewrite arm never goes to Codemagic", () => {
    expect(lanePool("rewrite")).toBe("webkit-sim-rewrite");
    expect(cell(2, { ghMacBusy: 5, ghTotalBusy: 5 }, facts, "rewrite").codemagic).toBe(0);
  });
});

describe("readGhBusy", () => {
  it("counts in-progress and queued macOS jobs of in-progress macOS workflows", async () => {
    const gh = async (a: string[]) => {
      if (a[1] === "list") return JSON.stringify([{ databaseId: 1, workflowName: "webkit-sim" }, { databaseId: 2, workflowName: "lean" }]);
      expect(a.slice(0, 3)).toEqual(["run", "view", "1"]);
      return JSON.stringify({ jobs: [{ name: "vm1", status: "in_progress" }, { name: "vm2", status: "queued" }, { name: "plan", status: "in_progress" }, { name: "vm0", status: "completed" }] });
    };
    const macOf = (_wf: string, names: string[]) => names.map((n) => n.startsWith("vm"));
    expect(await readGhBusy(gh, macOf)).toEqual({ ghMacBusy: 2, ghTotalBusy: 3 });
  });
});

describe("realRoute.split", () => {
  const job = (inputs: Record<string, string>) => ({ engine: "webkit", workflow: "webkit-sim.yml", inputs, digest: "d", key: [] }) as unknown as PlanJob;
  const mk = (full: boolean, trig = { code: 0, build: "b".repeat(24) }) => {
    const dir = mkdtempSync(join(tmpdir(), "route-"));
    const triggered: Record<string, string>[] = [];
    const cm: CmDeps = {
      trigger: async (_b, vars) => { triggered.push(vars); return trig; },
      wait: async (_b, out) => { mkdirSync(join(out, "artifacts"), { recursive: true }); return 0; },
      read: () => ({ status: "finished", startedAt: 5, finishedAt: 9, createdAt: 1, minutes: 4, sha: SHA }),
      facts: () => facts,
    };
    const gh = async (a: string[]) => (a[1] === "list" ? JSON.stringify(full ? [{ databaseId: 1, workflowName: "webkit-sim" }] : []) : JSON.stringify({ jobs: Array.from({ length: 5 }, (_, i) => ({ name: `sim (v${i + 1})`, status: "in_progress" })) }));
    const r = realRoute({ root, consoleDir: dir, call, gh, log: () => {}, now: () => 7, cm });
    const events = () => readFileSync(join(dir, "ci-route.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Record<string, unknown>);
    return { r, triggered, events, dir };
  };
  it("full GitHub: one cell goes to Codemagic as v3, the route and the build are recorded with redacted times", async () => {
    const m = mk(true);
    const s = await m.r.split(job({ vms: "3", sessions: "2", target: "original" }), "ci/x", SHA);
    expect(s.github).toBe(2);
    expect(m.triggered).toEqual([{ FW_TARGET: "original", FW_PRESET: "original", FW_FW: "", FW_VM: "v3", FW_SESSIONS: "2" }]);
    const cells = await s.cm;
    expect(cells.map((c) => c.vm)).toEqual(["v3"]);
    const ev = m.events();
    expect(ev[0]).toMatchObject({ kind: "ci.route", cells: 3, codemagic: 1, github: 2 });
    expect(ev[1]).toMatchObject({ kind: "ci.codemagic.build", vm: "v3", startedAt: 5, finishedAt: 9 });
    expect(JSON.stringify(ev)).not.toMatch(/@|token/i);
  });
  it("idle GitHub: nothing is triggered", async () => {
    const m = mk(false);
    const s = await m.r.split(job({ vms: "3", target: "original" }), "ci/x", SHA);
    expect(s.github).toBe(3);
    expect(m.triggered).toEqual([]);
  });
  it("skips are recorded: rewrite arm, non-ci ref, single cell", async () => {
    for (const [inputs, ref, why] of [[{ vms: "3", target: "rewrite" }, "ci/x", /rewrite/], [{ vms: "3", target: "original" }, "main", /not a pushed ci/], [{ vms: "1", target: "original" }, "ci/x", /one cell/]] as const) {
      const m = mk(true);
      const s = await m.r.split(job({ ...inputs }), ref, SHA);
      expect(s.github).toBe(Number(inputs.vms));
      expect(String(m.events()[0]!.why)).toMatch(why);
    }
  });
  it("a refused Codemagic trigger is recorded and stops the run", async () => {
    const m = mk(true, { code: 5, build: undefined as unknown as string });
    await expect(m.r.split(job({ vms: "2", target: "original" }), "ci/x", SHA)).rejects.toThrow(/--no-route/);
    expect(m.events().at(-1)).toMatchObject({ kind: "ci.codemagic.refused", vm: "v2", code: 5 });
  });
  it("a Codemagic build of another commit is refused", async () => {
    const m = mk(true);
    const s = await m.r.split(job({ vms: "2", target: "original" }), "ci/x", "c".repeat(40));
    await expect(s.cm).rejects.toThrow(/measured aaaaaaa/);
  });
});

describe("placeCmArtifacts", () => {
  it("files one VM's artifacts where gh run download puts webkit-sim-<vm>", () => {
    const out = mkdtempSync(join(tmpdir(), "cm-")), dir = mkdtempSync(join(tmpdir(), "dl-"));
    mkdirSync(join(out, "artifacts"));
    for (const f of ["v3-session-1.json", "v3-session-1.md", "runner.json", "tools.txt", "other.txt"]) writeFileSync(join(out, "artifacts", f), f);
    expect(placeCmArtifacts(out, dir, "v3")).toBe(4);
    expect(readFileSync(join(dir, "webkit-sim-v3", "v3-session-1.json"), "utf8")).toBe("v3-session-1.json");
  });
});
