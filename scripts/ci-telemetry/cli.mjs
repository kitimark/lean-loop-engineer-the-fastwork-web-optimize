// ci-telemetry: provider-neutral producer. One telemetry.json per CI job (layout: lean/Fw/Ci/Telemetry.lean, golden
// packages/contracts/golden/ci/telemetry.jsonl). It decides nothing: slow or not is fwcore `ci.telemetry`, run by the
// collector (`pnpm -s fw ci telemetry <provider> <id>`). Docs: docs/team/tools/ci-telemetry.md.
//   node scripts/ci-telemetry/cli.mjs start  [--lane L] [--job J] [--class C] [--every ms]   begin: facts + background sampler
//   node scripts/ci-telemetry/cli.mjs step   <name> -- <cmd...>                              run cmd, record a span.sh-format span
//   node scripts/ci-telemetry/cli.mjs sim-boot-ms <n>                                        record the Simulator boot time
//   node scripts/ci-telemetry/cli.mjs cache  <key> <path>                                    record a cache directory (size now = restored)
//   node scripts/ci-telemetry/cli.mjs finish [--out file]                                    stop the sampler, write telemetry.json
// State lives in FW_TELEMETRY_DIR (default $RUNNER_TEMP/fw-telemetry, else the OS temp dir). Every subcommand but `step`
// exits 0 on any internal error: telemetry never fails a job. `step` returns the command's exit status unchanged.
import { spawn, spawnSync, execFileSync } from "node:child_process";
import { appendFileSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import os from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { buildRecord, githubJobFacts, machineFacts, mergeSteps, pickJob, runnerClass, spanLine, stepTable, stepsOfSpans } from "./lib.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const env = process.env;
const dirOf = () => env.FW_TELEMETRY_DIR || join(env.RUNNER_TEMP || os.tmpdir(), "fw-telemetry");
const exec = (cmd, args) => { try { return execFileSync(cmd, args, { encoding: "utf8", timeout: 4000, stdio: ["ignore", "pipe", "ignore"] }); } catch { return null; } };
const readJson = (p, d) => { try { return JSON.parse(readFileSync(p, "utf8")); } catch { return d; } };
const readLines = (p) => { try { return readFileSync(p, "utf8").split("\n").filter(Boolean); } catch { return []; } };
const flag = (argv, f, d) => { const i = argv.indexOf(f); return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d; };

export function detect(e = env) {
  if (e.GITHUB_ACTIONS === "true") {
    return { provider: "github", runId: e.GITHUB_RUN_ID ?? "0", job: e.GITHUB_JOB ?? "job", commit: (e.GITHUB_SHA ?? "").slice(0, 7), lane: (e.GITHUB_WORKFLOW ?? "ci") };
  }
  if (e.CIRCLECI === "true") {
    return { provider: "circleci", runId: e.CIRCLE_PIPELINE_ID ?? e.CIRCLE_WORKFLOW_ID ?? "0", job: e.CIRCLE_JOB ?? "job", commit: (e.CIRCLE_SHA1 ?? "").slice(0, 7), lane: e.CIRCLE_WORKFLOW_ID ? (e.CIRCLE_PROJECT_REPONAME ?? "ci") : "ci" };
  }
  return { provider: e.FW_TELEMETRY_PROVIDER ?? "github", runId: e.FW_TELEMETRY_RUN ?? "0", job: "job", commit: "", lane: "local" };
}

function start(argv) {
  const dir = dirOf();
  mkdirSync(dir, { recursive: true });
  for (const f of ["stop", "probes.jsonl", "spans.jsonl", "cache.json", "sim-boot-ms.json", "telemetry.json"]) rmSync(join(dir, f), { force: true });
  const d = detect();
  const machine = machineFacts(exec);
  const meta = {
    provider: d.provider, lane: flag(argv, "--lane", d.lane), job: flag(argv, "--job", d.job), runId: d.runId, commit: d.commit,
    class: flag(argv, "--class", runnerClass(env, machine)), machine, startedMs: Date.now(),
  };
  writeFileSync(join(dir, "meta.json"), JSON.stringify(meta));
  const child = spawn(process.execPath, [join(here, "sampler.mjs"), dir, flag(argv, "--every", "5000")], { detached: true, stdio: "ignore" });
  child.unref();
  writeFileSync(join(dir, "sampler.pid"), String(child.pid));
  console.log(`telemetry: started in ${dir} (${meta.provider} ${meta.lane}/${meta.job} ${meta.class})`);
  return 0;
}

function step(argv) {
  const sep = argv.indexOf("--");
  if (sep < 1 || sep === argv.length - 1) { console.error("usage: step <name> -- <cmd...>"); return 2; }
  const name = argv.slice(0, sep).join(" ");
  const cmd = argv.slice(sep + 1);
  const t0 = Date.now();
  const r = spawnSync(cmd[0], cmd.slice(1), { stdio: "inherit" });
  const rc = r.status ?? (r.signal ? 128 : 127);
  try {
    const dir = dirOf();
    const meta = readJson(join(dir, "meta.json"), null);
    mkdirSync(dir, { recursive: true });
    appendFileSync(join(dir, "spans.jsonl"), spanLine({
      tool: meta?.lane ?? detect().lane, step: name, startMs: t0, durMs: Date.now() - t0, exit: rc, commit: meta?.commit ?? "",
      load: Math.round(os.loadavg()[0] * 100) / 100, host: env.CI ? "ci" : "local",
    }) + "\n");
  } catch { /* never fails the step */ }
  return rc;
}

/** Bytes under a path (files only, no symlink follow). 0 when absent. */
export function dirBytes(p) {
  let n = 0;
  const go = (q) => {
    let st;
    try { st = statSync(q, { throwIfNoEntry: false }); } catch { return; }
    if (!st) return;
    if (st.isDirectory()) { for (const e of readdirSync(q)) go(join(q, e)); } else n += st.size;
  };
  go(p);
  return n;
}

function cache(argv) {
  const [key, path] = argv;
  if (!key || !path) { console.error("usage: cache <key> <path>"); return 2; }
  const dir = dirOf();
  const rows = readJson(join(dir, "cache.json"), []);
  const bytes = dirBytes(path);
  rows.push({ key, path, hit: bytes > 0, restoredBytes: bytes, savedBytes: 0 });
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "cache.json"), JSON.stringify(rows));
  return 0;
}

