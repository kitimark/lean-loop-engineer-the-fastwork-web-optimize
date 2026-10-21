// Cold-start cost of each long-lived or repeated process kind on this Mac (task sup-warmup, input of Fw.Sup's idle grace).
//   node measure.mjs lsp|sim|fwcore|vitest|lakehist [--n N] [--out results.json]
// One kind per call; the result is merged into results.json under kinds.<kind>. Local lane: these are this Mac's own
// process costs under whatever load it carries, never CI results. Every sample records the load average and the free
// memory beside it. A series only starts when no land is queued or holding the land lock (it waits, it never kills).
// Kills only the process groups this script started (lake serve; Simulator devices it created are shut down by udid).
import { spawn, spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { cpus, loadavg, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../../../..");
const args = process.argv.slice(2);
const kind = args[0];
const opt = (k, d) => { const i = args.indexOf(k); return i < 0 ? d : args[i + 1]; };
const outFile = resolve(opt("--out", join(here, "results.json")));
const now = () => performance.now();
const sh = (cmd, a, o = {}) => spawnSync(cmd, a, { encoding: "utf8", maxBuffer: 1 << 28, ...o });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** load average (1 min) and memory beside a sample. free = free+speculative pages; avail = free+inactive+purgeable. */
export function machine() {
  const vm = sh("vm_stat", []).stdout;
  const ps = Number(/page size of (\d+)/.exec(vm)?.[1] ?? 16384);
  const pg = (name) => Number(new RegExp(`${name}:\\s+(\\d+)`).exec(vm)?.[1] ?? 0);
  const mb = (p) => Math.round((p * ps) / 1048576);
  const swap = /used = ([\d.]+)M/.exec(sh("sysctl", ["-n", "vm.swapusage"]).stdout)?.[1];
  return { load1: Number(loadavg()[0].toFixed(2)), freeMB: mb(pg("Pages free") + pg("Pages speculative")),
    availMB: mb(pg("Pages free") + pg("Pages speculative") + pg("Pages inactive") + pg("Pages purgeable")), swapUsedMB: Math.round(Number(swap ?? 0)) };
}

/** true while a land is queued or holds the land lock (fw land --queue-status prints one VERDICT line per task). */
function landBusy() {
  const q = sh("pnpm", ["-s", "fw", "land", "--queue-status"], { cwd: root, env: { ...process.env } });
  const queued = (q.stdout ?? "").split("\n").some((l) => l.startsWith("VERDICT ") && !l.startsWith("VERDICT done") && !l.startsWith("VERDICT refused") && !l.startsWith("VERDICT failed"));
  const common = sh("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: root }).stdout.trim();
  return queued || existsSync(join(common, "fw-land.lock"));
}
async function waitNoLand() {
  if (process.env.FW_WARMUP_NOWAIT === "1") return 0; // debug runs only; a result run never sets it
  let waited = 0;
  while (landBusy()) { if (waited > 3600_000) throw new Error("land still busy after 1 h"); await sleep(30_000); waited += 30_000; }
  return waited;
}

const toolchain = () => {
  const lake = sh("lake", ["--version"]).stdout.trim();
  return { lake, node: process.version, ncpu: cpus().length, os: sh("sw_vers", ["-productVersion"]).stdout.trim() };
};
const results = existsSync(outFile) ? JSON.parse(readFileSync(outFile, "utf8")) : { schema: 1, kinds: {} };
const save = (k, v) => { results.kinds[k] = v; results.tool = toolchain(); writeFileSync(outFile, JSON.stringify(results, null, 2) + "\n"); };
const stamp = () => new Date().toISOString();

const psTable = () => sh("ps", ["-axo", "pid=,ppid=,pgid=,rss=,args="]).stdout.split("\n").filter(Boolean).map((l) => {
  const m = /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/.exec(l); return m && { pid: +m[1], ppid: +m[2], pgid: +m[3], rssKB: +m[4], args: m[5] };
}).filter(Boolean);

/** physical footprint (MB, `footprint -j`: the number Activity Monitor calls memory) of a pid and its descendants; -1 when it cannot be read. */
function treeFootprintMB(rootPid) {
  const t = psTable(); const seen = new Set([rootPid]);
  for (let ch = true; ch;) { ch = false; for (const p of t) if (!seen.has(p.pid) && seen.has(p.ppid)) { seen.add(p.pid); ch = true; } }
  const dir = mkdtempSync(join(tmpdir(), "warmup-fp-")); const f = join(dir, "fp.json");
  try {
    sh("footprint", ["-j", f, ...[...seen].map(String)], { timeout: 120_000 });
    return Math.round(JSON.parse(readFileSync(f, "utf8"))["total footprint"] / 1048576);
  } catch { return -1; } finally { rmSync(dir, { recursive: true, force: true }); }
}

// ---- lake serve: spawn to first diagnostics ------------------------------------------------------------------------------------------
async function lsp(n) {
  const leanDir = join(root, "lean");
  const rel = "Fw/Store/Ci.lean";
  const text = readFileSync(join(leanDir, rel), "utf8");
  const uri = "file://" + join(leanDir, rel);
  const samples = [];
  for (let i = 0; i < n; i++) {
    await waitNoLand();
    const m0 = machine(); const t0 = now();
    const child = spawn("lake", ["serve"], { cwd: leanDir, detached: true, stdio: ["pipe", "pipe", "ignore"] });
    const pgid = child.pid;
    const marks = {}; let buf = Buffer.alloc(0); let id = 0;
    const send = (msg) => { const b = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...msg })); child.stdin.write(`Content-Length: ${b.length}\r\n\r\n`); child.stdin.write(b); };
    const waiters = [];
    const diagCount = { n: 0 };
    child.stdout.on("data", (d) => {
      buf = Buffer.concat([buf, d]);
      for (;;) {
        const he = buf.indexOf("\r\n\r\n"); if (he < 0) return;
        const len = Number(/Content-Length: (\d+)/.exec(buf.subarray(0, he).toString())?.[1]);
        if (buf.length < he + 4 + len) return;
        const msg = JSON.parse(buf.subarray(he + 4, he + 4 + len).toString()); buf = buf.subarray(he + 4 + len);
        const t = now() - t0;
        if (msg.id === 1 && "result" in msg) marks.initializeMs ??= t;
        if (msg.method === "textDocument/publishDiagnostics" && msg.params.uri === uri) { diagCount.n++; marks.firstDiagMs ??= t; }
        if (msg.method === "$/lean/fileProgress" && msg.params.textDocument.uri === uri && msg.params.processing.length === 0) marks.fileDoneMs ??= t;
        for (const w of waiters.splice(0)) w();
      }
    });
    const until = async (key, limitMs) => { const dl = now() + limitMs; while (marks[key] === undefined) { if (now() > dl) return false; await new Promise((r) => { waiters.push(r); setTimeout(r, 500); }); } return true; };
    send({ id: ++id, method: "initialize", params: { processId: process.pid, rootUri: "file://" + leanDir, capabilities: {} } });
    const okInit = await until("initializeMs", 300_000);
    send({ method: "initialized", params: {} });
    send({ method: "textDocument/didOpen", params: { textDocument: { uri, languageId: "lean4", version: 1, text } } });
    const okDiag = okInit && (await until("firstDiagMs", 300_000));
    const okDone = okDiag && (await until("fileDoneMs", 300_000));
    const footMB = treeFootprintMB(pgid);
    // teardown: TERM the group this run started, confirm, then KILL only if it is still there
    let ended = "term";
    try { process.kill(-pgid, "SIGTERM"); } catch {}
    for (let k = 0; k < 20; k++) { await sleep(250); try { process.kill(-pgid, 0); } catch { break; } if (k === 19) { ended = "kill"; try { process.kill(-pgid, "SIGKILL"); } catch {} } }
    samples.push({ n: i + 1, at: stamp(), ok: !!okDone, initializeMs: Math.round(marks.initializeMs ?? -1), firstDiagMs: Math.round(marks.firstDiagMs ?? -1),
      fileDoneMs: Math.round(marks.fileDoneMs ?? -1), diagMessages: diagCount.n, footprintMB: footMB, ended, ...m0 });
    await sleep(2000);
  }
  save("lsp", { command: `cd lean && lake serve  (LSP client: initialize, initialized, didOpen ${rel}, ${text.split("\n").length} lines; a fresh server per sample, process group TERMed after)`,
    unit: "ms from spawn", file: rel, lines: text.split("\n").length, samples });
}

