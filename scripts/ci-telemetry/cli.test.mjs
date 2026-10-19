// node --test scripts/ci-telemetry/   (no dependencies). The producer's pure parts, and one real start/step/finish run whose
// telemetry.json is decoded by fwcore's `ci.telemetry` (the Lean decoder is the schema).
import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildRecord, busyTotal, cpuPct, downsample, githubJobFacts, mergeSteps, parseMeminfo, parseProcStat, parseVmStat, pickJob, runnerClass, spanLine, stepsOfSpans } from "./lib.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const cli = join(here, "cli.mjs");
const fwcore = join(here, "../../lean/.lake/build/bin/fwcore");

test("parseProcStat: busy and total jiffies, idle includes iowait", () => {
  assert.deepEqual(parseProcStat("cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 1 1 1 1\n"), [150, 1000]);
  assert.equal(parseProcStat("nonsense"), null);
});

test("cpuPct: integer share of the busy delta, clamped", () => {
  assert.equal(cpuPct([100, 1000], [200, 1200]), 50);
  assert.equal(cpuPct([0, 10], [0, 10]), 0);
  assert.equal(cpuPct([0, 10], [50, 20]), 100);
});

test("parseMeminfo and parseVmStat", () => {
  assert.deepEqual(parseMeminfo("MemTotal:       16384000 kB\nMemFree: 1 kB\nMemAvailable:    8192000 kB\n"), { totalMb: 16000, usedMb: 8000 });
  assert.equal(parseMeminfo("MemTotal: 1 kB\n"), null);
  const vm = "Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free:     1000.\nPages inactive:     500.\nPages speculative:  100.\nPages purgeable:    400.\n";
  assert.equal(parseVmStat(vm, 16384 * 4000), Math.round((16384 * 2000) / 1048576));
});

test("busyTotal sums the cores", () => {
  const t = (user, sys, idle) => ({ times: { user, nice: 0, sys, idle, irq: 0 } });
  assert.deepEqual(busyTotal([t(10, 5, 85), t(20, 0, 80)]), [35, 200]);
});

test("downsample keeps the ends and the bound", () => {
  const xs = Array.from({ length: 1000 }, (_, i) => i);
  const d = downsample(xs, 100);
  assert.equal(d.length, 100);
  assert.equal(d[0], 0);
  assert.equal(d[99], 999);
  assert.deepEqual(downsample([1, 2], 100), [1, 2]);
});

test("stepsOfSpans: the span.sh format; the lane's own tool gives the bare name", () => {
  const a = spanLine({ tool: "breakpoint-gate", step: "install", startMs: 1000, durMs: 500, exit: 0, commit: "abc1234", load: 1.5, host: "ci" });
  const b = spanLine({ tool: "lean/check", step: "lake build", startMs: 2000, durMs: 70, exit: 1, commit: "abc1234", load: 0, host: "ci" });
  assert.deepEqual(stepsOfSpans([a, "garbage", b], "breakpoint-gate"), [
    { name: "install", startMs: 1000, endMs: 1500, exit: 0 },
    { name: "lean/check lake build", startMs: 2000, endMs: 2070, exit: 1 },
  ]);
});

test("pickJob and githubJobFacts: own runner, skipped steps and telemetry steps dropped, open step ends now", () => {
  const reply = { jobs: [
    { runner_name: "A", status: "completed" },
    { runner_name: "B", status: "in_progress", created_at: "2026-10-20T01:00:00Z", started_at: "2026-10-20T01:00:09Z", steps: [
      { name: "Set up job", started_at: "2026-10-20T01:00:09Z", completed_at: "2026-10-20T01:00:10Z", conclusion: "success" },
      { name: "Build", started_at: "2026-10-20T01:00:10Z", completed_at: "2026-10-20T01:00:40Z", conclusion: "failure" },
      { name: "Skipped one", started_at: "2026-10-20T01:00:40Z", completed_at: "2026-10-20T01:00:40Z", conclusion: "skipped" },
      { name: "Telemetry finish", started_at: "2026-10-20T01:00:41Z", completed_at: null, conclusion: null },
    ] },
  ] };
  assert.equal(pickJob(reply, "C"), null);
  const f = githubJobFacts(pickJob(reply, "B"), Date.parse("2026-10-20T01:00:50Z"));
  assert.equal(f.createdMs, Date.parse("2026-10-20T01:00:00Z"));
  assert.equal(f.startedMs - f.createdMs, 9000);
  assert.deepEqual(f.steps.map((s) => [s.name, s.endMs - s.startMs, s.exit]), [["Set up job", 1000, 0], ["Build", 30000, 1]]);
});

