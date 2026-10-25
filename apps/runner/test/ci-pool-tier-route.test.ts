import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { classRowsOf, poolRows, readPairs, recordPair, rerouteQueued, type PairRecord, cellMerged, parseHw, parsePlatformKey, placeCmArtifacts, poolCell, planCells, readGhBusy, realRoute, routeCells, type CmDeps } from "../src/ci-pool-tier.ts";
import type { PlanJob } from "@fw/contracts";
import { fwcoreCall } from "../src/run.ts";

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
  it("the rewrite arm is routable under its own lane: a full GitHub sends one rewrite cell to Codemagic", () => {
    expect(poolCell(call, "rewrite")).toMatchObject({ lane: "webkit-sim-rewrite", routable: true, needsDigest: true });
    expect(cell(2, { ghMacBusy: 5, ghTotalBusy: 5 }, facts, "rewrite").codemagic).toBe(1);
    expect(cell(2, idle, facts, "rewrite").codemagic).toBe(0);
  });
  it("both is not routable (two arms in one run)", () => {
    expect(poolCell(call, "both")).toMatchObject({ lane: null, routable: false });
  });
  it("Lean files a rewrite cell only with equal, non-empty site digests; the original arm needs none", () => {
    expect(poolCell(call, "rewrite", "ab", "ab").filed).toBe(true);
    expect(poolCell(call, "rewrite", "ab", "cd").filed).toBe(false);
    expect(poolCell(call, "rewrite", "ab", null).filed).toBe(false);
    expect(poolCell(call, "rewrite", null, "ab").filed).toBe(false);
    expect(poolCell(call, "original", null, null).filed).toBe(true);
  });
  it("planCells names the rewrite VMs r<n> and carries the planned query", () => {
    expect(planCells(call, { target: "rewrite", vms: 3, sessions: "1", preset: "original", fw: "", sha: SHA }).map((c) => c.vm)).toEqual(["r1", "r2", "r3"]);
    expect(planCells(call, { target: "original", vms: 2, sessions: "1", preset: "original", fw: "", sha: SHA }).map((c) => c.vm)).toEqual(["v1", "v2"]);
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
  const mk = (full: boolean, trig = { code: 0, build: "b".repeat(24) }, ghDigest: string | null = "ab", cmDigest: string | null = "ab", docSha: string | null = SHA) => {
    const dir = mkdtempSync(join(tmpdir(), "route-"));
    const triggered: Record<string, string>[] = [];
    const cm: CmDeps = {
      trigger: async (_b, vars) => { triggered.push(vars); return trig; },
      wait: async (_b, out) => { mkdirSync(join(out, "artifacts"), { recursive: true }); return 0; },
      read: () => ({ status: "finished", startedAt: 5, finishedAt: 9, createdAt: 1, minutes: 4, sha: docSha }),
      facts: () => facts,
      githubSiteDigest: async () => ghDigest,
      siteDigestOf: () => cmDigest,
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
  it("full GitHub, rewrite: the Codemagic cell is r3 with FW_TARGET rewrite and the planned query", async () => {
    const m = mk(true);
    const s = await m.r.split(job({ vms: "3", target: "rewrite", preset: "original", fw: "" }), "ci/x", SHA);
    expect(s.github).toBe(2);
    expect(m.triggered).toEqual([{ FW_TARGET: "rewrite", FW_PRESET: "original", FW_FW: "", FW_VM: "r3", FW_SESSIONS: "1", FW_SEARCH: "" }]);
    expect(m.events()[0]).toMatchObject({ kind: "ci.route", target: "rewrite", lane: "webkit-sim-rewrite", codemagic: 1 });
  });
  it("place: a rewrite cell is filed when its site digest equals the GitHub site job digest, and the event says so", async () => {
    const m = mk(true);
    const s = await m.r.split(job({ vms: "2", target: "rewrite" }), "ci/x", SHA);
    const cells = await s.cm;
    mkdirSync(join(cells[0]!.out, "artifacts"), { recursive: true });
    writeFileSync(join(cells[0]!.out, "artifacts", "r2-session-1.json"), "{}");
    await m.r.place(mkdtempSync(join(tmpdir(), "dl-")), cells, "99").catch((e: Error) => { if (!/merge failed/.test(e.message)) throw e; });
    expect(m.events().find((e) => e.kind === "ci.site.digest")).toMatchObject({ vm: "r2", github: "ab", codemagic: "ab", filed: true });
  });
  it("place: a differing or missing site digest refuses the rewrite cell, nothing is placed", async () => {
    for (const [g, c] of [["ab", "cd"], ["ab", null], [null, "ab"]] as const) {
      const m = mk(true, undefined, g, c);
      const cells = await (await m.r.split(job({ vms: "2", target: "rewrite" }), "ci/x", SHA)).cm;
      const dl = mkdtempSync(join(tmpdir(), "dl-"));
      await expect(m.r.place(dl, cells, "99")).rejects.toThrow(/not routable/);
      expect(m.events().find((e) => e.kind === "ci.site.digest")).toMatchObject({ filed: false });
    }
  });
  it("skips are recorded: not routable target, non-ci ref, single cell", async () => {
    for (const [inputs, ref, why] of [[{ vms: "3", target: "both" }, "ci/x", /not routable/], [{ vms: "3", target: "original" }, "main", /not a pushed ci/], [{ vms: "1", target: "original" }, "ci/x", /one cell/]] as const) {
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

const TOOLS = (mac: string, xc: string, rt: string, extra = "") =>
  `ProductName:\t\tmacOS\nProductVersion:\t\t27.0.1\nBuildVersion:\t\t${mac}\nXcode 27.1\nBuild version ${xc}\n== Runtimes ==\n${extra}iOS 27.0 (27.0 - ${rt}) - com.apple.CoreSimulator.SimRuntime.iOS-27-0\nv24.22.0\n12\n17179869184\narm64\n`;

describe("toolchain identity of a Codemagic cell (Lean ci.cellMerged)", () => {
  const gh = parsePlatformKey(TOOLS("26A434", "27A9275", "24A434"));
  it("parses the three builds; an extra other-version runtime does not matter", () => {
    expect(gh).toEqual({ macosBuild: "26A434", xcodeBuild: "27A9275", runtimeBuild: "24A434", cpus: 12, memsize: 17179869184 });
    expect(parsePlatformKey(TOOLS("26A434", "27A9275", "24A434", "iOS 26.5 (26.5 - 23F77) - x\n"))).toEqual(gh);
    expect(parsePlatformKey(null)).toEqual({ macosBuild: "", xcodeBuild: "", runtimeBuild: "", cpus: 0, memsize: 0 });
  });
  it("round-2 pair refused, pinned pair merged, missing runtime refused", () => {
    expect(cellMerged(call, gh, parsePlatformKey(TOOLS("26A428", "27A266a", "24A434")))).toBe(false);
    expect(cellMerged(call, gh, parsePlatformKey(TOOLS("26A434", "27A9275", "24A434")))).toBe(true);
    expect(cellMerged(call, gh, parsePlatformKey(TOOLS("26A434", "27A9275", "24A434").replace(/^iOS 27.*\n/m, "")))).toBe(false);
  });
  it("equal toolchain, other hardware: not merged (the 3 cpu GitHub cell against the 8 cpu Codemagic cell)", () => {
    const other = parsePlatformKey(TOOLS("26A434", "27A9275", "24A434").replace("12\n17179869184", "8\n12884901888"));
    expect(other.cpus).toBe(8);
    expect(cellMerged(call, gh, other)).toBe(false);
    expect(cellMerged(call, gh, parsePlatformKey(TOOLS("26A434", "27A9275", "24A434").replace("12\n17179869184\n", "")))).toBe(false);
  });
  it("hardware: sysctl lines of tools.txt, runner.json cpus", () => {
    const d = mkdtempSync(join(tmpdir(), "hw-"));
    writeFileSync(join(d, "tools.txt"), TOOLS("a", "b", "c"));
    expect(parseHw(d)).toEqual({ cpus: 12, memsize: 17179869184 });
    writeFileSync(join(d, "runner.json"), JSON.stringify({ cpus: 3 }));
    expect(parseHw(d)).toEqual({ cpus: 3, memsize: 17179869184 });
  });
});

describe("row pooling by pinned pairs (Lean ci.poolRows)", () => {
  const ghK = parsePlatformKey(TOOLS("a", "b", "c").replace("12\n17179869184", "3\n7516192768"));
  const cmK = parsePlatformKey(TOOLS("a", "b", "c").replace("12\n17179869184", "8\n12884901888"));
  const pair = (n: number, cm: string): PairRecord => ({ sha: "1".repeat(40), target: "original", vm: "v3", ghRun: String(n), cmBuild: `cm:${String(n).padStart(24, "0")}`, ghKey: ghK, cmKey: cmK, gh: { "a|m|l": "stable", "b|m|l": "stable" }, cm: { "a|m|l": "stable", "b|m|l": cm } });
  it("classRowsOf reads the class table", () => {
    expect(classRowsOf("| family | metric | level | class | a | b | c | d |\n|---|\n| x | y | z | **stable** | 1 | 2 | 3 | 4 |\n")).toEqual({ "x|y|z": "stable" });
  });
  it("three agreeing pairs pool a row, one disagreement refuses only that row, two pairs pool nothing", () => {
    const three = poolRows(call, ghK, cmK, [pair(1, "stable"), pair(2, "stable"), pair(3, "quarantined")]);
    expect(three.rows).toEqual([{ row: "a|m|l", use: "paired", class: "stable" }, { row: "b|m|l", use: "refused" }]);
    expect(three.counts).toEqual({ direct: 0, paired: 1, refused: 1 });
    expect(poolRows(call, ghK, cmK, [pair(1, "stable"), pair(2, "stable")]).counts.paired).toBe(0);
    expect(poolRows(call, ghK, cmK, [pair(1, "stable"), pair(2, "stable"), pair(3, "stable")], 166).reachable).toBe(3);
  });
  it("recordPair and readPairs round-trip", () => {
    const d = mkdtempSync(join(tmpdir(), "pairs-"));
    recordPair(d, pair(1, "stable"));
    expect(readPairs(d)).toEqual([pair(1, "stable")]);
    expect(readPairs(join(d, "none"))).toEqual([]);
  });
});

describe("queued re-route glue (Lean ci.reroute)", () => {
  const req = { capMin: 40, cfg: "00".repeat(32), engine: "iosSimSafari", image: "xcode-27", lane: "webkit-sim", rep: 0, sha: "0123456789abcdef0123456789abcdef01234567" };
  const state = { ccSpent: 3575, ccStorage: 30, cmUsed: 166, ghMacBusy: 5, ghRemainingS: null, ghTotalBusy: 5 };
  const run = async (queuedS: number, runCells: number, code = 0) => {
    const calls: string[] = [];
    const out = await rerouteQueued(call, state, [{ req, queuedS, runCells, runId: "42" }], {
      trigger: async () => { calls.push("trigger"); return { build: code ? null : "a".repeat(24), code }; },
      cancel: async (id) => { calls.push(`cancel ${id}`); }, log: () => {} });
    return { out, calls };
  };
  it("aged lone job: Codemagic first, then the GitHub run is cancelled", async () => {
    expect(await run(300, 1)).toEqual({ out: ["a".repeat(24)], calls: ["trigger", "cancel 42"] });
  });
  it("young, shared, or refused: the GitHub run is untouched", async () => {
    expect((await run(299, 1)).calls).toEqual([]);
    expect((await run(900, 2)).calls).toEqual([]);
    expect((await run(300, 1, 5)).calls).toEqual(["trigger"]);
  });
});

describe("realRoute place: platform verdict and missing sha", () => {
  const job = (inputs: Record<string, string>) => ({ engine: "webkit", workflow: "webkit-sim.yml", inputs, digest: "d", key: [] }) as unknown as PlanJob;
  const run = async (cmTools: string, docSha: string | null = SHA) => {
    const dir = mkdtempSync(join(tmpdir(), "route-"));
    const cm: CmDeps = {
      trigger: async () => ({ code: 0, build: "b".repeat(24) }),
      wait: async (_b, out) => { mkdirSync(join(out, "artifacts"), { recursive: true }); writeFileSync(join(out, "artifacts", "tools.txt"), cmTools); writeFileSync(join(out, "artifacts", "v3-session-1.json"), "{}"); return 0; },
      read: () => ({ status: "finished", startedAt: 5, finishedAt: 9, createdAt: 1, minutes: 4, sha: docSha }),
      facts: () => ({ cmUsed: 46, cmBusy: 0, ccSpent: 3575, ccStorage: 30 }),
      githubSiteDigest: async () => null,
      siteDigestOf: () => null,
    };
    const gh = async (a: string[]) => (a[1] === "list" ? JSON.stringify([{ databaseId: 1, workflowName: "webkit-sim" }]) : JSON.stringify({ jobs: Array.from({ length: 5 }, (_, i) => ({ name: `sim (v${i + 1})`, status: "in_progress" })) }));
    const r = realRoute({ root, consoleDir: dir, call, gh, log: () => {}, now: () => 7, cm });
    const events = () => readFileSync(join(dir, "ci-route.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Record<string, unknown>);
    const s = await r.split(job({ vms: "3", target: "original" }), "ci/x", SHA);
    return { r, s, events, dir };
  };
  it("a build that reports no sha is refused", async () => {
    const m = await run(TOOLS("26A434", "27A9275", "24A434"), null);
    await expect(m.s.cm).rejects.toThrow(/no commit sha/);
  });
  it("a refused toolchain is filed aside with its key and emits ci.cell.platform merged:false", async () => {
    const m = await run(TOOLS("26A428", "27A266a", "24A434"));
    const cells = await m.s.cm;
    const dl = mkdtempSync(join(tmpdir(), "dl-"));
    mkdirSync(join(dl, "webkit-sim-v1"), { recursive: true });
    writeFileSync(join(dl, "webkit-sim-v1", "tools.txt"), TOOLS("26A434", "27A9275", "24A434"));
    await m.r.place(dl, cells, "99").catch((e: Error) => { if (!/merge failed/.test(e.message)) throw e; });
    expect(m.events().find((e) => e.kind === "ci.cell.platform")).toMatchObject({ vm: "v3", merged: false, key: { macosBuild: "26A428", xcodeBuild: "27A266a", runtimeBuild: "24A434" }, ref: { macosBuild: "26A434" } });
    expect(readFileSync(join(dl, "refused", "webkit-sim-v3", "tools.txt"), "utf8")).toContain("26A428");
  });
  it("a pinned toolchain is merged: its cell is placed beside the GitHub cells", async () => {
    const m = await run(TOOLS("26A434", "27A9275", "24A434"));
    const cells = await m.s.cm;
    const dl = mkdtempSync(join(tmpdir(), "dl-"));
    mkdirSync(join(dl, "webkit-sim-v1"), { recursive: true });
    writeFileSync(join(dl, "webkit-sim-v1", "tools.txt"), TOOLS("26A434", "27A9275", "24A434"));
    await m.r.place(dl, cells, "99").catch((e: Error) => { if (!/merge failed/.test(e.message)) throw e; });
    expect(m.events().find((e) => e.kind === "ci.cell.platform")).toMatchObject({ vm: "v3", merged: true });
    expect(readFileSync(join(dl, "webkit-sim-v3", "tools.txt"), "utf8")).toContain("26A434");
  });
  it("no reference tools.txt: the cell is refused (an unread key never merges)", async () => {
    const m = await run(TOOLS("26A434", "27A9275", "24A434"));
    const cells = await m.s.cm;
    const dl = mkdtempSync(join(tmpdir(), "dl-"));
    await m.r.place(dl, cells, "99").catch((e: Error) => { if (!/merge failed/.test(e.message)) throw e; });
    expect(m.events().find((e) => e.kind === "ci.cell.platform")).toMatchObject({ merged: false });
  });
});