// ---- local iOS Simulator boot and shutdown, on a device this script creates and deletes ---------------------------------------------------
async function sim(n) {
  const ver = process.env.FW_IOS_VERSION ?? "27.0", build = process.env.FW_IOS_BUILD ?? "24A434", dtype = process.env.FW_SIM_DEVICE_TYPE ?? "iPhone 15 Pro Max";
  const rts = JSON.parse(sh("xcrun", ["simctl", "list", "runtimes", "-j"]).stdout).runtimes.filter((r) => r.isAvailable && r.version === ver && r.buildversion === build);
  if (rts.length !== 1) throw new Error(`pinned runtime iOS ${ver} ${build} not found`);
  const lock = sh("sh", [join(root, "scripts/sim-lock.sh"), "acquire", "sup-warmup", "--wait", "1800"], { cwd: root });
  if (lock.status !== 0) throw new Error("sim-lock not acquired: " + lock.stderr);
  const samples = []; const made = [];
  const cleanup = () => { for (const udid of made) { sh("xcrun", ["simctl", "shutdown", udid]); sh("xcrun", ["simctl", "delete", udid]); } sh("sh", [join(root, "scripts/sim-lock.sh"), "release"], { cwd: root }); };
  for (const sg of ["SIGTERM", "SIGINT"]) process.on(sg, () => { cleanup(); process.exit(143); });
  const timed = (a) => { const t = now(); const r = sh("xcrun", ["simctl", ...a]); return { ms: Math.round(now() - t), r }; };
  const simFootMB = (udid) => { const p = psTable().find((x) => x.args.includes("launchd_sim") && x.args.includes(udid)); return p ? treeFootprintMB(p.pid) : -1; };
  try {
    for (let i = 0; i < n; i++) {
      await waitNoLand();
      const name = `fw-warmup-${process.pid}-${i + 1}`;
      const m0 = machine();
      const c = timed(["create", name, dtype, rts[0].identifier]); const udid = c.r.stdout.trim(); made.push(udid);
      if (c.r.status !== 0) throw new Error("create failed: " + c.r.stderr);
      const row = { n: i + 1, at: stamp(), udid: "(deleted)", createMs: c.ms, ...m0 };
      // 1st boot of a fresh device (first-boot data setup), then bootstatus until Springboard reports ready
      const b1 = timed(["boot", udid]); const s1 = timed(["bootstatus", udid]);
      row.firstBootCmdMs = b1.ms; row.firstBootReadyMs = b1.ms + s1.ms; row.firstBootStatus = [b1.r.status, s1.r.status];
      row.firstBootFootprintMB = simFootMB(udid); row.afterFirstBoot = machine();
      const d1 = timed(["shutdown", udid]); row.shutdownMs = d1.ms; row.shutdownStatus = d1.r.status;
      // 2nd boot of the same device (warm data, the case after an idle teardown)
      const m1 = machine();
      const b2 = timed(["boot", udid]); const s2 = timed(["bootstatus", udid]);
      row.rebootCmdMs = b2.ms; row.rebootReadyMs = b2.ms + s2.ms; row.rebootStatus = [b2.r.status, s2.r.status]; row.rebootMachine = m1;
      row.rebootFootprintMB = simFootMB(udid);
      const d2 = timed(["shutdown", udid]); row.shutdown2Ms = d2.ms;
      const del = timed(["delete", udid]); row.deleteMs = del.ms; row.deleteStatus = del.r.status;
      samples.push(row);
    }
  } finally {
    cleanup();
  }
  const left = JSON.parse(sh("xcrun", ["simctl", "list", "devices", "-j"]).stdout);
  const leftover = Object.values(left.devices).flat().filter((d) => d.name.startsWith("fw-warmup-")).length;
  save("sim", { command: `xcrun simctl create <fresh name> "${dtype}" <iOS ${ver} ${build}>; simctl boot <udid>; simctl bootstatus <udid>; simctl shutdown <udid>; boot+bootstatus again; shutdown; delete  (scripts/sim-lock.sh held; own device only)`,
    runtime: `iOS ${ver} (${build})`, device: dtype, leftoverDevices: leftover, samples });
}

