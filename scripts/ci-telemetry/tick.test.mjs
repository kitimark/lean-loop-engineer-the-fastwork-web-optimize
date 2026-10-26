// node --test scripts/ci-telemetry/   The upload tick: its stand-ins against the Lean golden, and a real launch / wait / await run.
import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { TICK_STEPS, PERIODIC_TICKS, awaitRun, freshPasses, launch, periodicAtMin, tickPeriodMin, tickPeriodS, waitTick, wakeWhy } from "./tick.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");
const golden = readFileSync(join(root, "packages/contracts/golden/ci/telemetry.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l)).filter((g) => g.request.upload !== undefined);

const standIn = (rq) => {
  if (rq.upload === "period") return { periodMin: tickPeriodMin(rq.stepMin), periodS: tickPeriodS(rq.stepMin), tickSteps: TICK_STEPS, atMin: periodicAtMin(rq.stepMin) };
  if (rq.upload === "wake") {
    const why = wakeWhy(rq.elapsedS, rq.sinceS, rq.periodS, rq.stepS, rq.fresh, rq.done);
    return { wake: why !== null, why: why ?? "none" };
  }
  return { error: `unknown upload ${rq.upload}` };
};

test("the golden has period and wake cases for every branch of the wake rule", () => {
  assert.ok(golden.length >= 12);
  const whys = new Set(golden.filter((g) => g.request.upload === "wake").map((g) => g.response.why));
  assert.deepEqual([...whys].sort(), ["deadline", "done", "none", "pass", "period"]);
});

test("the TS stand-ins of Lean tickPeriodMin, tickPeriodS and wakeWhy give the Lean reply on every golden case", () => {
  for (const g of golden) {
    if (g.request.upload === "nope") { assert.match(g.response.error, /unknown upload/); continue; }
    assert.deepEqual(standIn(g.request), g.response, g.name);
  }
});

test("the Lean binary gives the golden reply (when built)", { skip: !existsSync(fwcore) }, () => {
  for (const g of golden) {
    const r = spawnSync(fwcore, [], { input: JSON.stringify({ id: 1, ...g.request }) + "\n", encoding: "utf8" });
    const { id, ...rest } = JSON.parse(r.stdout.trim().split("\n")[0]);
    assert.deepEqual(rest, g.response, g.name);
  }
});

test("a one-session job has four periodic ticks inside its 35-minute step, and the first lands before the 53-minute job cap", () => {
  assert.equal(PERIODIC_TICKS, 4);
  assert.deepEqual(periodicAtMin(35), [7, 14, 21, 28]);
  const setupMin = 8, jobMin = 53, uploadMin = 2;
  assert.ok(setupMin + tickPeriodMin(35) + uploadMin < jobMin);
});

const scratch = () => mkdtempSync(join(tmpdir(), "fw-tick-"));
const clock = (start = 1_000_000) => { let t = start; return { now: () => t, sleep: async (ms) => { t += ms; }, at: (v) => { t = v; } }; };

test("freshPasses lists only unstaged .pass-N.part files and never a temp file", () => {
  const out = scratch();
  for (const f of ["v1-session-1.pass-1.part", "v1-session-1.pass-2.part", "v1-session-1.pass-2.part.tmp", "v1-session-1.json", "v1-session-1.log"]) writeFileSync(join(out, f), "x");
  assert.deepEqual(freshPasses(out, []), ["v1-session-1.pass-1.part", "v1-session-1.pass-2.part"]);
  assert.deepEqual(freshPasses(out, ["v1-session-1.pass-1.part"]), ["v1-session-1.pass-2.part"]);
  rmSync(out, { recursive: true });
});

test("waitTick: wakes on the period, stages the probes, then wakes on a new pass file with only that file, then on the end", async () => {
  const dir = scratch(), out = scratch(), probes = join(scratch(), "probes.jsonl");
  const c = clock();
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "t0"), String(c.now()));
  writeFileSync(probes, '{"atMs":1}\n');
  const base = { dir, out, stepS: 2100, periodS: 420, pollMs: 5000, probes, now: c.now, sleep: c.sleep, write: () => {} };

  const a = await waitTick(1, base);
  assert.equal(a.why, "period");
  assert.deepEqual(a.files, ["probes.jsonl"]);
  assert.ok(c.now() - 1_000_000 >= 420_000 && c.now() - 1_000_000 < 430_000);

  writeFileSync(join(out, "v1-session-1.pass-1.part"), '{"pass":1}');
  const b = await waitTick(2, base);
  assert.equal(b.why, "pass");
  assert.deepEqual(b.files, ["v1-session-1.pass-1.part", "probes.jsonl"]);
  assert.ok(existsSync(join(dir, "tick/2/v1-session-1.pass-1.part")));
  assert.equal(JSON.parse(readFileSync(join(dir, "tick/2/tick.json"), "utf8")).why, "pass");

  writeFileSync(join(out, "v1-session-1.pass-2.part"), '{"pass":2}');
  writeFileSync(join(dir, "exit"), "0");
  const d = await waitTick(3, base);
  assert.equal(d.why, "done");
  assert.deepEqual(d.files, ["v1-session-1.pass-2.part", "probes.jsonl"]);

  const e = await waitTick(4, base);
  assert.equal(e.why, "done");
  assert.equal(e.stage, false, "a second tick after the end has nothing new");
  assert.deepEqual(readdirSync(join(dir, "tick")).sort(), ["1", "2", "3"]);

});

