// The poller's re-route call site: queued runs of the list go to env.reroute with their age; no decision is made here
// (Lean `ci.reroute` sits behind the hook, tested in apps/runner).
import assert from "node:assert/strict";
import { mkdirSync, readFileSync } from "node:fs";
import test from "node:test";
import { pollOnce, rerouteTick, type QueuedRun, type RerouteEnv } from "../src/poller.ts";
import { paths, type Row } from "../src/state.ts";
import { addWaiter, sentinelId } from "../src/wait.ts";
import { mkWorld } from "./util.ts";

const T0 = 1_800_000_000;
const iso = (t: number) => new Date(t * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
const row = (id: number, status: string, createdS: number): Row => ({ status, conclusion: null, databaseId: id, headBranch: "ci/x", workflowName: "webkit-sim", headSha: "a".repeat(40), createdAt: iso(createdS) });

test("only queued rows reach the hook, with their age in seconds", async () => {
  const w = mkWorld(T0, { fastGh: true }); const env: RerouteEnv = w.env;
  const got: QueuedRun[][] = [];
  env.reroute = async (q) => { got.push(q); };
  const n = await rerouteTick(env, [row(1, "queued", T0 - 400), row(2, "in_progress", T0 - 900), row(3, "completed", T0 - 900)], T0);
  assert.equal(n, 1);
  assert.deepEqual(got, [[{ runId: 1, workflow: "webkit-sim", sha: "a".repeat(40), branch: "ci/x", queuedS: 400 }]]);
});

test("no hook or no queued row: nothing is called", async () => {
  const w = mkWorld(T0, { fastGh: true }); const env: RerouteEnv = w.env;
  assert.equal(await rerouteTick(env, [row(1, "queued", T0 - 400)], T0), 0);
  let calls = 0;
  env.reroute = async () => { calls++; };
  assert.equal(await rerouteTick(env, [row(2, "completed", T0 - 400)], T0), 0);
  assert.equal(calls, 0);
});

test("a failing hook is logged and the poll goes on", async () => {
  const w = mkWorld(T0, { fastGh: true }); const env: RerouteEnv = w.env;
  mkdirSync(w.stateDir, { recursive: true });
  env.reroute = async () => { throw new Error("boom"); };
  await rerouteTick(env, [row(1, "queued", T0 - 400)], T0);
  assert.match(readFileSync(paths(w.stateDir).incidents, "utf8"), /rerouteFailed.*boom/);
});

test("pollOnce passes the listed queued run to the hook", async () => {
  const w = mkWorld(T0, { fastGh: true }); const env: RerouteEnv = w.env;
  w.config({ start: T0 - 1000, listCost: 2, runs: [{ databaseId: 7, createdAt: T0 - 3, completeAt: T0 + 9999, headBranch: "ci/x", workflowName: "webkit-sim", headSha: "b".repeat(40) }] });
  const inner = w.env.exec!;
  w.env.exec = (args) => { const o = inner(args); return { ...o, stdout: o.stdout.replace(/"in_progress"/g, '"queued"') }; };
  const seen: QueuedRun[] = [];
  env.reroute = async (q) => { seen.push(...q); };
  addWaiter(env, sentinelId({ branch: "ci/x", sha: "b".repeat(40) }), T0 - 5);
  const p = await pollOnce(env);
  assert.equal(p.ticked, true);
  assert.deepEqual(seen.map((q) => [q.runId, q.workflow, q.queuedS]), [[7, "webkit-sim", 3]]);
});
