// ci-telemetry tick: a measuring step that runs in the background, and the upload ticks around it (task macos-vm-upload).
// TS stand-ins of Fw.Ci.Telemetry.tickPeriodMin, tickPeriodS and wakeWhy, replayed against the Lean golden
// packages/contracts/golden/ci/telemetry.jsonl by tick.test.mjs. The rest only moves files.
//   node tick.mjs launch [--dir D] -- <cmd...>     start cmd in its own process group, record start time, pid, and exit code
//   node tick.mjs wait <n> [--step-min N]           block until a pass file is new, the period passed, the run ended or the step bound; stage the upload
//   node tick.mjs await [--step-min N]              wait for the run (kill it at the step bound), print its log, exit with its code
// State: --dir, else $RUNNER_TEMP/fw-measure. Every command but `await` exits 0 on any internal error: a tick never fails the job.
import { appendFileSync, closeSync, copyFileSync, existsSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, statSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

export const TICK_STEPS = 8;
export const PERIODIC_TICKS = 4;
export const tickPeriodMin = (step) => Math.floor(step / (PERIODIC_TICKS + 1));
export const tickPeriodS = (step) => 60 * tickPeriodMin(step);
export const periodicAtMin = (step) => Array.from({ length: PERIODIC_TICKS }, (_, i) => (i + 1) * tickPeriodMin(step));

/** Lean `wakeWhy`: the first reason in the order done, deadline, pass, period; null when the tick keeps waiting. */
export function wakeWhy(elapsedS, sinceS, periodS, stepS, fresh, done) {
  if (done) return "done";
  if (stepS <= elapsedS) return "deadline";
  if (fresh > 0) return "pass";
  if (periodS <= sinceS) return "period";
  return null;
}

const PASS = /\.pass-\d+\.part$/;
const TAIL_LINES = 100;

export const stateDir = (env = process.env) => env.FW_MEASURE_DIR || join(env.RUNNER_TEMP || tmpdir(), "fw-measure");
const readNum = (f) => { try { return Number(readFileSync(f, "utf8").trim()); } catch { return null; } };
const readState = (dir) => { try { return JSON.parse(readFileSync(join(dir, "state.json"), "utf8")); } catch { return { staged: [], lastUploadMs: null, logOffset: 0, finalUploaded: false }; } };
const writeState = (dir, s) => writeFileSync(join(dir, "state.json"), JSON.stringify(s));

/** Pass files under `out` that are not staged yet. */
export function freshPasses(out, staged) {
  let names = [];
  try { names = readdirSync(out); } catch { /* no out dir yet */ }
  return names.filter((n) => PASS.test(n) && !staged.includes(n)).sort();
}

function tailOf(file, lines) {
  try { return readFileSync(file, "utf8").split("\n").slice(-lines - 1).join("\n"); } catch { return ""; }
}

/** Print the console lines written since the last print and return the new offset. */
function echoNew(file, offset, write) {
  try {
    const size = statSync(file).size;
    if (size <= offset) return offset;
    const buf = readFileSync(file);
    write(buf.subarray(offset).toString("utf8"));
    return buf.length;
  } catch { return offset; }
}

export function launch(dir, cmd, { now = Date.now } = {}) {
  mkdirSync(dir, { recursive: true });
  const log = openSync(join(dir, "console.log"), "a");
  const t0 = now();
  writeFileSync(join(dir, "t0"), String(t0));
  const exitFile = join(dir, "exit");
  const child = spawn("/bin/bash", ["-c", 'f=$1; shift; "$@"; rc=$?; echo $rc > "$f.tmp"; mv "$f.tmp" "$f"', "bash", exitFile, ...cmd], { detached: true, stdio: ["ignore", log, log], env: { ...process.env, FW_MEASURE_T0_MS: String(t0) } });
  child.unref();
  closeSync(log);
  writeFileSync(join(dir, "pid"), String(child.pid));
  return child.pid;
}

/**
 * One tick: wait for Lean's `wakeWhy` to say wake, then stage <dir>/tick/<n> (new pass files, a probes snapshot, the console tail, tick.json).
 * Returns { why, stage, files }.
 */
export async function waitTick(n, { dir, out, stepS, periodS, pollMs = 5000, probes, now = Date.now, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), write = (s) => process.stdout.write(s) }) {
  const t0 = readNum(join(dir, "t0"));
  const st = readState(dir);
  if (t0 === null) return { why: "no-run", stage: false, files: [] };
  if (st.lastUploadMs === null) st.lastUploadMs = t0;
  const log = join(dir, "console.log");
  for (;;) {
    st.logOffset = echoNew(log, st.logOffset, write);
    const done = existsSync(join(dir, "exit"));
    const fresh = freshPasses(out, st.staged);
    const t = now();
    const why = wakeWhy(Math.floor((t - t0) / 1000), Math.floor((t - st.lastUploadMs) / 1000), periodS, stepS, fresh.length, done);
    if (why) {
      const files = [];
      const ending = why === "done" || why === "deadline";
      const has = fresh.length > 0 || !ending || !st.finalUploaded;
      if (has) {
        const to = join(dir, "tick", String(n));
        mkdirSync(to, { recursive: true });
        for (const f of fresh) { copyFileSync(join(out, f), join(to, f)); files.push(f); }
        if (probes && existsSync(probes)) { copyFileSync(probes, join(to, "probes.jsonl")); files.push("probes.jsonl"); }
        writeFileSync(join(to, "console-tail.txt"), tailOf(log, TAIL_LINES));
        writeFileSync(join(to, "tick.json"), JSON.stringify({ tick: n, why, atMs: t, elapsedS: Math.floor((t - t0) / 1000), passes: fresh, done }));
        st.staged.push(...fresh);
        st.lastUploadMs = t;
        if (ending) st.finalUploaded = true;
      }
      writeState(dir, st);
      return { why, stage: has, files };
    }
    writeState(dir, st);
    await sleep(pollMs);
  }
}

