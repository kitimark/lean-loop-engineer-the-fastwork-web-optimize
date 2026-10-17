import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { engineCheckCli, findCounts, type CountsFile, observedFor, parseCheckArgs, parseRows, renderCheck, variantKeys, type CheckReply, type Row } from "../src/engine-check.ts";
import { UsageError } from "../src/lib.ts";
import { fwcoreCall } from "../src/run.ts";

describe("parseCheckArgs / parseRows", () => {
  it("flags", () => {
    expect(parseCheckArgs(["--rows", "r.jsonl", "--run", "d"])).toEqual({ rows: "r.jsonl", run: "d", json: false });
    expect(parseCheckArgs(["--json", "--rows", "r", "--run", "d", "--classes", "c.json"])).toEqual({ rows: "r", run: "d", classes: "c.json", json: true });
    expect(() => parseCheckArgs(["--run", "d"])).toThrow(UsageError);
    expect(() => parseCheckArgs(["--rows", "r"])).toThrow(UsageError);
    expect(() => parseCheckArgs(["--rows", "r", "--run"])).toThrow(UsageError);
    expect(() => parseCheckArgs(["--nope"])).toThrow(UsageError);
  });
  it("rows are JSON lines; blank lines are skipped; bad JSON names the line", () => {
    expect(parseRows('{"engine":"chromium"}\n\n{"engine":"webkit"}\n')).toHaveLength(2);
    expect(() => parseRows('{"engine":"chromium"}\nnope')).toThrow(/line 2/);
  });
});

describe("variantKeys / observedFor", () => {
  it("target, target+search, explicit variant", () => {
    expect(variantKeys({ meta: { target: "original", search: "" } })).toEqual(["original"]);
    expect(variantKeys({ meta: { target: "rewrite", search: "?fw=a:b" } })).toEqual(["rewrite+?fw=a:b", "rewrite"]);
    expect(variantKeys({ meta: { target: "rewrite", variant: "v1" } })).toEqual(["v1"]);
    expect(variantKeys({})).toEqual([]);
  });
  it("only the (scenario, variant, type) a row asks for, one series per run, missing counts are 0", () => {
    const f = (o: number): CountsFile => ({ profile: { id: "s" }, meta: { target: "original" }, frames: [{ counts: { A: o, B: 9 } }, { counts: { B: 1 } }] });
    const rows: Row[] = [{ engine: "chromium", scenario: "s", variant: "rewrite", stage: "paint", prediction: "<o", countType: "A" }];
    const g: CountsFile = { profile: { id: "s" }, meta: { target: "rewrite" }, frames: [{ counts: { A: 1 } }] };
    expect(observedFor([f(3), f(4), g, { profile: { id: "other" }, meta: { target: "original" }, frames: [] }], rows)).toEqual([
      { scenario: "s", variant: "original", type: "A", runs: [[3, 0], [4, 0]] },
      { scenario: "s", variant: "rewrite", type: "A", runs: [[1]] }]);
  });
});

describe("renderCheck", () => {
  it("one line per row and a tally", () => {
    const r: CheckReply = { tally: { pass: 1, modelBug: 0, unusable: 1 }, verdicts: [
      { engine: "chromium", scenario: "s", variant: "rewrite", stage: "paint", prediction: "=0", countType: "T", base: "original", verdict: "pass", reason: "ok",
        class: { variant: "deterministic", base: "deterministic" }, runs: { variant: 2, base: 2 }, totals: { variant: [0, 0], base: [4, 4] } },
      { engine: "webkit", scenario: "s", variant: "rewrite", stage: "paint", prediction: "=0", countType: "T", base: "original", verdict: "unusable", reason: "no lane yet",
        class: { variant: "deterministic", base: "deterministic" }, runs: { variant: 0, base: 0 }, totals: { variant: [], base: [] } }] };
    const out = renderCheck(r);
    expect(out).toHaveLength(3);
    expect(out[0]).toMatch(/^PASS/);
    expect(out[1]).toMatch(/^unusable.*no observation.*no lane yet/);
    expect(out[2]).toBe("engine-check: 1 pass, 0 model-bug, 1 unusable (2 rows)");
  });
});

const hasCore = (() => { try { fwcoreCall(process.cwd()); return true; } catch { return false; } })();

// The model: the F1/F2 fixture shape of packages/measure-chromium/README.md (120 frames; compositor animation:
// Paint 0, Layout 0, cc.Commit 0, UpdateLayoutTree 120; main-thread animation: Paint 240, Layout 162, UpdateLayoutTree 162).
// The counts here are synthetic: the fixture run's counts.json is not in the repo.
const FRAMES = 120;
const series = (f: (i: number) => number) => Array.from({ length: FRAMES }, (_, i) => f(i));
const mainThread: Record<string, number[]> = {
  "trace.Paint": series(() => 2), "trace.Layout": series((i) => (i < 81 ? 2 : 0)), "trace.UpdateLayoutTree": series((i) => (i < 42 ? 2 : 1)),
  "trace.cc.Commit": series(() => 0), "trace.Noisy": series(() => 1), "trace.Raster": series((i) => (i === 0 ? 20 : 0)) };
const compositor = (raster: number): Record<string, number[]> => ({
  "trace.Paint": series(() => 0), "trace.Layout": series(() => 0), "trace.UpdateLayoutTree": series(() => 1),
  "trace.cc.Commit": series(() => 0), "trace.Noisy": series(() => 0), "trace.Raster": series((i) => (i === 0 ? raster : 0)) });
