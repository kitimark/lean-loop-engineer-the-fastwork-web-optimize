// Golden obs/timing-capnets.jsonl (Lean `Fw.Wire.Obs.Timing.capNetsCases`, theorem `Fw.Obs.Timing.netMsOf_capNets`):
// each `ci wait` span replays through fwcore `obs.timing` to the own time Lean computed.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fwcoreCall } from "../src/core.ts";
import { repoRoot } from "./util.ts";

type Row = { name: string; span: Record<string, unknown>; waits: { why: string; ms: number; nets: boolean }[]; capMs: number; netMs: number; gapOwnMs: number; ownMs: number };
const rows = readFileSync(join(repoRoot, "packages/contracts/golden/obs/timing-capnets.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Row);
const params = { budgetMs: 1, budgets: [], ceilings: [], kDen: 1, kNum: 1, loadMax: 1000, nMin: 1, stages: [] };

test("timing-capnets golden: floor, share and slack-absorbed waits", () => {
  assert.equal(rows.length, 3);
  assert.deepEqual(rows.map((r) => r.waits.filter((w) => !w.nets).map((w) => w.why)), [["floor"], ["hour"], ["minute"]]);
});

for (const r of rows) {
  test(r.name, () => {
    const s = r.span;
    const sample = { tool: s.tool, step: s.step, durMs: s.durMs, host: s.host, load: 0, exit: s.exit, startMs: s.startMs, phases: s.phases };
    const out = fwcoreCall(repoRoot)({ op: "obs.timing", params, samples: [sample] }) as { verdicts?: { kind: string; durMs: number }[] };
    assert.equal(out.verdicts?.find((v) => v.kind === "sample")?.durMs, r.ownMs);
  });
}
