// A watch is kept exactly while its waiter lives (Lean `Fw.Ci.Budget` section (j): `Marker.alive`, `sweep`, `next_window_from_live`).
// The glue reads facts (kill(pid, 0), the recorded and the current process start time); fwcore decides. Every state lives in a
// temp directory (mkWorld) on a simulated clock; the real .git/fw-gh-budget is never touched.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { iso, pollOnce } from "../src/poller.ts";
import { tryLock } from "../src/lock.ts";
import { loadState, paths, stepEvent } from "../src/state.ts";
import { addWaiter, sentinelId } from "../src/wait.ts";
import { readMarkers, selfStart, startToken } from "../src/waiters.ts";
import { mkWorld, type World } from "./util.ts";

const T0 = 1_800_000_000;
const LONG_AGO = "Thu Jan  1 00:00:00 1970";
const incidents = (dir: string) => {
  try { return readFileSync(paths(dir).incidents, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as { runId: number; time: number; why: string }); } catch { return []; }
};
const watched = (dir: string) => ((loadState(dir)?.watched as { runId: number }[] | undefined) ?? []).map((w) => w.runId);

/** A pid that existed and is gone: a child that has exited and been reaped. */
function deadPid(): number {
  const r = spawnSync(process.execPath, ["-e", ""]);
  assert.ok(r.pid && r.status === 0);
  return r.pid;
}

/** A marker as an older or foreign process left it: `r<id>.<pid>.<name>` with the given text, and the watch it registered. */
function plant(w: World, id: number, createdAt: number, pid: number, text: string, name = "deadbeef"): void {
  const dir = paths(w.env.dir).waiters;
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `r${id}.${pid}.${name}`), text);
  stepEvent(w.env, { register: { runId: id, createdAt } });
}

const listArgs = (w: World) => w.calls().filter((c) => c.args[1] === "list").map((c) => c.args[c.args.indexOf("--created") + 1]);

test("the start token: read from ps, equal across reads, null for a pid that is gone", () => {
  const a = startToken(process.pid);
  assert.ok(a && a.length > 8, `token ${String(a)}`);
  assert.equal(startToken(process.pid), a);
  assert.equal(selfStart(), a);
  assert.equal(startToken(deadPid()), null);
});

test("readMarkers: facts only (dead pid, reused pid, tokenless, a file that is no marker)", () => {
  const w = mkWorld(T0, { fastGh: true });
  const dead = deadPid();
  plant(w, 11, T0 - 5, dead, JSON.stringify({ pid: dead, start: "x" }));
  plant(w, 12, T0 - 5, process.pid, JSON.stringify({ pid: process.pid, start: LONG_AGO }), "aa");
  plant(w, 13, T0 - 5, process.pid, "", "bb");
  addWaiter(w.env, 14, T0 - 5);
  writeFileSync(join(paths(w.env.dir).waiters, "notes.txt"), "x");
  const ms = readMarkers(w.env);
  const by = (id: number) => ms.find((m) => m.runId === id);
  assert.deepEqual(by(11), { runId: 11, killOk: false, recorded: "x" });
  assert.deepEqual(by(12), { runId: 12, killOk: true, recorded: LONG_AGO, now: selfStart() });
  assert.deepEqual(by(13), { runId: 13, killOk: true });
  assert.deepEqual(by(14), { runId: 14, killOk: true, recorded: selfStart(), now: selfStart() });
  assert.equal(ms.length, 4);
});

test("a dead waiter's sentinel is dropped with an orphan incident and does not widen the window", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  const sentinel = sentinelId({ branch: "ci/dead", sha: "d00d" });
  const dead = deadPid();
  plant(w, sentinel, T0 - 16_200, dead, JSON.stringify({ pid: dead, start: selfStart() })); // would pin the window 4.5 h back
  const live = 25_000_000_001;
  addWaiter(w.env, live, T0 - 30);
  const p = await pollOnce(w.env);
  assert.equal(p.ticked, true);
  assert.ok(!watched(w.env.dir).includes(sentinel), "the dead sentinel is gone");
  assert.ok(watched(w.env.dir).includes(live), "the live waiter's watch stays");
  assert.deepEqual(incidents(w.env.dir), [{ runId: sentinel, time: T0, why: "orphan" }]);
  assert.deepEqual(listArgs(w), [`>=${iso(T0 - 30)}`], "the list starts at the live watch");
});

test("a live waiter's watch is kept across ticks", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  const id = sentinelId({ branch: "ci/live", sha: "1ive" });
  addWaiter(w.env, id, T0 - 10);
  let ticks = 0;
  for (let i = 0; i < 4; i++) {
    const p = await pollOnce(w.env);
    if (p.ticked) ticks++;
    w.sim.set(p.wakeAt);
  }
  assert.ok(ticks >= 2);
  assert.deepEqual(watched(w.env.dir), [id]);
  assert.deepEqual(incidents(w.env.dir), []);
});

