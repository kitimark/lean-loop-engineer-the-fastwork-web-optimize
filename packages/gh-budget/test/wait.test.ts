// `fw ci wait`: virtual-time runs with N waiters (the number of gh calls must not depend on N), the newest run of a
// branch, and real processes (one elected poller, exit codes) with the fake gh on PATH.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { join } from "node:path";
import test, { describe, it } from "node:test";
import { readFileSync } from "node:fs";
import { critIndex, waitFor, waitKind } from "../src/wait.ts";
import type { TickStatus } from "../src/poller.ts";
import { readStatus } from "../src/state.ts";
import { messageOf, parseWait } from "../src/cli.ts";
import { drive, goldenDir, mkWorld, repoRoot } from "./util.ts";

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
  assert.deepEqual(one.res, [{ code: 0, lines: ["run 111 chromium-counts success -> pass"] }]);
  assert.deepEqual(many.res, Array(20).fill(one.res[0]));
  const shape = (cs: typeof one.calls) => cs.map((c) => [c.t, c.args.slice(0, 2).join(" ")]);
  assert.deepEqual(shape(many.calls), shape(one.calls));
  assert.equal(many.calls.length, one.calls.length);
  const views = many.calls.filter((c) => c.args[1] === "view").length;
  assert.equal(views, 2, "one charged run view and one charged jobs view per run id");
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
  assert.deepEqual(f.res, [{ code: 1, lines: ["run 5 chromium-counts failure -> fail (jobs not success: work)"] }], "a fail without a reason names the jobs that did not succeed");
  const c = await wait(1, [run(6, { conclusion: "cancelled", completeAt: T0 - 1 })], { kind: "run", runId: 6 });
  assert.equal(c.res[0]!.code, 1);
  assert.equal(c.calls.filter((x) => x.args[1] === "list").length, 0);
});

test("a branch wait with --workflow follows the newest run of that workflow created after the commit", async () => {
  const runs = [
    run(10, { headBranch: "ci/x", conclusion: "cancelled", completeAt: T0 + 50 }),
    run(11, { headBranch: "ci/x", createdAt: T0 + 20, completeAt: T0 + 200, conclusion: "success" }),
    run(12, { headBranch: "ci/other", createdAt: T0 + 30, completeAt: T0 + 40, conclusion: "failure" }),
    run(9, { headBranch: "ci/x", createdAt: T0 - 500, completeAt: T0 - 400, conclusion: "failure" }), // before the commit
  ];
  const r = await wait(3, runs, { kind: "branch", branch: "ci/x", workflow: "chromium-counts", sha: "abc", since: T0 });
  assert.deepEqual(r.res, Array(3).fill({ code: 0, lines: ["run 11 chromium-counts success -> pass"] }));
  const views = r.calls.filter((c) => c.args[1] === "view");
  assert.deepEqual(views.map((c) => c.args.slice(2)), [["11", "--json", "jobs,attempt"]], "a branch wait views only the jobs of the decisive run");
});

test("a branch wait with --workflow never takes a run of a newer commit (exact sha, round-5 review)", async () => {
  const runs = [run(13, { headBranch: "ci/x", headSha: "def", createdAt: T0 + 20, completeAt: T0 + 60, conclusion: "success" })];
  const r = await wait(1, runs, { kind: "branch", branch: "ci/x", workflow: "chromium-counts", sha: "abc", since: T0 });
  assert.notEqual(r.res[0]?.code, 0, "a pass on def is not a pass on abc");
});

// ci-own-trigger round 2: GitHub calls a run whose jobs were all skipped `success`; the verdict is fwcore's
// `ci.verdict` (lean/Fw/Ci/Verdict.lean `skipped_never_pass`, `pass_iff`), so such a run is `not-run`, exit 4.
const skipGuard = [{ name: "guard", conclusion: "skipped", steps: [] }, { name: "work", conclusion: "skipped" }];
const decidedSkip = [
  { name: "guard", conclusion: "success", steps: [{ name: "decision: run", conclusion: "skipped" }, { name: "decision: skip: no input of difftest changed", conclusion: "success" }] },
  { name: "work", conclusion: "skipped" },
];

