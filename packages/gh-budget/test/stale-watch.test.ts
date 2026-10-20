// The stale-watch path of the poller on a simulated clock (incident 2026-10-20, Lean `Fw.Ci.Budget` section (i)): a tick never reads more pages than the tick share allows, and the poller
// does not stop `tooBig`. Every state lives in a temp directory (mkWorld); the real .git/fw-gh-budget is never touched.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";
import { pollOnce } from "../src/poller.ts";
import { loadState, paths, readStatus, stepEvent } from "../src/state.ts";
import { logCleanupFailure } from "../src/cli.ts";
import { addWaiter, dropWaiter, sentinelId } from "../src/wait.ts";
import { mkWorld } from "./util.ts";

const T0 = 1_800_000_000;
const incidents = (dir: string) => {
  try { return readFileSync(paths(dir).incidents, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as { runId: number; time: number; why: string }); } catch { return []; }
};
const watched = (dir: string) => ((loadState(dir)?.watched as { runId: number }[] | undefined) ?? []).map((w) => w.runId);

test("a sentinel with a live waiter is not dropped by lists: it stays registered and the poller keeps ticking", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  const id = sentinelId({ branch: "ci/x", sha: "abc" });
  addWaiter(w.env, id, T0 - 16_200);
  let ticks = 0;
  for (let i = 0; i < 5; i++) {
    const p = await pollOnce(w.env);
    assert.equal(p.stopped, undefined);
    if (p.ticked) ticks++;
    w.sim.set(p.wakeAt);
  }
  assert.ok(ticks >= 2, `the poller ticked ${ticks} times`);
  assert.equal(w.calls().filter((c) => c.args[1] === "list").length, ticks);
  assert.deepEqual(watched(w.stateDir), [id]);
  assert.deepEqual(incidents(w.stateDir), []);
});

test("a failed cleanup is logged as {cleanupFailed, at} in incidents.jsonl", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  const id = sentinelId({ branch: "ci/z", sha: "ghi" });
  const marker = addWaiter(w.env, id, T0 - 5);
  const env = { ...w.env, core: () => { throw new Error("fwcore killed"); } };
  try { dropWaiter(env, id, marker); assert.fail("expected a throw"); } catch (e) { logCleanupFailure(w.env, e); }
  const lines = readFileSync(paths(w.env.dir).incidents, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
  assert.deepEqual(lines, [{ cleanupFailed: "fwcore killed", at: T0 }]);
});

test("the unregister goes before the marker is unlinked: a failed step leaves the marker", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  const id = sentinelId({ branch: "ci/y", sha: "def" });
  const marker = addWaiter(w.env, id, T0 - 5);
  const real = w.env.core;
  const env = { ...w.env, core: () => { throw new Error("fwcore killed"); } };
  assert.throws(() => dropWaiter(env, id, marker), /fwcore killed/);
  assert.ok(readdirSync(paths(w.env.dir).waiters).length === 1, "the marker stays for a later sweep");
  assert.deepEqual(watched(w.stateDir), [id]);
  dropWaiter({ ...w.env, core: real }, id, marker); // the later sweep
  assert.deepEqual(watched(w.stateDir), []);
  assert.equal(readdirSync(paths(w.env.dir).waiters).length, 0);
});

test("a run missing from three covering lists is dropped as unseen; one that shows up keeps its place", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [{ databaseId: 501, createdAt: T0 - 5, completeAt: T0 + 100_000 }] });
  addWaiter(w.env, 501, T0 - 10);
  addWaiter(w.env, 502, T0 - 10); // no such run on GitHub
  let ticks = 0;
  for (let i = 0; i < 20 && ticks < 3; i++) {
    const p = await pollOnce(w.env);
    assert.equal(p.stopped, undefined);
    if (p.ticked) ticks++;
    w.sim.set(p.wakeAt);
  }
  assert.equal(ticks, 3);
  assert.deepEqual(watched(w.stateDir), [501]);
  const inc = incidents(w.stateDir);
  assert.equal(inc.length, 1);
  assert.equal(inc[0]!.runId, 502);
  assert.equal(inc[0]!.why, "unseen");
});

test("a tick needing more pages than the share reads the newest pages, drops what it cannot cover, and does not stop", async () => {
  const w = mkWorld(T0, { fastGh: true });
  const runs = Array.from({ length: 1_200 }, (_, i) => ({ databaseId: 1_000 + i, createdAt: T0 - 50, completeAt: T0 + 100_000 }));
  w.config({ start: T0, listCost: 20, runs }); // what GitHub bills for 10 pages
  addWaiter(w.env, 7, T0 - 100); // older than every listed row
  addWaiter(w.env, 2_199, T0 - 50); // among the newest 1000
  stepEvent(w.env, { pages: 11 }); // the state of the incident: 11 pages asked for, cost 22 > the minute share 20
  const p = await pollOnce(w.env);
  assert.equal(p.stopped, undefined, "no tooBig stop");
  assert.equal(p.ticked, true);
  const list = w.calls().filter((c) => c.args[1] === "list");
  assert.equal(list.length, 1);
  assert.equal(list[0]!.cost, 20);
  assert.equal(list[0]!.args[list[0]!.args.indexOf("--limit") + 1], "1000", "10 pages of 100");
  assert.deepEqual(watched(w.stateDir), [2_199]);
  assert.deepEqual(incidents(w.stateDir), [{ runId: 7, time: T0, why: "uncovered" }]);
  assert.equal(readStatus(w.stateDir)?.stopped, undefined);
});

test("registration refuses an id that is neither a run id nor a branch sentinel", () => {
  const w = mkWorld(T0, { fastGh: true });
  assert.throws(() => stepEvent(w.env, { register: { runId: 5_000_000_000_000_000, createdAt: T0 } }), /neither a GitHub run id nor a branch sentinel/);
  assert.throws(() => stepEvent(w.env, { register: { runId: 0, createdAt: T0 } }), /neither/);
  assert.deepEqual(watched(w.stateDir), []);
  stepEvent(w.env, { register: { runId: 25_000_000_000, createdAt: T0 } });
  assert.deepEqual(watched(w.stateDir), [25_000_000_000]);
});