test("a reused pid (live process, other start time) is no waiter: its real-run watch is dropped", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [{ databaseId: 601, createdAt: T0 - 5, completeAt: T0 + 100_000 }] });
  plant(w, 601, T0 - 10, process.pid, JSON.stringify({ pid: process.pid, start: LONG_AGO }));
  const p = await pollOnce(w.env);
  assert.equal(p.stopped, undefined);
  assert.deepEqual(watched(w.env.dir), []);
  assert.deepEqual(incidents(w.env.dir), [{ runId: 601, time: T0, why: "orphan" }]);
});

test("a marker without a token: kept when its pid exists, dropped when it does not", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [{ databaseId: 701, createdAt: T0 - 5, completeAt: T0 + 100_000 }, { databaseId: 702, createdAt: T0 - 5, completeAt: T0 + 100_000 }] });
  plant(w, 701, T0 - 10, process.pid, "", "aa"); // older code wrote an empty marker
  plant(w, 702, T0 - 10, deadPid(), "", "bb");
  await pollOnce(w.env);
  assert.deepEqual(watched(w.env.dir), [701]);
  assert.deepEqual(incidents(w.env.dir), [{ runId: 702, time: T0, why: "orphan" }]);
});

test("nobody alive: the sweep leaves nothing to poll, the poller is idle and makes no gh call", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  plant(w, 801, T0 - 10, deadPid(), "");
  const p = await pollOnce(w.env);
  assert.equal(p.ticked, false);
  assert.equal(w.calls().length, 0);
  assert.deepEqual(watched(w.env.dir), []);
  assert.deepEqual(incidents(w.env.dir), [{ runId: 801, time: T0, why: "orphan" }]);
});

test("no register-before-marker gap: the marker is on disk when register is sent, and the lock is held between them", () => {
  const w = mkWorld(T0, { fastGh: true });
  const id = 25_000_000_002;
  const seen: { marker: boolean; lockHeld: boolean }[] = [];
  const nextLockHeld: boolean[] = [];
  const env = {
    ...w.env,
    core: (req: Record<string, unknown>) => {
      if (req.op === "ci.budget.next") nextLockHeld.push(tryLock(paths(w.env.dir).lock) === null); // the poller reads the markers under this lock
      if (req.op === "ci.budget.step" && JSON.stringify(req.event).includes("register")) {
        // a poller deciding now reads the waiters dir under the same lock; it cannot start while we hold it
        seen.push({ marker: readMarkers(w.env).some((m) => m.runId === id), lockHeld: tryLock(paths(w.env.dir).lock) === null });
      }
      return w.env.core(req);
    },
  };
  addWaiter(env, id, T0 - 5);
  assert.deepEqual(seen, [{ marker: true, lockHeld: true }]);
});

test("lock order, poller side: the decision (and so readMarkers) runs while the state lock is held", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [] });
  const held: boolean[] = [];
  const env = {
    ...w.env,
    core: (req: Record<string, unknown>) => {
      if (req.op === "ci.budget.next") held.push(tryLock(paths(w.env.dir).lock) === null);
      return w.env.core(req);
    },
  };
  addWaiter(env, 25_000_000_003, T0 - 5);
  await pollOnce(env);
  assert.ok(held.length >= 1 && held.every((h) => h), `lock held on every next: ${JSON.stringify(held)}`);
});

test("the start token is TZ independent: recorded under Asia/Bangkok, read by the poller under UTC, the watch is kept", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [{ databaseId: 901, createdAt: T0 - 5, completeAt: T0 + 100_000 }] });
  const wtsUrl = new URL("../src/waiters.ts", import.meta.url).href;
  const child = spawn(process.execPath, ["-e", `import(${JSON.stringify(wtsUrl)}).then((m) => { process.stdout.write(m.markerText() + "\\n"); process.stdin.resume(); });`], {
    env: { ...process.env, TZ: "Asia/Bangkok" }, stdio: ["pipe", "pipe", "inherit"],
  });
  try {
    const text = await new Promise<string>((res, rej) => {
      let buf = "";
      child.stdout.on("data", (d) => { buf += String(d); if (buf.includes("\n")) res(buf.trim()); });
      child.on("error", rej);
      child.on("exit", () => rej(new Error("child exited")));
    });
    const rec = JSON.parse(text) as { pid: number; start: string | null };
    assert.equal(rec.pid, child.pid);
    assert.ok(rec.start, "the child recorded a token");
    const saved = process.env.TZ;
    process.env.TZ = "UTC"; // the reading process
    try {
      assert.equal(startToken(rec.pid), rec.start, "same token under another TZ");
      plant(w, 901, T0 - 10, rec.pid, text);
      await pollOnce(w.env);
    } finally { if (saved === undefined) delete process.env.TZ; else process.env.TZ = saved; }
    assert.deepEqual(watched(w.env.dir), [901]);
    assert.deepEqual(incidents(w.env.dir), []);
  } finally {
    child.stdin.end();
    child.kill();
  }
});