test("not run: a guard-skipped run (GitHub: success) is exit 4 with the guard reason, never a pass", async () => {
  const s = await wait(1, [run(7, { jobs: skipGuard })], { kind: "run", runId: 7 });
  assert.deepEqual(s.res, [{ code: 4, lines: ["run 7 chromium-counts success -> not-run (unwanted: guard if: the head commit does not ask for this lane)"] }]);
  const d = await wait(1, [run(8, { jobs: decidedSkip })], { kind: "run", runId: 8 });
  assert.deepEqual(d.res, [{ code: 4, lines: ["run 8 chromium-counts success -> not-run (no input of difftest changed)"] }]);
});

test("verdict: a run passes only if some non-guard job ran and every job that ran succeeded", async () => {
  const guard = { name: "guard", conclusion: "success", steps: [{ name: "decision: run", conclusion: "success" }] };
  const none = await wait(1, [run(13, { jobs: [guard, { name: "a", conclusion: "skipped" }] })], { kind: "run", runId: 13 });
  assert.equal(none.res[0]!.code, 4);
  const mixed = await wait(1, [run(14, { jobs: [guard, { name: "a", conclusion: "success" }, { name: "b", conclusion: "skipped" }] })], { kind: "run", runId: 14 });
  assert.equal(mixed.res[0]!.code, 0);
  const bad = await wait(1, [run(15, { jobs: [guard, { name: "a", conclusion: "success" }, { name: "b", conclusion: "failure" }] })], { kind: "run", runId: 15 });
  assert.equal(bad.res[0]!.code, 1);
  const g = await wait(1, [run(16, { conclusion: "failure", jobs: [{ ...guard, conclusion: "failure" }, { name: "a", conclusion: "skipped" }] })], { kind: "run", runId: 16 });
  assert.equal(g.res[0]!.code, 1, "a failed guard is a failure, not a skip");
  const old = await wait(1, [run(17, { jobs: [{ name: "build", conclusion: "success" }] })], { kind: "run", runId: 17 });
  assert.equal(old.res[0]!.code, 0, "a workflow without a guard job (a branch before ci-trigger-lean) passes on its jobs");
});

// ci-own-trigger round 3: `--branch` without `--workflow` waits for every lane the commit requests (fwcore `ci.required`)
// and passes only when each has a pass run for that sha (Lean `combine_requested_never_pass`).
test("lanes mode: a requested lane that did not run is never a pass, though another lane passed", async () => {
  const runs = [
    run(20, { headBranch: "ci/x", workflowName: "wktr", jobs: decidedSkip }),
    run(21, { headBranch: "ci/x", workflowName: "lean", createdAt: T0 + 5 }),
    run(22, { headBranch: "ci/x", workflowName: "difftest", jobs: skipGuard }), // not requested: ignored
    run(23, { headBranch: "ci/x", workflowName: "wktr", headSha: "old", createdAt: T0 + 9 }), // another commit: ignored
  ];
  const asked = await wait(1, runs, { kind: "branch", branch: "ci/x", sha: "abc", since: T0, msg: "fix [ci:wktr]" });
  assert.equal(asked.res[0]!.code, 4, asked.res[0]!.lines.join("\n"));
  assert.ok(asked.res[0]!.lines.includes("run 20 wktr success -> not-run (no input of difftest changed)"), asked.res[0]!.lines.join("\n"));
  assert.ok(asked.res[0]!.lines.includes("lanes lean,wktr -> not-run"), asked.res[0]!.lines.join("\n"));
  const leanOnly = await wait(1, runs, { kind: "branch", branch: "ci/x", sha: "abc", since: T0, msg: "fix" });
  assert.equal(leanOnly.res[0]!.code, 0, leanOnly.res[0]!.lines.join("\n"));
  const one = await wait(1, runs, { kind: "branch", branch: "ci/x", workflow: "wktr", sha: "abc", since: T0 });
  assert.equal(one.res[0]!.code, 4, "--workflow takes only runs of the exact commit: run 20 (abc, skipped) decides, never run 23 (another commit)");
});