const cls = (c: string, k = 0, t = 0) => ({ class: c, k, t });
const types = { "trace.Paint": cls("deterministic"), "trace.Layout": cls("deterministic"), "trace.UpdateLayoutTree": cls("deterministic"),
  "trace.cc.Commit": cls("deterministic"), "trace.Noisy": cls("quarantined"), "trace.Raster": cls("stable", 1, 3) };
const frozen = { profiles: { "fixture-rest": { arms: { original: { types }, rewrite: { types } } } } };

function artifact(raster: number): string {
  const dir = mkdtempSync(join(tmpdir(), "engine-check-"));
  const put = (name: string, target: string, counts: Record<string, number[]>) => {
    mkdirSync(join(dir, name), { recursive: true });
    const frames = Array.from({ length: FRAMES }, (_, i) => ({ counts: Object.fromEntries(Object.entries(counts).map(([t, s]) => [t, s[i]!])) }));
    writeFileSync(join(dir, name, "counts.json"), JSON.stringify({ profile: { id: "fixture-rest" }, meta: { target, search: "" }, frames }));
  };
  for (const r of ["r1", "r2"]) { put(`orig-${r}`, "original", mainThread); put(`rew-${r}`, "rewrite", compositor(raster)); }
  writeFileSync(join(dir, "classes.json"), JSON.stringify(frozen));
  return dir;
}

const row = (prediction: string, countType: string, engine = "chromium", variant = "rewrite"): Row => ({ engine, scenario: "fixture-rest", variant, stage: "paint", prediction, countType });
const rowsFile = (dir: string, rows: Row[]): string => { const p = join(dir, "rows.jsonl"); writeFileSync(p, rows.map((r) => JSON.stringify(r)).join("\n") + "\n"); return p; };

describe.skipIf(!hasCore)("engine-check through fwcore (F1/F2 shape, synthetic counts)", () => {
  const check = (dir: string, rows: Row[]) => {
    const lines: string[] = [];
    const code = engineCheckCli(["--rows", rowsFile(dir, rows), "--run", dir, "--classes", join(dir, "classes.json"), "--json"], process.cwd(), (l) => lines.push(l));
    return { code, reply: JSON.parse(lines.join("\n")) as CheckReply };
  };
  const verdicts = (dir: string, rows: Row[]) => check(dir, rows).reply.verdicts.map((v) => v.verdict);

  it("F1: a compositor animation has no Paint, no Layout, no commit (=0 passes on det types); UpdateLayoutTree is not 0 (model bug)", () => {
    const dir = artifact(10);
    const { code, reply } = check(dir, [row("=0", "trace.Paint"), row("=0", "trace.Layout"), row("=0", "trace.cc.Commit"), row("=0", "trace.UpdateLayoutTree")]);
    expect(reply.verdicts.map((v) => v.verdict)).toEqual(["pass", "pass", "pass", "model-bug"]);
    expect(reply.tally).toEqual({ pass: 3, modelBug: 1, unusable: 0 });
    expect(reply.verdicts[3]!.totals).toEqual({ variant: [120, 120], base: [162, 162] });
    expect(code).toBe(3);
  });
  it("F2: the compositor animation does strictly less Paint and Layout than the main-thread one (<o on det types)", () => {
    const dir = artifact(10);
    expect(verdicts(dir, [row("<o", "trace.Paint"), row("<o", "trace.Layout"), row("<o", "trace.UpdateLayoutTree"), row("≤o", "trace.UpdateLayoutTree")])).toEqual(["pass", "pass", "pass", "pass"]);
    expect(check(dir, [row("<o", "trace.Paint")]).code).toBe(0);
    // reversed: claiming the main-thread run does less is refuted by the compositor-vs-main-thread totals
    expect(verdicts(dir, [{ ...row("<o", "trace.Paint", "chromium", "original"), base: "rewrite" }])).toEqual(["model-bug"]);
  });
  it("quarantined types are never used; webkit rows have no lane yet", () => {
    const dir = artifact(10);
    const { reply } = check(dir, [row("=0", "trace.Noisy"), row("<o", "trace.Noisy"), row("=0", "trace.Paint", "webkit")]);
    expect(reply.verdicts.map((v) => [v.verdict, v.reason])).toEqual([
      ["unusable", "quarantined type: never used"], ["unusable", "quarantined type: never used"], ["unusable", "no lane yet"]]);
  });
  it("stable types: pass outside the margin, unusable inside it, never a strict <o", () => {
    expect(verdicts(artifact(10), [row("≤o", "trace.Raster")])).toEqual(["pass"]); // 10 + 2*3 <= 20
    const inside = artifact(18);
    expect(verdicts(inside, [row("≤o", "trace.Raster"), row("<o", "trace.Raster")])).toEqual(["unusable", "unusable"]);
    expect(verdicts(artifact(30), [row("≤o", "trace.Raster")])).toEqual(["model-bug"]); // 30 > 20 + 6
  });
  it("no observation: unusable, not a verdict; an unknown prediction is refused", () => {
    const dir = artifact(10);
    expect(verdicts(dir, [{ ...row("=0", "trace.Paint"), scenario: "swipe-v1" }])).toEqual(["unusable"]);
    expect(() => check(dir, [row("<=>", "trace.Paint")])).toThrow(/unknown prediction/);
  });
  it("an empty run directory is a usage error", () => {
    const dir = mkdtempSync(join(tmpdir(), "engine-check-empty-"));
    expect(findCounts(dir)).toEqual([]);
    writeFileSync(join(dir, "classes.json"), JSON.stringify(frozen));
    expect(() => engineCheckCli(["--rows", rowsFile(dir, [row("=0", "trace.Paint")]), "--run", dir, "--classes", join(dir, "classes.json")], process.cwd(), () => {})).toThrow(/no counts.json/);
  });
});
