import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { dryTotalStep } from "../src/land.ts";
import { lintPlan } from "../src/land-verdict.ts";
import { EXIT_ERROR, run } from "../src/slot.ts";
import { cmdKey, kindCap, runStep, seenInFile, seenKeys, waitStep } from "../src/slot-span.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const golden = readFileSync(join(root, "packages/contracts/golden/obs/slot-key.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: { kind: string; seen: string[]; argv: string[] }; response: { step: string; wait: string } });

describe("slot span keys against the Lean golden", () => {
  it("has the golden cases", () => expect(golden.length).toBeGreaterThanOrEqual(22));
  for (const g of golden) {
    it(`run and wait labels: ${g.name}`, () => {
      expect(runStep(g.request.kind, g.request.seen, g.request.argv)).toBe(g.response.step);
      expect(waitStep(g.request.kind)).toBe(g.response.wait);
    });
  }
  it("the caps are the Lean ones, per kind", () => expect(["check", "test", "land", "sim"].map(kindCap)).toEqual([24, 24, 8, 4]));
  it("never writes a path, a value or a home directory into a key", () => {
    expect(cmdKey(["/opt/bin/tool", "/opt/x/script.sh"])).toBe("tool script.sh");
    expect(cmdKey(["sh", "name=value"])).toBeNull();
    expect(cmdKey(["x".repeat(61)])).toBeNull();
  });
});

const jsonl = <T,>(f: string): T[] => readFileSync(join(root, "packages/contracts/golden/obs", f), "utf8").trim().split("\n").map((l) => JSON.parse(l) as T);