// ---- fwcore start: one request, one reply, as apps/runner/src/run.ts fwcoreCall does ------------------------------------------------------
function fwcoreBin() {
  const p = process.env.FW_CORE_BIN ?? join(root, "lean/.lake/build/bin/fwcore");
  if (!existsSync(p)) throw new Error("fwcore not built");
  return p;
}
async function fwcore(n) {
  const bin = fwcoreBin();
  const input = JSON.stringify({ op: "console.landTier", ids: ["x"], built: false, id: 0 }) + "\n";
  const env = { ...process.env, LEAN_ABORT_ON_PANIC: "1" };
  const bytes = statSync(bin).size;
  const spawnSamples = []; const rssSamples = [];
  for (let i = 0; i < n; i++) {
    await waitNoLand();
    const m = machine(); const t = now();
    const r = spawnSync(bin, [], { input, env, maxBuffer: 1 << 30 });
    spawnSamples.push({ n: i + 1, at: stamp(), ms: Math.round((now() - t) * 10) / 10, status: r.status, ...m });
  }
  for (let i = 0; i < n; i++) {
    const m = machine();
    const r = spawnSync("/usr/bin/time", ["-l", bin], { input, env, encoding: "utf8", maxBuffer: 1 << 30 });
    const rss = Number(/(\d+)\s+maximum resident set size/.exec(r.stderr)?.[1] ?? 0);
    const foot = Number(/(\d+)\s+peak memory footprint/.exec(r.stderr)?.[1] ?? 0);
    const real = Number(/([\d.]+)\s+real/.exec(r.stderr)?.[1] ?? 0);
    rssSamples.push({ n: i + 1, at: stamp(), realMs: Math.round(real * 1000), maxRssMB: Math.round(rss / 1048576), peakFootprintMB: Math.round(foot / 1048576), ...m });
  }
  save("fwcore", { command: "node: spawnSync(lean/.lake/build/bin/fwcore, [], {input: one console.landTier request line, env LEAN_ABORT_ON_PANIC=1}) as fwcoreCall in apps/runner/src/run.ts; rss series: /usr/bin/time -l fwcore < the same line",
    binaryMB: Math.round(bytes / 1048576), spawnSamples, rssSamples });
}

