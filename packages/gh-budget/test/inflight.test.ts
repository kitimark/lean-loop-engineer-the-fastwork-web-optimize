// Task gh-budget-fresh-inflight (incident 2026-10-26): a queued or in-progress row in the meta cache was trusted at any age,
// so `fw ci wait <id>` on a run that had long finished idled to its cap. Lean `Fw.Ci.Attempt.trusted` / `uncoveredExit`;
// golden ci/attempt-inflight.jsonl. Every world lives in a temp directory with a fake gh and a simulated clock.
import assert from "node:assert/strict";
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { INFLIGHT_S, UNCOVERED_CODE, trustedRow, uncoveredExit, uncoveredSince, waitFor } from "../src/wait.ts";
import { paths } from "../src/state.ts";
import { drive, goldenDir, mkWorld } from "./util.ts";

const T0 = 1_800_000_000;
const iso = (t: number) => new Date(t * 1000).toISOString();
const run = (databaseId: number, extra: Record<string, unknown> = {}) => ({ databaseId, createdAt: T0 - 7200, completeAt: T0 - 3600, conclusion: "success", ...extra });
const goldenCases = () => readFileSync(join(goldenDir, "..", "ci", "attempt-inflight.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as Record<string, unknown>);

function metaRow(dir: string, id: number, status: string, readAt: number): void {
  mkdirSync(join(dir, "meta"), { recursive: true });
  writeFileSync(paths(dir).meta(id), JSON.stringify({ status, conclusion: null, databaseId: id, headBranch: "ci/x", workflowName: "chromium-counts", headSha: "abc", createdAt: iso(T0 - 7200), readAt }));
}
const incident = (dir: string, runId: number, time: number, why = "uncovered") => appendFileSync(paths(dir).incidents, JSON.stringify({ runId, time, why }) + "\n");
const viewsOf = (calls: { args: string[] }[], id: number) => calls.filter((c) => c.args[0] === "run" && c.args[1] === "view" && c.args[2] === String(id) && !c.args[4]!.startsWith("jobs"));

test("trustedRow and uncoveredExit replay golden ci/attempt-inflight.jsonl", () => {
  const w = mkWorld(T0, { fastGh: true });
  const cases = goldenCases();
  assert.ok(cases.length >= 10);
  assert.equal(INFLIGHT_S, 300);
  for (const c of cases) {
    if (c.kind === "trusted") {
      const env = { ...w.env, now: () => c.now as number };
      assert.equal(trustedRow(env, c.completed as boolean, c.read as number), c.trusted, String(c.name));
    } else {
      assert.equal(uncoveredExit(c.incidents as number), c.exit, String(c.name));
      assert.equal(UNCOVERED_CODE, c.code, String(c.name));
    }
  }
  assert.equal(trustedRow(w.env, false, undefined), false, "a row with no read time is never trusted");
});

test("a stale queued row of a completed run returns within one tick, with one charged view and no tick of the poller", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(99)] });
  metaRow(w.stateDir, 99, "queued", T0 - 3600);
  const [res] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 99 }, { timeoutS: 540 })]);
  assert.equal(res!.code, 0, res!.lines.join("\n"));
  assert.equal(w.sim.t, T0, "no virtual time passed: not one sleep");
  assert.equal(viewsOf(w.calls(), 99).length, 1, "one charged run view for the stale row");
  assert.equal(w.calls().some((c) => c.args[1] === "list"), false, "no list tick");
  const meta = JSON.parse(readFileSync(paths(w.stateDir).meta(99), "utf8")) as { status: string; readAt: number };
  assert.equal(meta.status, "completed");
  assert.equal(meta.readAt, T0);
});

test("a queued row inside its bound is trusted: no view", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(98, { completeAt: 1e12 })] });
  metaRow(w.stateDir, 98, "in_progress", T0 - INFLIGHT_S);
  const [res] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 98 }, { timeoutS: 60 })]);
  assert.equal(res!.code, 3);
  assert.equal(viewsOf(w.calls(), 98).length, 0);
});

test("a stale in-progress row of a run still running is viewed once per wait, never again inside the wait", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(97, { createdAt: T0 - 1000, completeAt: 1e12 })] });
  metaRow(w.stateDir, 97, "in_progress", T0 - 4 * 3600);
  const [res] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 97 }, { timeoutS: 900 })]);
  assert.equal(res!.code, 3);
  assert.equal(viewsOf(w.calls(), 97).length, 1);
});

test("a gh failure of the refreshing view is exit 2 and is not retried (no retry on 403)", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  metaRow(w.stateDir, 96, "queued", T0 - 3600);
  const [res] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 96 }, { timeoutS: 540 })]);
  assert.equal(res!.code, 2);
  assert.equal(viewsOf(w.calls(), 96).length, 1);
});

test("a repeated uncovered incident of the run ends the wait with exit 6, one incident does not", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(77, { createdAt: T0 - 100, completeAt: 1e12 })] });
  metaRow(w.stateDir, 77, "in_progress", T0);
  incident(w.stateDir, 77, T0 - 50); // before this wait began
  incident(w.stateDir, 78, T0); // another run
  incident(w.stateDir, 77, T0, "orphan"); // another reason
  incident(w.stateDir, 77, T0);
  assert.equal(uncoveredSince(w.env, 77, T0), 1);
  const [one] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 77 }, { timeoutS: 60 })]);
  assert.equal(one!.code, 3, "one incident keeps waiting");
  incident(w.stateDir, 77, w.sim.t);
  incident(w.stateDir, 77, w.sim.t);
  const [two] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 77 }, { timeoutS: 3600 })]);
  assert.equal(two!.code, 6);
  assert.match(two!.lines[0]!, /does not cover run 77/);
});
