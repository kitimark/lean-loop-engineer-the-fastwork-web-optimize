// The stale-watch path of the poller on a simulated clock (incident 2026-10-20, Lean `Fw.Ci.Budget` section (i)): an old
// branch watch is dropped with an incident, a tick never reads more pages than the tick share allows, and the poller
// does not stop `tooBig`. Every state lives in a temp directory (mkWorld); the real .git/fw-gh-budget is never touched.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { pollOnce } from "../src/poller.ts";
import { loadState, paths, readStatus, stepEvent } from "../src/state.ts";
import { sentinelId } from "../src/wait.ts";
import { mkWorld } from "./util.ts";

const T0 = 1_800_000_000;
const incidents = (dir: string) => {
  try { return readFileSync(paths(dir).incidents, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as { runId: number; time: number; why: string }); } catch { return []; }
};
const watched = (dir: string) => ((loadState(dir)?.watched as { runId: number }[] | undefined) ?? []).map((w) => w.runId);

test("a sentinel watch older than the longest workflow timeout is dropped with an incident, no tick, no stop", () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  const stray = sentinelId({ branch: "ci/x", sha: "abc" });
  stepEvent(w.env, { register: { runId: stray, createdAt: T0 - 16_200 } }); // created 4.5 h ago
  stepEvent(w.env, { pages: 11 });
  return pollOnce(w.env).then((p) => {
    assert.equal(p.stopped, undefined);
    assert.equal(p.ticked, false);
    assert.deepEqual(watched(w.stateDir), []);
    assert.deepEqual(incidents(w.stateDir), [{ runId: stray, time: T0, why: "expired" }]);
    assert.equal(w.calls().length, 0, "nothing to watch, so no gh call");
    assert.deepEqual((loadState(w.stateDir)?.incidents as unknown[]), [], "acknowledged after the log");
  });
});

test("a young sentinel watch is kept (the branch waiter is alive)", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  const id = sentinelId({ branch: "ci/x", sha: "abc" });
  stepEvent(w.env, { register: { runId: id, createdAt: T0 - 3_000 } });
  const p = await pollOnce(w.env);
  assert.equal(p.ticked, true);
  assert.deepEqual(watched(w.stateDir), [id], "a sentinel is not a run: the list never shows it, only its age ends it");
  w.sim.set(T0 + 7_300); // past 7200 s of age
  await pollOnce(w.env);
  assert.deepEqual(watched(w.stateDir), []);
  assert.equal(incidents(w.stateDir)[0]?.why, "expired");
});

test("a run missing from three covering lists is dropped as unseen; one that shows up keeps its place", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [{ databaseId: 501, createdAt: T0 - 5, completeAt: T0 + 100_000 }] });
  stepEvent(w.env, { register: { runId: 501, createdAt: T0 - 10 } });
  stepEvent(w.env, { register: { runId: 502, createdAt: T0 - 10 } }); // no such run on GitHub
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
  stepEvent(w.env, { register: { runId: 7, createdAt: T0 - 100 } }); // older than every listed row
  stepEvent(w.env, { register: { runId: 2_199, createdAt: T0 - 50 } }); // among the newest 1000
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
