// One row per run: the TS twin (src/want.ts dedupById, dupIds) equals Lean Fw.Ci.Dispatch on every `dedup` line of the golden,
// and the poller applies it before any select (incident: `nonce 912416a6895d9222 matches several runs (40196217959, 40196217959)`).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { updatedMs } from "../src/poller.ts";
import { paths, readStatus } from "../src/state.ts";
import { waitFor } from "../src/wait.ts";
import { dedupById, dupIds, selectOne, titleOf, type WRun, type Want } from "../src/want.ts";
import { drive, mkWorld, repoRoot } from "./util.ts";

type LRow = WRun & { updatedAt: number };
type Line = { name: string; want: Want; rows: LRow[]; kept: LRow[]; dups: number[]; result: unknown };
const lines: Line[] = readFileSync(join(repoRoot, "packages", "contracts", "golden", "ci", "dispatch.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l)).filter((l) => l.kind === "dedup");

test("dedupById, dupIds and selectOne on the kept rows equal Lean on every dedup line", () => {
  assert.ok(lines.length >= 8);
  const twice = lines.find((l) => l.rows.length === 2 && JSON.stringify(l.rows[0]) === JSON.stringify(l.rows[1]));
  assert.ok(twice, "the golden has the [a, a] case");
  assert.deepEqual(twice.result, { kind: "found", id: twice.rows[0]!.id });
  for (const k of ["found", "absent", "ambiguous"]) assert.ok(lines.some((l) => (l.result as { kind: string }).kind === k), k);
  for (const l of lines) {
    const kept = dedupById(l.rows, (r) => r.id, (r) => r.updatedAt);
    assert.deepEqual(kept, l.kept, l.name);
    assert.deepEqual(dupIds(l.rows, (r) => r.id), l.dups, l.name);
    assert.deepEqual(selectOne(l.want, kept), l.result, l.name);
  }
});

test("updatedMs: an ISO time in epoch milliseconds; absent or unreadable is 0 (the copy that loses)", () => {
  const r = { status: "completed", conclusion: "success", databaseId: 1, headBranch: "b", workflowName: "w", headSha: "s", createdAt: "2026-10-25T13:08:00Z" };
  assert.equal(updatedMs({ ...r, updatedAt: "2026-10-25T13:08:07Z" }), Date.UTC(2026, 9, 25, 13, 8, 7));
  assert.equal(updatedMs(r), 0);
  assert.equal(updatedMs({ ...r, updatedAt: "not a time" }), 0);
});

const T0 = 1_800_000_000;
const SHA = "abcdef1234567890abcdef1234567890abcdef12";

test("one dispatch listed twice by gh: the poller keeps one row, logs the duplicate id, and the wait finds the run", async () => {
  const want: Want = { kind: "dispatch", workflow: "trajectory-probe", nonce: "aaaa1111" };
  const run = { databaseId: 6, createdAt: T0, completeAt: T0 + 50, conclusion: "success", workflowName: "trajectory-probe", headBranch: "ci/x", headSha: SHA, event: "workflow_dispatch", displayTitle: titleOf("aaaa1111") };
  const w = mkWorld(T0 + 100, { fastGh: true });
  w.config({ start: T0 + 100, listCost: 2, runs: [run, run] });
  const [res] = await drive(w.sim, [waitFor(w.env, { kind: "branch", branch: "ci/x", workflow: "trajectory-probe", sha: SHA, since: T0 - 1, want }, { timeoutS: 3600 })]);
  assert.deepEqual(res, { code: 0, lines: ["run 6 trajectory-probe success -> pass"] });
  assert.deepEqual(readStatus(w.stateDir)?.rows.map((r) => r.databaseId), [6]);
  const logged = readFileSync(paths(w.stateDir).incidents, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
  assert.ok(logged.some((e) => JSON.stringify(e.duplicateIds) === "[6]" && e.listed === 2), JSON.stringify(logged));
});