test("lanes mode: a heavy job stopped at its tip re-check is stale; a requested lane with no run is missing", async () => {
  const guard = { name: "guard", conclusion: "success", steps: [{ name: "decision: run", conclusion: "success" }] };
  const staleJob = { name: "work", conclusion: "failure", steps: [{ name: "tip re-check", conclusion: "success" }, { name: "stale: a newer push is the branch tip", conclusion: "failure" }] };
  const st = await wait(1, [run(30, { headBranch: "ci/x", workflowName: "lean", conclusion: "failure", jobs: [guard, staleJob] })],
    { kind: "branch", branch: "ci/x", sha: "abc", since: T0, msg: "a" });
  assert.equal(st.res[0]!.code, 4, st.res[0]!.lines.join("\n"));
  assert.ok(st.res[0]!.lines.some((l) => l.startsWith("run 30 lean failure -> not-run (stale: ")), st.res[0]!.lines.join("\n"));
  const miss = await wait(1, [run(31, { headBranch: "ci/x", workflowName: "lean" })],
    { kind: "branch", branch: "ci/x", sha: "abc", since: T0, msg: "[ci:wktr]" });
  assert.equal(miss.res[0]!.code, 4, miss.res[0]!.lines.join("\n"));
  assert.ok(miss.res[0]!.lines.some((l) => l.startsWith("lane wktr no run -> missing")), miss.res[0]!.lines.join("\n"));
});

// ci-own-trigger round 4: a commit whose message cannot be read is an unknown request; the wait never passes, even
// with a lean pass on that sha (Lean `unknown_request_never_pass`).
test("lanes mode: an unknown request (message unreadable) is not-run at once, though lean passed", async () => {
  const runs = [run(40, { headBranch: "ci/x", workflowName: "lean" })];
  for (const msg of [null, undefined]) {
    const t = { kind: "branch" as const, branch: "ci/x", sha: "abc", since: T0, ...(msg === null ? { msg } : {}) };
    const r = await wait(1, runs, t);
    assert.equal(r.res[0]!.code, 4, r.res[0]!.lines.join("\n"));
    assert.ok(r.res[0]!.lines.some((l) => l.startsWith("lanes ? -> not-run (unknown request")), r.res[0]!.lines.join("\n"));
  }
});

// ci-own-trigger round 5: lean skipped as unchanged never stands in for its pass (the round-4 review probe: [ci:wktr],
// lean `unchanged`, wktr pass); Lean `wait_needs_default_pass`.
test("lanes mode: lean skipped as unchanged is not a pass, though the requested lane passed", async () => {
  const leanUnchanged = [
    { name: "guard", conclusion: "success", steps: [{ name: "decision: run", conclusion: "skipped" }, { name: "decision: skip: unchanged: none of the 2 file(s) match", conclusion: "success" }] },
    { name: "lean", conclusion: "skipped" },
  ];
  const runs = [
    run(50, { headBranch: "ci/x", workflowName: "lean", jobs: leanUnchanged }),
    run(51, { headBranch: "ci/x", workflowName: "wktr", createdAt: T0 + 5 }),
  ];
  const r = await wait(1, runs, { kind: "branch", branch: "ci/x", sha: "abc", since: T0, msg: "[ci:wktr]" });
  assert.equal(r.res[0]!.code, 4, r.res[0]!.lines.join("\n"));
  assert.ok(r.res[0]!.lines.includes("lanes lean,wktr -> not-run"), r.res[0]!.lines.join("\n"));
});

