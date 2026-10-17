// `fw ci wait`: virtual-time runs with N waiters (the number of gh calls must not depend on N), the newest run of a
// branch, and real processes (one elected poller, exit codes) with the fake gh on PATH.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { join } from "node:path";
import test, { describe, it } from "node:test";
import { waitFor } from "../src/wait.ts";
import { drive, mkWorld, repoRoot } from "./util.ts";

const T0 = 1_800_000_000;
const run = (databaseId: number, extra: Record<string, unknown> = {}) => ({ databaseId, createdAt: T0, completeAt: T0 + 100, conclusion: "success", ...extra });

async function wait(N: number, runs: Record<string, unknown>[], target: Parameters<typeof waitFor>[1]) {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs });
  const res = await drive(w.sim, Array.from({ length: N }, () => waitFor(w.env, target, { timeoutS: 3600 })));
  return { res, calls: w.calls(), w };
}

test("20 waiters on one run make exactly the gh calls of 1 waiter", async () => {
  const one = await wait(1, [run(111)], { kind: "run", runId: 111 });
  const many = await wait(20, [run(111)], { kind: "run", runId: 111 });
  assert.deepEqual(one.res, [{ code: 0, lines: ["run 111 chromium-counts success"] }]);
  assert.deepEqual(many.res, Array(20).fill(one.res[0]));
  const shape = (cs: typeof one.calls) => cs.map((c) => [c.t, c.args.slice(0, 2).join(" ")]);
  assert.deepEqual(shape(many.calls), shape(one.calls));
  assert.equal(many.calls.length, one.calls.length);
  const views = many.calls.filter((c) => c.args[1] === "view").length;
  assert.equal(views, 1, "one charged view per run id");
  console.log(`# gh calls: 1 waiter ${one.calls.length}, 20 waiters ${many.calls.length} (views ${views}, ticks ${many.calls.length - views})`);
});

test("20 waiters on 20 distinct runs: the ticks are those of 1 waiter (one list covers every run)", async () => {
  const runs = Array.from({ length: 20 }, (_, i) => run(200 + i));
  const one = await wait(1, runs, { kind: "run", runId: 200 });
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs });
  await drive(w.sim, runs.map((r) => waitFor(w.env, { kind: "run", runId: r.databaseId as number }, { timeoutS: 3600 })));
  const ticks = (cs: typeof one.calls) => cs.filter((c) => c.args[1] === "list").length;
  assert.equal(ticks(w.calls()), ticks(one.calls));
});

test("exit codes: failure is 1, cancelled is 1, an already finished run needs no tick", async () => {
  const f = await wait(1, [run(5, { conclusion: "failure" })], { kind: "run", runId: 5 });
  assert.deepEqual(f.res, [{ code: 1, lines: ["run 5 chromium-counts failure"] }]);
  const c = await wait(1, [run(6, { conclusion: "cancelled", completeAt: T0 - 1 })], { kind: "run", runId: 6 });
  assert.equal(c.res[0]!.code, 1);
  assert.equal(c.calls.filter((x) => x.args[1] === "list").length, 0);
});

test("a branch follows the newest run: the superseded one is cancelled, the newer one decides", async () => {
  const runs = [
    run(10, { headBranch: "ci/x", conclusion: "cancelled", completeAt: T0 + 50 }),
    run(11, { headBranch: "ci/x", createdAt: T0 + 20, completeAt: T0 + 200, conclusion: "success" }),
    run(12, { headBranch: "ci/other", createdAt: T0 + 30, completeAt: T0 + 40, conclusion: "failure" }),
    run(9, { headBranch: "ci/x", createdAt: T0 - 500, completeAt: T0 - 400, conclusion: "failure" }), // before the commit
  ];
  const r = await wait(3, runs, { kind: "branch", branch: "ci/x", workflow: "chromium-counts", sha: "abc", since: T0 });
  assert.deepEqual(r.res, Array(3).fill({ code: 0, lines: ["run 11 chromium-counts success"] }));
  assert.equal(r.calls.filter((c) => c.args[1] === "view").length, 0, "a branch wait needs no view");
});

test("timeout is exit 3 and the state keeps no watcher behind", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(7, { completeAt: 1e12 })] });
  const [res] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 7 }, { timeoutS: 300 })]);
  assert.equal(res!.code, 3);
  assert.match(res!.lines[0]!, /timed out/);
  const st = JSON.parse((await import("node:fs")).readFileSync(join(w.stateDir, "state.json"), "utf8")) as { watched: unknown[] };
  assert.deepEqual(st.watched, []);
});

// ---- real processes, real clock ----------------------------------------------------------------------------------------
function cli(w: ReturnType<typeof mkWorld>, args: string[]): Promise<{ code: number | null; out: string }> {
  return new Promise((res) => {
    const p = spawn(process.execPath, [join(repoRoot, "packages/gh-budget/src/cli.ts"), ...args], {
      cwd: repoRoot, env: { ...process.env, PATH: `${w.bin}:${process.env.PATH}`, FW_GH_BUDGET_DIR: w.stateDir, FAKE_GH_DIR: w.fakeDir },
    });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (out += d));
    p.on("close", (code) => res({ code, out }));
  });
}

// the two real-clock tests each have their own world (own state dir, own fake gh dir, `cli` passes both in the
// child's environment), so they run side by side: the serial sum of their real waits was the file's critical path
describe("real processes, real clock", { concurrency: true }, () => {
  it("process: 20 `ci wait` on a finished run make 1 gh call and exit 0", { timeout: 120_000 }, async () => {
    const w = mkWorld(Math.floor(Date.now() / 1000) - 600, { realClock: true });
    const now = Math.floor(Date.now() / 1000);
    w.config({ start: now - 600, listCost: 2, runs: [run(31, { createdAt: now - 300, completeAt: now - 100 })] });
    const rs = await Promise.all(Array.from({ length: 20 }, () => cli(w, ["wait", "31"])));
    for (const r of rs) assert.deepEqual([r.code, r.out.trim()], [0, "run 31 chromium-counts success"]);
    assert.equal(w.calls().length, 1);
  });

  it("process: 3 `ci wait` on a running run elect one poller: 1 view + 1 tick, then exit 3 on timeout", { timeout: 120_000 }, async () => {
    const w = mkWorld(Math.floor(Date.now() / 1000) - 600, { realClock: true });
    const now = Math.floor(Date.now() / 1000);
    w.config({ start: now - 600, listCost: 2, runs: [run(32, { createdAt: now - 300, completeAt: 1e12 })] });
    const rs = await Promise.all(Array.from({ length: 3 }, () => cli(w, ["wait", "32", "--timeout", "6"])));
    for (const r of rs) assert.equal(r.code, 3, r.out);
    const cs = w.calls();
    assert.deepEqual(cs.map((c) => c.args[1]), ["view", "list"]);
  });
});

test("process: usage errors are exit 64", async () => {
  const w = mkWorld(T0);
  assert.equal((await cli(w, ["wait"])).code, 64);
  assert.equal((await cli(w, ["wait", "1", "--branch", "x"])).code, 64);
  assert.equal(w.calls().length, 0);
});