const killGroup = (pid, sig) => { try { process.kill(-pid, sig); } catch { /* gone */ } };

/** Wait for the run to end; at the step bound stop its process group (TERM, 20 s, KILL) and return 124. */
export async function awaitRun({ dir, stepS, pollMs = 2000, graceMs = 20000, now = Date.now, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), write = (s) => process.stdout.write(s) }) {
  const t0 = readNum(join(dir, "t0"));
  if (t0 === null) { write("the measurement was never started\n"); return 125; }
  const st = readState(dir);
  const log = join(dir, "console.log");
  const pid = readNum(join(dir, "pid"));
  let code = null;
  let killedAt = null;
  while (code === null) {
    st.logOffset = echoNew(log, st.logOffset, write);
    const rc = readNum(join(dir, "exit"));
    if (rc !== null) { code = rc; break; }
    const t = now();
    if (killedAt === null && stepS <= (t - t0) / 1000 && pid) { write(`measuring step bound ${stepS} s reached: stopping process group ${pid}\n`); killGroup(pid, "SIGTERM"); killedAt = t; }
    else if (killedAt !== null && t - killedAt >= graceMs) { killGroup(pid, "SIGKILL"); code = 124; break; }
    await sleep(pollMs);
  }
  st.logOffset = echoNew(log, st.logOffset, write);
  writeState(dir, st);
  return killedAt !== null ? 124 : code;
}

function flag(args, name, def) {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
}

async function main(argv) {
  const [cmd, ...rest] = argv;
  const env = process.env;
  const dir = flag(rest, "--dir", stateDir(env));
  const stepMin = Number(flag(rest, "--step-min", env.FW_TICK_STEP_MIN || 35));
  if (cmd === "launch") {
    const at = rest.indexOf("--");
    if (at < 0 || at === rest.length - 1) { console.error("usage: tick.mjs launch [--dir D] -- <cmd...>"); return 64; }
    console.log(`measurement started in the background, pid ${launch(dir, rest.slice(at + 1))}`);
    return 0;
  }
  if (cmd === "wait") {
    const n = Number(rest[0]);
    const out = flag(rest, "--out", env.FW_TICK_OUT || join(env.GITHUB_WORKSPACE || process.cwd(), "packages/measure-webkit/out"));
    const probes = join(env.FW_TELEMETRY_DIR || join(env.RUNNER_TEMP || tmpdir(), "fw-telemetry"), "probes.jsonl");
    const stepS = Number(flag(rest, "--step-s", stepMin * 60));
    const periodS = Number(flag(rest, "--period-s", tickPeriodS(stepMin)));
    const pollMs = Number(flag(rest, "--poll-ms", 5000));
    try {
      const r = await waitTick(n, { dir, out, stepS, periodS, pollMs, probes });
      console.log(`tick ${n}: ${r.why}${r.stage ? `, staged ${r.files.join(" ") || "nothing"}` : ", nothing new to upload"}`);
      if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, `stage=${r.stage ? "yes" : "no"}\ndir=${join(dir, "tick", String(n))}\nwhy=${r.why}\n`);
    } catch (e) { console.log(`tick ${n}: not staged (${e instanceof Error ? e.message : String(e)})`); }
    return 0;
  }
  if (cmd === "await") {
    const stepS = Number(flag(rest, "--step-s", stepMin * 60));
    const code = await awaitRun({ dir, stepS });
    console.log(`the measurement ended with exit ${code}`);
    return code;
  }
  console.error("usage: tick.mjs launch|wait|await");
  return 64;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main(process.argv.slice(2)).then((c) => process.exit(c), (e) => { console.error(e); process.exit(1); });