test("parseWait: the message comes from git only; a sha not in the local object store gives an unknown message", () => {
  const p = parseWait(["--branch", "ci/x", "--sha", "deadbeef1", "--since", "100"], repoRoot);
  assert.equal(p.target.kind === "branch" ? p.target.msg : "run", null);
  assert.equal(messageOf(repoRoot, "deadbeef1"), null);
  assert.equal(typeof messageOf(repoRoot, "HEAD"), "string");
  assert.throws(() => parseWait(["--branch", "ci/x", "--sha", "deadbeef1", "--since", "100", "--msg", "x [ci:wktr]"], repoRoot), /unexpected argument --msg/);
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

// task ci-wait-lag: the verdict is keyed on the attempt (Lean `Fw.Ci.Attempt`). After `gh run rerun --failed` the run id
// is the same: the list still shows attempt 1 finished while the jobs view already shows attempt 2 (run 39363764375).
test("rerun: a finished row of attempt 1 never gives the verdict while the jobs view shows attempt 2", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(41, { conclusion: "failure", attempt: 1, viewAttempt: 2 })] });
  const [res] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 41 }, { timeoutS: 300 })]);
  assert.equal(res!.code, 3, res!.lines.join("\n"));
  assert.match(res!.lines[0]!, /timed out/);
  const views = w.calls().filter((c) => c.args[1] === "view" && c.args.includes("jobs,attempt"));
  assert.equal(views.length, 1, "one jobs view, not one per loop");
});

test("rerun: jobs cached at attempt 1 are not reused once the row is attempt 2", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(42, { conclusion: "failure", attempt: 1 })] });
  const [first] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 42 }, { timeoutS: 300 })]);
  assert.equal(first!.code, 1);
  w.config({ start: T0, listCost: 2, runs: [run(42, { conclusion: "success", attempt: 2 })] });
  await drive(w.sim, [w.env.sleepUntil(w.env.now() + 120)]); // past the window in which a finished row is shared
  const [second] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 42 }, { timeoutS: 300 })]);
  assert.equal(second!.code, 0, second!.lines.join("\n"));
  assert.equal(w.calls().filter((c) => c.args.includes("jobs,attempt")).length, 2, "attempt 2 is read again");
});

test("rerun: the jobs of a running attempt seen as stale are not cached as the verdict of the finished attempt", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(44, { conclusion: "failure", attempt: 1, viewAttempt: 2 })] });
  const [first] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 44 }, { timeoutS: 300 })]);
  assert.equal(first!.code, 3, first!.lines.join("\n"));
  w.config({ start: T0, listCost: 2, runs: [run(44, { conclusion: "success", attempt: 2 })] });
  await drive(w.sim, [w.env.sleepUntil(w.env.now() + 120)]);
  const [second] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 44 }, { timeoutS: 300 })]);
  assert.equal(second!.code, 0, second!.lines.join("\n"));
  assert.equal(w.calls().filter((c) => c.args.includes("jobs,attempt")).length, 2, "attempt 2 is read by a second jobs view");
});

// task macos-telemetry: a job without a conclusion right after the finish is GitHub's lag (run 39629760037 printed `success -> fail`
// because one of 10 matrix jobs was read as `""` and the facts were cached for good). Lean `Fw.Ci.Attempt.jobsSettled` decides.
const openJobs = (open: number) => [{ name: "guard", conclusion: "success" }, ...Array.from({ length: 4 }, (_, i) => ({ name: `m${i}`, conclusion: i < open ? null : "success" }))];

test("an open job conclusion right after the finish is read again, and only the settled view is cached", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(61, { jobs: openJobs(1) })] });
  const base = w.env.exec!;
  let views = 0;
  const env = { ...w.env, exec: (args: string[]) => {
    if (args.includes("jobs,attempt") && ++views === 3) w.config({ start: T0, listCost: 2, runs: [run(61, { jobs: openJobs(0) })] }); // GitHub fills the conclusion
    return base(args);
  } };
  const [res] = await drive(w.sim, [waitFor(env, { kind: "run", runId: 61 }, { timeoutS: 3600 })]);
  assert.deepEqual(res, { code: 0, lines: ["run 61 chromium-counts success -> pass"] });
  assert.equal(w.calls().filter((c) => c.args.includes("jobs,attempt")).length, 3, "two views with an open job, one settled");
  const [again] = await drive(w.sim, [waitFor(env, { kind: "run", runId: 61 }, { timeoutS: 3600 })]);
  assert.equal(again!.code, 0);
  assert.equal(w.calls().filter((c) => c.args.includes("jobs,attempt")).length, 3, "the settled facts were cached");
});