// ---- fwcore starts inside a real test file: apps/runner test/checks.test.ts (every case calls fwcoreCall once) --------------------------------
async function vitest(n) {
  const cwd = join(root, "apps/runner"); const samples = [];
  const countFile = join(mkdtempSync(join(tmpdir(), "warmup-count-")), "starts.txt");
  const wrapper = join(dirname(countFile), "fwcore-count.sh");
  writeFileSync(wrapper, `#!/bin/sh\necho 1 >> "${countFile}"\nexec "${fwcoreBin()}" "$@"\n`, { mode: 0o755 });
  try {
    const c = sh("pnpm", ["exec", "vitest", "run", "test/checks.test.ts"], { cwd, env: { ...process.env, FW_CORE_BIN: wrapper } });
    const starts = existsSync(countFile) ? readFileSync(countFile, "utf8").split("\n").filter(Boolean).length : 0;
    const tests = Number(/Tests\s+(?:\d+ failed \| )?(\d+) passed/.exec(c.stdout + c.stderr)?.[1] ?? 0);
    for (let i = 0; i < n; i++) {
      await waitNoLand();
      const m = machine(); const t = now();
      const r = sh("pnpm", ["exec", "vitest", "run", "test/checks.test.ts"], { cwd });
      const wall = Math.round(now() - t);
      const dm = /Duration\s+([\d.]+)(ms|s)\b/.exec(r.stdout + r.stderr);
      const vitestDurationMs = dm ? Math.round(Number(dm[1]) * (dm[2] === "ms" ? 1 : 1000)) : -1;
      samples.push({ n: i + 1, at: stamp(), wallMs: wall, vitestDurationMs, status: r.status, ...m });
    }
    // starts as seen from inside a vitest worker: a temporary test file (removed after) times 12 consecutive fwcoreCall requests
    const probeFile = join(cwd, "test", "zz-warmup-probe.test.ts"), probeOut = join(dirname(countFile), "probe.json");
    writeFileSync(probeFile, `import { writeFileSync } from "node:fs";\nimport { it } from "vitest";\nimport { fwcoreCall } from "../src/run.ts";\n` +
      `it("times fwcore starts", () => { const core = fwcoreCall(process.cwd()); const ms: number[] = [];\n` +
      `  for (let i = 0; i < 12; i++) { const t = performance.now(); core({ op: "console.landTier", ids: ["x"], built: false }); ms.push(Math.round((performance.now() - t) * 10) / 10); }\n` +
      `  writeFileSync(process.env.FW_PROBE_OUT!, JSON.stringify(ms)); });\n`);
    const inTest = [];
    try {
      for (let i = 0; i < n; i++) {
        await waitNoLand();
        const m = machine();
        const r = sh("pnpm", ["exec", "vitest", "run", "test/zz-warmup-probe.test.ts"], { cwd, env: { ...process.env, FW_PROBE_OUT: probeOut } });
        if (r.status === 0 && existsSync(probeOut)) inTest.push({ n: i + 1, at: stamp(), startsMs: JSON.parse(readFileSync(probeOut, "utf8")), ...m });
      }
    } finally { rmSync(probeFile, { force: true }); }
    save("vitest", { command: "cd apps/runner && pnpm exec vitest run test/checks.test.ts  (wall of the process; one extra run with FW_CORE_BIN set to a counting wrapper gives the number of fwcore starts)",
      file: "apps/runner/test/checks.test.ts", fwcoreStarts: starts, testsPassed: tests, samples, inTest,
      inTestCommand: "a temporary apps/runner/test/zz-warmup-probe.test.ts (removed after the run) calls fwcoreCall 12 times in a row and times each call with performance.now, run as pnpm exec vitest run test/zz-warmup-probe.test.ts" });
  } finally { rmSync(dirname(countFile), { recursive: true, force: true }); }
}