test("waitTick: the step bound wakes a tick that nothing else woke", async () => {
  const dir = scratch(), out = scratch();
  const c = clock();
  writeFileSync(join(dir, "t0"), String(c.now()));
  const r = await waitTick(1, { dir, out, stepS: 100, periodS: 100000, pollMs: 10000, now: c.now, sleep: c.sleep, write: () => {} });
  assert.equal(r.why, "deadline");
  assert.equal(r.stage, true, "the first tick at the step bound uploads the last probes");
  const again = await waitTick(2, { dir, out, stepS: 100, periodS: 100000, pollMs: 10000, now: c.now, sleep: c.sleep, write: () => {} });
  assert.equal(again.stage, false, "later ticks at the bound upload nothing");
});

test("waitTick: no run started stages nothing", async () => {
  const r = await waitTick(1, { dir: scratch(), out: scratch(), stepS: 10, periodS: 5, now: () => 0, sleep: async () => {}, write: () => {} });
  assert.equal(r.why, "no-run");
  assert.equal(r.stage, false);
});

test("launch runs the command in the background, records its exit code and console, and awaitRun returns that code", async () => {
  const dir = scratch();
  const pid = launch(dir, ["sh", "-c", "echo hello; echo oops >&2; exit 3"]);
  assert.ok(pid > 0);
  const lines = [];
  const code = await awaitRun({ dir, stepS: 60, pollMs: 50, write: (s) => lines.push(s) });
  assert.equal(code, 3);
  const text = lines.join("");
  assert.match(text, /hello/);
  assert.match(text, /oops/);
});

test("awaitRun stops the process group at the step bound and returns 124", async () => {
  const dir = scratch();
  launch(dir, ["sh", "-c", "sleep 30"]);
  const t = Date.now();
  const code = await awaitRun({ dir, stepS: 0, pollMs: 50, graceMs: 2000, write: () => {} });
  assert.equal(code, 124);
  assert.ok(Date.now() - t < 10000);
});

test("the CLI: launch, a wait that sees the end, and GITHUB_OUTPUT carries stage and dir", () => {
  const dir = scratch(), out = scratch();
  const env = { ...process.env, FW_MEASURE_DIR: dir, GITHUB_OUTPUT: join(scratch(), "gh-out") };
  writeFileSync(env.GITHUB_OUTPUT, "");
  const cli = join(here, "tick.mjs");
  assert.equal(spawnSync("node", [cli, "launch", "--", "sh", "-c", "exit 0"], { env, encoding: "utf8" }).status, 0);
  const w = spawnSync("node", [cli, "wait", "1", "--out", out, "--poll-ms", "50", "--step-min", "35"], { env, encoding: "utf8", timeout: 20000 });
  assert.equal(w.status, 0, w.stderr);
  assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /stage=yes\ndir=.*tick\/1\nwhy=done/);
  const a = spawnSync("node", [cli, "await", "--step-min", "35"], { env, encoding: "utf8", timeout: 20000 });
  assert.equal(a.status, 0, a.stderr);
});

test("the webkit-sim workflow has exactly Lean's tickSteps tick steps, each with its upload, between the launch and the one measuring step", () => {
  const yml = readFileSync(join(root, ".github", "workflows", "webkit-sim.yml"), "utf8");
  const ids = [...yml.matchAll(/^ {8}id: tick(\d+)$/gm)].map((m) => Number(m[1]));
  assert.deepEqual(ids, Array.from({ length: TICK_STEPS }, (_, i) => i + 1));
  for (const k of ids) {
    assert.match(yml, new RegExp(`run: node scripts/ci-telemetry/tick.mjs wait ${k}\\n`));
    assert.match(yml, new RegExp(`steps.tick${k}.outputs.stage == 'yes'`));
    assert.match(yml, new RegExp(`name: sim-tick-\\$\\{\\{ matrix.vm \\}\\}-${k}\\n`));
  }
  assert.equal([...yml.matchAll(/^ {6}- name: Determinism sessions$/gm)].length, 1);
  assert.ok(yml.indexOf("tick.mjs launch") < yml.indexOf("id: tick1") && yml.indexOf("id: tick8") < yml.indexOf("tick.mjs await"));
  assert.match(yml, /FW_TICK_STEP_MIN: \$\{\{ needs.plan.outputs.step_min \}\}/);
});