test("a job that stays open is read at most 7 times, the result is not cached, and the failing job is named", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(62, { jobs: openJobs(1) })] });
  const [res] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 62 }, { timeoutS: 3600 })]);
  assert.equal(res!.code, 1);
  assert.match(res!.lines[0]!, /-> fail \(jobs not success: m0\)$/);
  const n = w.calls().filter((c) => c.args.includes("jobs,attempt")).length;
  assert.equal(n, 7, "the first view and 6 re-reads");
  await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 62 }, { timeoutS: 3600 })]);
  assert.ok(w.calls().filter((c) => c.args.includes("jobs,attempt")).length > n, "an unsettled view is read again by the next wait");
});

test("an open job long after the finish is a fact: one view, cached", async () => {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs: [run(63, { completeAt: T0 - 1000, jobs: openJobs(1) })] });
  const [res] = await drive(w.sim, [waitFor(w.env, { kind: "run", runId: 63 }, { timeoutS: 3600 })]);
  assert.equal(res!.code, 1);
  assert.equal(w.calls().filter((c) => c.args.includes("jobs,attempt")).length, 1);
});

// task ci-wait-lag: the kind of a wait and its critical run replay the Lean golden (Fw.Ci.Lag.kind, Fw.Ci.Lag.crit)
test("waitKind and critIndex replay golden ci-budget/lag-kind.jsonl", () => {
  const f = join(goldenDir, "lag-kind.jsonl");
  const cases = readFileSync(f, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as Record<string, unknown>);
  assert.ok(cases.length >= 10);
  for (const c of cases) {
    if (c.op === "kind") assert.equal(waitKind(c.lanesMissing as boolean, c.tick as number | undefined, c.reg as number), c.kind, String(c.name));
    else assert.equal(critIndex(c.upds as number[]), c.crit ?? null, String(c.name));
  }
});

async function phased(N: number, runs: Record<string, unknown>[], target: Parameters<typeof waitFor>[1], timeoutS = 3600, cfg: Record<string, unknown> = {}, others: Parameters<typeof waitFor>[1][] = []) {
  const w = mkWorld(T0, { fastGh: true });
  w.config({ start: T0, listCost: 2, runs, ...cfg });
  const got: import("../src/wait.ts").WaitPhases[] = [];
  const targets = [...Array.from({ length: N - others.length }, () => target), ...others];
  const res = await drive(w.sim, targets.map((x) => waitFor(w.env, x, { timeoutS, phases: (p) => got.push(p) })));
  return { res, got, calls: w.calls(), w };
}

test("phases: a wait on a running run records run, update, tick, read, view, verdict and return in order", async () => {
  const r = await phased(3, [run(70)], { kind: "run", runId: 70 });
  assert.equal(r.got.length, 3);
  assert.equal(r.got.filter((p) => p.holder).length, 1, "one waiter runs the poller");
  for (const p of r.got) {
    assert.equal(p.how, "done");
    assert.deepEqual(p.runIds, [70]);
    const t = [p.regMs, p.tickMs!, p.readMs!, p.viewEndMs!, p.doneMs!, p.retMs];
    assert.ok(t.every((x) => typeof x === "number"), JSON.stringify(p));
    assert.ok(t.every((x, i) => i === 0 || x >= t[i - 1]!), `phases ordered: ${t.join(",")}`);
    assert.ok(p.tickMs! >= p.updMs!, "the tick that showed the run completed is not before its updatedAt");
    assert.equal(p.updMs, (T0 + 100) * 1000);
  }
  assert.equal(r.got.filter((p) => p.views === 1).length + r.got.filter((p) => p.cached === 1).length, 3, "each waiter either fetched the jobs or read the cache");
});

test("phases: the instrumentation adds no gh call, whatever the waiter count", async () => {
  const plain = await wait(5, [run(71)], { kind: "run", runId: 71 });
  const withPh = await phased(5, [run(71)], { kind: "run", runId: 71 });
  assert.deepEqual(withPh.calls.map((c) => [c.t, c.args.slice(0, 3).join(" ")]), plain.calls.map((c) => [c.t, c.args.slice(0, 3).join(" ")]));
});