describe("seenKeys against the Lean golden", () => {
  for (const g of jsonl<{ name: string; request: { kind: string; steps: string[] }; response: { seen: string[] } }>("slot-seen.jsonl")) {
    it(g.name, () => expect(seenKeys(g.request.steps.map((x) => JSON.stringify({ step: x })).join("\n"), g.request.kind)).toEqual(g.response.seen));
  }
  it("reading the file in chunks gives the keys of the whole file, whatever the cut", () => {
    const dir = mkdtempSync(join(tmpdir(), "slot-seen-"));
    try {
      const f = join(dir, "timings.jsonl");
      const lines = Array.from({ length: 200000 }, (_, i) => JSON.stringify({ step: `slot run check sh k${i % 40}.sh`, pad: "x".repeat(10) }));
      writeFileSync(f, lines.join("\n") + "\n");
      expect(seenInFile(f, "check").sort()).toEqual(Array.from({ length: 40 }, (_, i) => `sh k${i}.sh`).sort());
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
  it("keys that scroll out of any tail stay seen: the first line of a big file still counts", () => {
    const dir = mkdtempSync(join(tmpdir(), "slot-seen-"));
    try {
      const f = join(dir, "timings.jsonl");
      writeFileSync(f, [JSON.stringify({ step: "slot run check sh old.sh" }), ...Array.from({ length: 100000 }, () => JSON.stringify({ step: "slot run check sh new.sh", pad: "y".repeat(60) }))].join("\n") + "\n");
      expect(seenInFile(f, "check")).toContain("sh old.sh");
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});

describe("the dry land total is keyed by its Lean dry plan", () => {
  for (const g of jsonl<{ name: string; request: { changed: string[]; hasCiPaths: boolean; hasAxioms: boolean; hasFootprint: boolean; fwcoreBuild: boolean }; response: { step: string } }>("dry-step.jsonl")) {
    it(g.name, () => {
      const r = g.request;
      expect(dryTotalStep(lintPlan(r.changed, r.hasCiPaths, r.hasAxioms, r.hasFootprint), r.fwcoreBuild)).toBe(g.response.step);
    });
  }
});

const POOLED = [87823, 89931, 1898, 94518, 106347, 105730, 102091, 1034, 2091, 795, 115010, 154518, 35271, 89530, 8676, 281, 3887, 882, 111717, 116460, 1471,
  216518, 232769, 249554, 370230, 224826, 90376, 162599, 250562, 100284, 145990, 129470, 3581, 7775, 4334, 130449, 160033, 89825, 25397, 1314, 196958,
  288499, 260119, 2067, 3592, 134824, 92421, 583, 1811, 101369, 37045, 14988, 38697];

const fwcore = join(root, "lean/.lake/build/bin/fwcore");
const params = { budgetMs: 30000, budgets: [], ceilings: [], kDen: 2, kNum: 3, loadMax: 8, nMin: 5, window: 20, stages: [] };
const sample = (step: string, durMs: number) => ({ durMs, exit: 0, host: "local", load: 4, runKind: "", skipped: false, step, tool: "fw" });
const synthetic = (step: string, durMs: number, tool = "fw") => ({ ...sample(step, durMs), tool, synthetic: true });
const lastCode = (samples: object[]): string => {
  const r = spawnSync(fwcore, [], { input: `${JSON.stringify({ id: 0, op: "obs.timing", params, samples })}\n`, encoding: "utf8", maxBuffer: 64 << 20 });
  const rows = JSON.parse(r.stdout.split("\n")[0]!) as { verdicts: { kind: string; code: string }[] };
  return rows.verdicts.filter((v) => v.kind === "sample").at(-1)!.code;
};

describe.skipIf(!existsSync(fwcore))("the 2026-10-22 16:51 alert", () => {
  it("fired under the pooled key `slot run check`: the window mixed 0.3 s and 370 s runs", () => {
    expect(POOLED.length).toBe(53);
    expect(lastCode(POOLED.map((d) => sample("slot run check", d)))).toBe("slow");
  });
  it("does not fire under the command key: its key has no earlier sample, so it is noBaseline until five runs of that command exist", () => {
    const step = runStep("check", [], ["sh", "lean/scripts/check.sh"]);
    expect(step).toBe("slot run check sh lean/scripts/check.sh");
    const hist = POOLED.slice(0, -1).map((d) => sample("slot run check", d));
    expect(lastCode([...hist, sample(step, 38697)])).toBe("noBaseline");
    const own = [90000, 92000, 89000, 91000, 90500].map((d) => synthetic(step, d));
    expect(lastCode([...hist, ...own, sample(step, 38697)])).toBe("ok");
  });
});

describe.skipIf(!existsSync(fwcore))("queue waits are not judged by the 30 s budget", () => {
  const hist = [100, 120, 90, 110, 100].map((d) => synthetic("slot wait check", d, "fw wait"));
  it("a 40 s wait against a near-zero median is ok, the same 40 s run is slow", () => {
    expect(lastCode([...hist, synthetic("slot wait check", 40000, "fw wait")])).toBe("ok");
    expect(lastCode([...[100, 120, 90, 110, 100].map((d) => synthetic("slot run check x", d)), synthetic("slot run check x", 40000)])).toBe("slow");
  });
  it("a wait over the wait budget (30 min) is slow", () => expect(lastCode([...hist, synthetic("slot wait check", 1800001, "fw wait")])).toBe("slow"));
});

describe("slot run writes the run span under the command key", () => {
  it("a run inside a held slot records `slot run <kind>` (here no key: the argument has a space) with its exit", async () => {
    const dir = mkdtempSync(join(tmpdir(), "slot-span-"));
    const file = join(dir, "timings.jsonl");
    process.env.FW_TIMINGS_FILE = file;
    try {
      const d = { env: { FW_SLOT_HELD: "1", PATH: process.env.PATH }, out: () => {}, err: () => {} } as never;
      expect(await run(d, "check", ["sh", "-c", "exit 3"], false)).toBe(3);
      const rows = readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l) as { step: string; exit: number });
      expect(rows.map((r) => [r.step, r.exit])).toEqual([["slot run check", 3]]);
    } finally {
      delete process.env.FW_TIMINGS_FILE;
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("a run whose exec throws still writes its span, with the error exit", async () => {
    const dir = mkdtempSync(join(tmpdir(), "slot-span-"));
    const file = join(dir, "timings.jsonl");
    process.env.FW_TIMINGS_FILE = file;
    try {
      const d = { env: { FW_SLOT_HELD: "1", PATH: process.env.PATH }, out: () => {}, err: () => {} } as never;
      await expect(run(d, "check", ["sh\0x"], false)).rejects.toThrow();
      const rows = readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l) as { step: string; exit: number });
      expect(rows.map((r) => [r.step, r.exit])).toEqual([["slot run check", EXIT_ERROR]]);
    } finally {
      delete process.env.FW_TIMINGS_FILE;
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