async function githubFacts(meta, nowMs) {
  if (env.GITHUB_ACTIONS !== "true" || !env.GITHUB_REPOSITORY || !env.GITHUB_RUN_ID || !env.RUNNER_NAME) return null;
  const url = `${env.GITHUB_API_URL ?? "https://api.github.com"}/repos/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}/attempts/${env.GITHUB_RUN_ATTEMPT ?? "1"}/jobs?per_page=100`;
  const headers = { accept: "application/vnd.github+json", "x-github-api-version": "2022-11-28" };
  if (env.GITHUB_TOKEN) headers.authorization = `Bearer ${env.GITHUB_TOKEN}`;
  try {
    const res = await fetch(url, { headers, signal: AbortSignal.timeout(Number(env.FW_TELEMETRY_API_MS) || 15000) });
    if (!res.ok) { console.log(`telemetry: jobs API answered ${res.status}; the collector fills the steps`); return null; }
    const job = pickJob(await res.json(), env.RUNNER_NAME);
    return job ? githubJobFacts(job, nowMs) : null;
  } catch (e) { console.log(`telemetry: jobs API failed (${e?.name ?? "error"}); the collector fills the steps`); return null; }
}

async function finish(argv) {
  const dir = dirOf();
  const meta = readJson(join(dir, "meta.json"), null);
  if (!meta) { console.log("telemetry: no start, nothing to write"); return 0; }
  const pid = Number(readLines(join(dir, "sampler.pid"))[0]);
  if (pid > 0) { try { process.kill(pid, "SIGTERM"); } catch { /* already gone */ } }
  try { writeFileSync(join(dir, "stop"), "1"); } catch { /* the sampler also exits on SIGTERM */ }
  const endedMs = Date.now();
  const own = stepsOfSpans(readLines(join(dir, "spans.jsonl")), meta.lane);
  const boot = own.find((s) => s.name === "sim-boot");
  const simBootMs = env.FW_SIM_BOOT_MS ? Number(env.FW_SIM_BOOT_MS) : readJson(join(dir, "sim-boot-ms.json"), null) ?? (boot ? boot.endMs - boot.startMs : null);
  const gh = await githubFacts(meta, endedMs);
  const rows = readJson(join(dir, "cache.json"), []).map((c) => ({ key: c.key, hit: c.hit, restoredBytes: c.restoredBytes, savedBytes: Math.max(0, dirBytes(c.path) - c.restoredBytes) }));
  const probes = readLines(join(dir, "probes.jsonl")).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
  const rec = buildRecord({
    meta, steps: mergeSteps(gh?.steps ?? [], own.filter((s) => s.name !== "sim-boot")), probes, cache: rows, endedMs,
    startedMs: gh?.startedMs ?? meta.startedMs, createdMs: gh?.createdMs ?? null, simBootMs: Number.isFinite(simBootMs) ? simBootMs : null,
  });
  const out = flag(argv, "--out", join(dir, "telemetry.json"));
  writeFileSync(out, JSON.stringify(rec) + "\n");
  const table = stepTable(rec);
  console.log(table);
  if (env.GITHUB_STEP_SUMMARY) { try { appendFileSync(env.GITHUB_STEP_SUMMARY, "### telemetry\n```\n" + table + "\n```\n"); } catch { /* summary is optional */ } }
  return 0;
}

export async function main(argv) {
  const [sub, ...rest] = argv;
  try {
    if (sub === "start") return start(rest);
    if (sub === "step") return step(rest);
    if (sub === "cache") return cache(rest);
    if (sub === "sim-boot-ms") { mkdirSync(dirOf(), { recursive: true }); writeFileSync(join(dirOf(), "sim-boot-ms.json"), String(Math.round(Number(rest[0])))); return 0; }
    if (sub === "finish") return await finish(rest);
  } catch (e) {
    if (sub === "step") throw e;
    console.log(`telemetry: ${sub} failed (${e?.message ?? e}); ignored`);
    return 0;
  }
  console.error("usage: cli.mjs start|step|cache|sim-boot-ms|finish ...");
  return 2;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv.slice(2)).then((c) => { process.exitCode = c; });
}