test("phases: an already finished run is `already` with no tick, a timeout is `timeout`", async () => {
  const a = await phased(1, [run(72, { completeAt: T0 - 1 })], { kind: "run", runId: 72 });
  assert.equal(a.got[0]!.how, "already");
  assert.equal(a.got[0]!.tickMs, undefined);
  const t = await phased(1, [run(73, { completeAt: 1e12 })], { kind: "run", runId: 73 }, 120);
  assert.equal(t.res[0]!.code, 3);
  assert.equal(t.got[0]!.how, "timeout");
  assert.equal(t.got[0]!.doneMs, undefined);
});

test("phases: the tick before the finish is the previous tick (the list still showed the run unfinished)", async () => {
  const r = await phased(1, [run(74, { completeAt: T0 + 100 })], { kind: "run", runId: 74 });
  const p = r.got[0]!;
  assert.equal(p.how, "done");
  assert.ok(p.prevTickMs !== undefined && p.prevTickMs < p.updMs!, "previous tick precedes the update");
  assert.ok(p.tickMs! > p.prevTickMs!);
});

test("phases: the interval and retryUntil each tick wrote into the status give pollS, retryUntilS and prevPollS", async () => {
  const r = await phased(1, [run(75, { completeAt: T0 + 100 })], { kind: "run", runId: 75 });
  const p = r.got[0]!;
  assert.equal(p.how, "done");
  assert.equal(p.pollS, 10, "Budget.interval of the default limits on a fresh state");
  assert.equal(p.retryUntilS, 0, "no failure backoff");
  assert.equal(p.prevPollS, 10, "the earlier tick's interval");
  const st = readStatus(r.w.stateDir) as TickStatus;
  assert.equal(st.tickAt, p.tickMs! / 1000);
  assert.equal(st.interval, 10);
  assert.equal(st.retryUntil, 0);
  const a = await phased(1, [run(76, { completeAt: T0 - 1 })], { kind: "run", runId: 76 });
  assert.equal(a.got[0]!.pollS, undefined, "an already finished run has no deciding tick");
});

test("phases: a failed tick between the two ticks shows as a retryUntil past the earlier tick, and the gap fits interval plus backoff", async () => {
  const r = await phased(1, [run(77, { completeAt: T0 + 100 })], { kind: "run", runId: 77 }, 3600, { overrides: [{ at: T0 + 85, lines: ["HTTP/2.0 403 Forbidden"] }] });
  const p = r.got[0]!;
  assert.equal(p.how, "done");
  assert.ok(p.prevTickMs !== undefined && p.retryUntilS !== undefined && p.pollS !== undefined, JSON.stringify(p));
  assert.ok(p.retryUntilS * 1000 > p.prevTickMs, `backoff past the earlier tick: ${JSON.stringify(p)}`);
  assert.ok(p.tickMs! - p.prevTickMs > p.pollS * 1000, "the backoff spaced the ticks wider than the interval");
  assert.ok(p.tickMs! - p.prevTickMs <= p.pollS * 1000 + (p.retryUntilS * 1000 - p.prevTickMs), "the gap fits interval plus backoff");
});

test("phases: a failed call after the deciding tick raises the state's retryUntil, not the retryUntilS a later reader records", async () => {
  const ok = ["HTTP/2.0 200 OK", "X-Ratelimit-Remaining: 4900", `X-Ratelimit-Reset: ${T0 + 3600}`, "X-Ratelimit-Resource: core"];
  const r = await phased(2, [run(78, { completeAt: T0 + 100 }), run(79, { completeAt: T0 + 100 })], { kind: "run", runId: 78 }, 3600,
    { overrides: [{ at: T0 + 100, lines: ok }, { at: T0 + 100, lines: ["HTTP/2.0 403 Forbidden", "Retry-After: 600"] }] }, [{ kind: "run", runId: 79 }]);
  const late = r.got.find((p) => !p.holder)!;
  assert.ok(late.readMs! > late.tickMs!, `the reader came after the deciding tick: ${JSON.stringify(late)}`);
  assert.equal(r.calls.find((c) => c.t === T0 + 100 && c.args[1] === "view")?.refused, true, "the holder's view after the tick was refused");
  assert.equal(late.retryUntilS, 0, "the retryUntil when the deciding tick was issued");
  assert.equal(late.how, "done");
});