test("runnerClass", () => {
  const m = { os: "linux", arch: "arm64", cores: 4 };
  assert.equal(runnerClass({ ImageOS: "ubuntu24", RUNNER_ARCH: "ARM64" }, m), "ubuntu24-arm64-4c");
  assert.equal(runnerClass({ ImageOS: "ubuntu24-arm64", RUNNER_ARCH: "ARM64" }, m), "ubuntu24-arm64-4c");
  assert.equal(runnerClass({}, m), "linux-arm64-4c");
  assert.equal(runnerClass({ FW_RUNNER_CLASS: "x" }, m), "x");
});

test("buildRecord: layout of the Lean schema, creation never after start, steps sorted by mergeSteps", () => {
  const meta = { provider: "circleci", lane: "l", job: "j", runId: 7, commit: "abc1234", class: "c", machine: { os: "linux", arch: "x64", cpu: "c", cores: 2, memMb: 1 }, startedMs: 100 };
  const steps = mergeSteps([{ name: "b", startMs: 5, endMs: 9 }], [{ name: "a", startMs: 1, endMs: 3, exit: 0 }]);
  const r = buildRecord({ meta, steps, probes: [], cache: [], endedMs: 50, createdMs: 500 });
  assert.equal(r.ident.runId, "7");
  assert.deepEqual(r.steps.map((s) => s.name), ["a", "b"]);
  assert.equal(r.times.createdMs, 100);
  assert.equal(r.times.endedMs, 100);
  assert.equal(r.schema, 1);
});

test("start, step, finish: exit status passes through; telemetry.json is a record fwcore decodes", () => {
  const dir = mkdtempSync(join(tmpdir(), "fw-tel-"));
  const env = { PATH: process.env.PATH, FW_TELEMETRY_DIR: dir, FW_TELEMETRY_PROVIDER: "circleci", FW_TELEMETRY_RUN: "42" };
  const run = (...a) => spawnSync(process.execPath, [cli, ...a], { env, encoding: "utf8" });
  assert.equal(run("start", "--lane", "t", "--job", "unit", "--every", "1000").status, 0);
  assert.equal(run("step", "ok step", "--", process.execPath, "-e", "0").status, 0);
  assert.equal(run("step", "failing", "--", process.execPath, "-e", "process.exit(3)").status, 3);
  assert.equal(run("sim-boot-ms", "1234").status, 0);
  const fin = run("finish");
  assert.equal(fin.status, 0, fin.stderr);
  const rec = JSON.parse(readFileSync(join(dir, "telemetry.json"), "utf8"));
  assert.equal(rec.ident.provider, "circleci");
  assert.equal(rec.ident.runId, "42");
  assert.equal(rec.times.simBootMs, 1234);
  assert.deepEqual(rec.steps.map((s) => [s.name, s.exit]), [["ok step", 0], ["failing", 3]]);
  assert.ok(rec.probes.length >= 1, "the sampler wrote at least one probe");
  if (existsSync(fwcore)) {
    const req = JSON.stringify({ id: 1, op: "ci.telemetry", records: [rec] });
    const r = spawnSync(fwcore, [], { input: req + "\n", encoding: "utf8" });
    const reply = JSON.parse(r.stdout.trim().split("\n")[0]);
    assert.equal(reply.error, undefined, reply.error);
    assert.ok(reply.spans.some((s) => s.name === "failing" && s.kind.startsWith("circleci/")));
    assert.ok(reply.spans.some((s) => s.name === "(sim boot)" && s.durMs === 1234));
  }
});

test("finish without start writes nothing and exits 0", () => {
  const dir = mkdtempSync(join(tmpdir(), "fw-tel-"));
  const r = spawnSync(process.execPath, [cli, "finish"], { env: { PATH: process.env.PATH, FW_TELEMETRY_DIR: dir }, encoding: "utf8" });
  assert.equal(r.status, 0);
  assert.equal(existsSync(join(dir, "telemetry.json")), false);
  writeFileSync(join(dir, "x"), "");
});