// ---- longest lake build, from .fw-console/timings.jsonl (local `lean/check` stage `lake build`) -------------------------------------------------------
function lakehist() {
  const common = sh("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: root }).stdout.trim();
  const file = join(dirname(common), ".fw-console/timings.jsonl");
  const rows = readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
  const pick = (f) => rows.filter(f).map((r) => r.durMs).sort((a, b) => a - b);
  const q = (v, p) => v.length ? v[Math.min(v.length - 1, Math.ceil((p / 100) * v.length) - 1)] : null; // nearest rank, as `fw timings`
  const sum = (v) => ({ n: v.length, p50: q(v, 50), p90: q(v, 90), p99: q(v, 99), max: v.length ? v[v.length - 1] : null });
  const base = (r) => r.tool === "lean/check" && r.host === "local" && r.step === "lake build";
  const ok = (r) => r.exit === 0;
  const first = rows.filter(base).reduce((a, r) => Math.min(a, r.startMs), Infinity), last = rows.filter(base).reduce((a, r) => Math.max(a, r.startMs), 0);
  const series = {
    all: sum(pick(base)), exit0: sum(pick((r) => base(r) && ok(r))),
    exit0_load_lt10: sum(pick((r) => base(r) && ok(r) && r.load < 10)), exit0_load_ge10: sum(pick((r) => base(r) && ok(r) && r.load >= 10)),
    exit0_noop_lt2s: sum(pick((r) => base(r) && ok(r) && r.durMs < 2000)), exit0_real_ge2s: sum(pick((r) => base(r) && ok(r) && r.durMs >= 2000)),
    bench_solo_build_plain: sum(pick((r) => r.tool === "lake-slot/bench" && r.step === "solo build plain a")),
    bench_clean_fwcore_build_plain: sum(pick((r) => r.tool === "lake-slot/bench" && r.step === "clean fwcore-build plain")),
  };
  save("lakehist", { command: "node measure.mjs lakehist: nearest-rank quantiles of .fw-console/timings.jsonl rows tool=lean/check host=local step='lake build' (scripts/fwcore-build.sh: lake build + strip + build record, one per lean/check.sh); bench rows tool=lake-slot/bench",
    from: new Date(first).toISOString(), to: new Date(last).toISOString(), rows: rows.length, unit: "ms per build", series, at: stamp(), ...machine() });
}

const n = Number(opt("--n", kind === "sim" ? "3" : "5"));
const run = { lsp, sim, fwcore, vitest, lakehist: async () => lakehist() }[kind];
if (!run) { console.error("usage: node measure.mjs lsp|sim|fwcore|vitest|lakehist [--n N] [--out file]"); process.exit(2); }
mkdirSync(dirname(outFile), { recursive: true });
await run(n);
console.log(`measure ${kind}: ok -> ${outFile}`);