test("phases: an interval that shrank between the two ticks is recorded at both, and the gap fits the larger one", async () => {
  const r = await phased(1, [run(80, { completeAt: T0 + 100 })], { kind: "run", runId: 80 }, 3600, { start: T0 - 3300, drains: [{ at: T0 + 45, remaining: 504 }] });
  const p = r.got[0]!;
  assert.equal(p.how, "done");
  assert.deepEqual([p.prevTickMs, p.tickMs, p.prevPollS, p.pollS, p.retryUntilS], [(T0 + 50) * 1000, (T0 + 300) * 1000, 250, 10, 0]);
  assert.ok(p.tickMs! - p.prevTickMs! > p.pollS! * 1000, "the deciding tick's interval alone would cap the gap");
  assert.ok(p.tickMs! - p.prevTickMs! <= Math.max(p.pollS!, p.prevPollS!) * 1000, "the earlier tick's interval explains it");
});

test("phases: a tick whose full list raised the pages records the interval after its pages event, the gap it scheduled", async () => {
  const runs = [...Array.from({ length: 100 }, (_, i) => run(300 + i, { completeAt: 1e12 })), run(400, { completeAt: T0 + 5 })];
  const r = await phased(1, runs, { kind: "run", runId: 400 });
  const p = r.got[0]!;
  assert.equal(p.how, "done");
  assert.deepEqual([p.prevTickMs, p.tickMs, p.prevPollS, p.pollS], [T0 * 1000, (T0 + 12) * 1000, 12, 12], JSON.stringify(p));
  assert.equal(p.tickMs! - p.prevTickMs!, p.prevPollS! * 1000, "the earlier tick's interval is the gap: 2 pages cost 4, the minute share spaces ticks 12 s apart");
  const tick1 = r.calls.find((c) => c.args[1] === "list")!;
  assert.equal(tick1.args[tick1.args.indexOf("--limit") + 1], "100", "the first tick read one page and came back full");
});

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
  it("process: 20 `ci wait` on a finished run make 2 gh calls (run, jobs) and exit 0", { timeout: 120_000 }, async () => {
    const w = mkWorld(Math.floor(Date.now() / 1000) - 600, { realClock: true });
    const now = Math.floor(Date.now() / 1000);
    w.config({ start: now - 600, listCost: 2, runs: [run(31, { createdAt: now - 300, completeAt: now - 100 })] });
    const rs = await Promise.all(Array.from({ length: 20 }, () => cli(w, ["wait", "31"])));
    for (const r of rs) assert.deepEqual([r.code, r.out.trim()], [0, "run 31 chromium-counts success -> pass"]);
    assert.deepEqual(w.calls().map((c) => c.args.slice(1, 3).concat(c.args.includes("jobs,attempt") ? ["jobs"] : [])), [["view", "31"], ["view", "31", "jobs"]]);
  });

  it("process: 3 `ci wait` on a running run elect one poller: 1 view + 1 tick, then exit 3 on timeout", { timeout: 120_000 }, async () => {
    const w = mkWorld(Math.floor(Date.now() / 1000) - 600, { realClock: true });
    const now = Math.floor(Date.now() / 1000);
    w.config({ start: now - 600, listCost: 2, runs: [run(32, { createdAt: now - 300, completeAt: 1e12 })] });
    const rs = await Promise.all(Array.from({ length: 3 }, () => cli(w, ["wait", "32", "--timeout", "6"])));
    for (const r of rs) assert.equal(r.code, 3, r.out);
    const cs = w.calls().map((c) => c.args[1]);
    // one elected poller: one view, then at most one list tick before the 6 s timeout (none when the host is too
    // loaded to reach the first tick in time); never a second view or a second poller's list
    assert.ok(cs.length === 1 || cs.length === 2, cs.join(","));
    assert.deepEqual(cs, ["view", "list"].slice(0, cs.length));
  });
});

test("process: usage errors are exit 64", async () => {
  const w = mkWorld(T0);
  assert.equal((await cli(w, ["wait"])).code, 64);
  assert.equal((await cli(w, ["wait", "1", "--branch", "x"])).code, 64);
  assert.equal(w.calls().length, 0);
});
