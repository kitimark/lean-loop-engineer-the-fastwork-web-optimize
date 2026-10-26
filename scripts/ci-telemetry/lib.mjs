// ci-telemetry: the pure parts of the producer (no I/O except where a function says so). The record layout is the Lean
// one (lean/Fw/Ci/Telemetry.lean, `Fw.Wire.Ci.Telemetry.recordJson`); every judgement (slow or not) is fwcore's `ci.telemetry`.
// This file only measures, normalises and shapes. Node >= 24, no dependencies.
import { readFileSync, statfsSync } from "node:fs";
import os from "node:os";

export const SCHEMA = 1;

// ---- parsers (pure) ----------------------------------------------------------------------------------------------------

/** First line of /proc/stat -> [busy, total] jiffies (idle = idle + iowait). */
export function parseProcStat(text) {
  const line = text.split("\n").find((l) => l.startsWith("cpu ")) ?? "";
  const n = line.trim().split(/\s+/).slice(1).map(Number).filter((x) => Number.isFinite(x));
  if (n.length < 4) return null;
  const total = n.slice(0, 8).reduce((a, b) => a + b, 0);
  const idle = (n[3] ?? 0) + (n[4] ?? 0);
  return [total - idle, total];
}

/** /proc/meminfo -> { totalMb, usedMb } with used = MemTotal - MemAvailable. */
export function parseMeminfo(text) {
  const kb = (k) => { const m = new RegExp(`^${k}:\\s+(\\d+)\\s*kB`, "m").exec(text); return m ? Number(m[1]) : null; };
  const t = kb("MemTotal"), a = kb("MemAvailable");
  if (t === null || a === null) return null;
  return { totalMb: Math.round(t / 1024), usedMb: Math.round((t - a) / 1024) };
}

/** `vm_stat` (macOS) + total bytes -> used MB. Used = total - (free + inactive + speculative + purgeable) pages. */
export function parseVmStat(text, totalBytes) {
  const size = Number(/page size of (\d+) bytes/.exec(text)?.[1] ?? 16384);
  const pages = (k) => Number(new RegExp(`^${k}:\\s+(\\d+)\\.`, "m").exec(text)?.[1] ?? 0);
  const avail = (pages("Pages free") + pages("Pages inactive") + pages("Pages speculative") + pages("Pages purgeable")) * size;
  if (!(totalBytes > 0)) return null;
  return Math.max(0, Math.round((totalBytes - avail) / 1048576));
}

/** `vm_stat` (macOS) -> the compressor and swap counters: MB occupied by the compressor, MB stored in it, and the running totals of
 *  swapouts and compressions (pages). A counter the text lacks is null. */
export function parseVmStatPressure(text) {
  const size = Number(/page size of (\d+) bytes/.exec(text ?? "")?.[1] ?? 16384);
  const get = (k) => { const m = new RegExp(`^${k}:\\s+(\\d+)\\.`, "m").exec(text ?? ""); return m ? Number(m[1]) : null; };
  const mb = (pages) => (pages === null ? null : Math.round((pages * size) / 1048576));
  return { compressorMb: mb(get("Pages occupied by compressor")), storedMb: mb(get("Pages stored in compressor")), swapOuts: get("Swapouts"), compressions: get("Compressions") };
}

/** `sysctl -n vm.swapusage kern.memorystatus_vm_pressure_level` -> { swapUsedMb, pressureLevel }: swap in use (MB) and the kernel level (1 normal, 2 warn, 4 critical). */
export function parseSysctlPressure(text) {
  const used = /used = ([\d.]+)M/.exec(text ?? "");
  const last = String(text ?? "").trim().split("\n").pop()?.trim() ?? "";
  return { swapUsedMb: used ? Math.floor(Number(used[1])) : null, pressureLevel: /^\d+$/.test(last) ? Number(last) : null };
}

/** `memory_pressure -Q` -> the system-wide free memory in percent, or null. */
export function parseFreePct(text) {
  const m = /free percentage:\s*(\d+)%/.exec(text ?? "");
  return m ? Number(m[1]) : null;
}

/** The CPU percentage between two [busy,total] samples, an integer 0..100. */
export function cpuPct(a, b) {
  const dt = b[1] - a[1];
  return dt > 0 ? Math.max(0, Math.min(100, Math.round(((b[0] - a[0]) * 100) / dt))) : 0;
}

/** Same from os.cpus() (macOS, and the fallback): sums of times over all cores -> [busy, total]. */
export function busyTotal(cpus) {
  let busy = 0, total = 0;
  for (const c of cpus) {
    const t = c.times;
    total += t.user + t.nice + t.sys + t.idle + t.irq;
    busy += t.user + t.nice + t.sys + t.irq;
  }
  return [busy, total];
}

/** Keep at most `max` evenly spaced probes (the first and the last stay). */
export function downsample(xs, max) {
  if (xs.length <= max) return xs;
  const out = [];
  for (let i = 0; i < max; i++) out.push(xs[Math.round((i * (xs.length - 1)) / (max - 1))]);
  return out;
}

// ---- readers (I/O) -------------------------------------------------------------------------------------------------------

const read = (p) => { try { return readFileSync(p, "utf8"); } catch { return null; } };

/** The CPU model of a Linux machine from /proc/cpuinfo and `lscpu`. x86 has a "model name" line. The arm64 runners have
 *  none: `lscpu` gives "Model name: Neoverse-N2"; failing that the cpuinfo implementer and part ("arm 0x41 part 0xd49"). */
export function parseCpuModel(cpuinfo, lscpu) {
  const m = /^(?:model name|Model|Hardware)\s*:\s*(.+)$/m.exec(cpuinfo ?? "");
  if (m) return m[1].trim();
  const l = /^Model name:\s*(.+)$/m.exec(lscpu ?? "");
  if (l && l[1].trim() !== "-") return l[1].trim();
  const imp = /^CPU implementer\s*:\s*(0x[0-9a-f]+)/im.exec(cpuinfo ?? ""), part = /^CPU part\s*:\s*(0x[0-9a-f]+)/im.exec(cpuinfo ?? "");
  if (imp && part) return `arm ${imp[1].toLowerCase()} part ${part[1].toLowerCase()}`;
  return null;
}

/** Machine facts. macOS uses sysctl for the CPU name; Linux parseCpuModel (lscpu only when cpuinfo has no name), else the os.cpus() model. */
export function machineFacts(exec) {
  const cpus = os.cpus();
  let cpu = cpus[0]?.model ?? "unknown";
  if (process.platform === "linux") {
    const info = read("/proc/cpuinfo") ?? "";
    cpu = parseCpuModel(info, exec ? exec("lscpu", []) : null) ?? cpu;
  } else if (process.platform === "darwin" && exec) {
    const b = exec("sysctl", ["-n", "machdep.cpu.brand_string"]);
    if (b) cpu = b.trim();
  }
  return { os: process.platform, arch: os.arch(), cpu, cores: os.availableParallelism(), memMb: Math.round(os.totalmem() / 1048576) };
}

/** Runner class: ImageOS-RUNNER_ARCH-<cores>c on GitHub; os-arch-<cores>c elsewhere; FW_RUNNER_CLASS overrides. */
export function runnerClass(env, m) {
  if (env.FW_RUNNER_CLASS) return env.FW_RUNNER_CLASS;
  const arch = (env.RUNNER_ARCH ?? m.arch).toLowerCase();
  const base = env.ImageOS ? (env.ImageOS.toLowerCase().endsWith(arch) ? env.ImageOS : `${env.ImageOS}-${arch}`) : `${m.os}-${m.arch}`; // ImageOS may already carry the arch (ubuntu24-arm64)
  return `${base}-${m.cores}c`;
}

/** One probe now. `prev` is the previous [busy,total] (or null); returns { probe, cur }. */
export function takeProbe(prev, dir, exec, t0 = Date.now()) {
  let cur = null, usedMb = null;
  if (process.platform === "linux") {
    const s = read("/proc/stat");
    cur = s ? parseProcStat(s) : null;
    const mi = read("/proc/meminfo");
    usedMb = mi ? parseMeminfo(mi)?.usedMb ?? null : null;
  }
  if (!cur) cur = busyTotal(os.cpus());
  const mac = process.platform === "darwin" && exec;
  const vm = mac ? exec("vm_stat", []) : null;
  if (usedMb === null) usedMb = (vm ? parseVmStat(vm, os.totalmem()) : null) ?? Math.round((os.totalmem() - os.freemem()) / 1048576);
  let diskFreeMb = 0;
  try { const f = statfsSync(dir); diskFreeMb = Math.round((f.bavail * f.bsize) / 1048576); } catch { /* keep 0 */ }
  const probe = { atMs: t0, cpuPct: prev ? cpuPct(prev, cur) : 0, memUsedMb: usedMb, loadCenti: Math.round(os.loadavg()[0] * 100), diskFreeMb };
  if (mac) Object.assign(probe, pressureReadings(vm, exec));
  return { probe, cur };
}

/** The memory pressure readings of a macOS host as the optional probe fields; a reading that did not come is left out. */
export function pressureReadings(vmStat, exec) {
  const all = {
    ...parseVmStatPressure(vmStat),
    ...parseSysctlPressure(exec("sysctl", ["-n", "vm.swapusage", "kern.memorystatus_vm_pressure_level"])),
    freePct: parseFreePct(exec("memory_pressure", ["-Q"])),
  };
  return Object.fromEntries(Object.entries(all).filter(([, v]) => v !== null));
}

// ---- spans: the scripts/span.sh format ------------------------------------------------------------------------------------

/** One span.sh line: {"tool","step","startMs","durMs","exit","commit","load","host"} (apps/runner/src/timing.ts). */
export function spanLine({ tool, step, startMs, durMs, exit, commit, load, host }) {
  return JSON.stringify({ tool, step, startMs, durMs, exit, commit, load, host });
}

/** span.sh lines -> telemetry steps. Tool = lane gives the bare step name; any other tool (check.sh's "lean/check") prefixes it. */
export function stepsOfSpans(lines, lane) {
  const out = [];
  for (const l of lines) {
    let s;
    try { s = JSON.parse(l); } catch { continue; }
    if (typeof s?.step !== "string" || !Number.isFinite(s.startMs) || !Number.isFinite(s.durMs)) continue;
    const step = { name: s.tool === lane || !s.tool ? s.step : `${s.tool} ${s.step}`, startMs: s.startMs, endMs: s.startMs + Math.max(0, s.durMs) };
    if (Number.isFinite(s.exit)) step.exit = s.exit;
    out.push(step);
  }
  return out;
}

// ---- GitHub jobs API (best effort) ------------------------------------------------------------------------------------------

const ms = (iso) => { const t = Date.parse(iso ?? ""); return Number.isFinite(t) ? t : null; };

/** The job of this runner among the jobs of a run (GitHub jobs API reply): same runner_name, in progress. */
export function pickJob(reply, runnerName) {
  const jobs = Array.isArray(reply?.jobs) ? reply.jobs : [];
  return jobs.find((j) => j.runner_name === runnerName && j.status === "in_progress") ?? null;
}

/** A GitHub job -> { createdMs, startedMs, steps }. Skipped steps and the telemetry steps themselves are dropped. */
export function githubJobFacts(job, nowMs, skip = /telemetry/i) {
  const steps = [];
  for (const s of job.steps ?? []) {
    const a = ms(s.started_at);
    if (a === null || s.conclusion === "skipped" || skip.test(s.name ?? "")) continue;
    const b = ms(s.completed_at) ?? nowMs;
    const step = { name: String(s.name), startMs: a, endMs: Math.max(a, b) };
    if (s.conclusion === "success") step.exit = 0;
    else if (s.conclusion === "failure") step.exit = 1;
    steps.push(step);
  }
  return { createdMs: ms(job.created_at), startedMs: ms(job.started_at), steps };
}

/** Merge API steps and wrapper steps; a wrapper step is kept (it is finer or the only source), sorted by start. */
export function mergeSteps(api, own) {
  return [...api, ...own].sort((x, y) => x.startMs - y.startMs || x.endMs - y.endMs);
}

// ---- the record --------------------------------------------------------------------------------------------------------------

/** Assemble the Lean `Record` JSON. All inputs are plain data (see cli.mjs `finish`). */
export function buildRecord(x) {
  const startedMs = x.startedMs ?? x.meta.startedMs;
  const endedMs = Math.max(x.endedMs, startedMs);
  const times = { startedMs, endedMs };
  if (x.createdMs != null) times.createdMs = Math.min(x.createdMs, startedMs);
  if (x.simBootMs != null) times.simBootMs = x.simBootMs;
  const clean = (s) => { const o = { name: s.name, startMs: s.startMs, endMs: Math.max(s.startMs, s.endMs) }; if (s.exit != null) o.exit = s.exit; if (s.netBytes != null) o.netBytes = s.netBytes; return o; };
  return {
    schema: SCHEMA,
    ident: { provider: x.meta.provider, lane: x.meta.lane, job: x.meta.job, runId: String(x.meta.runId), commit: x.meta.commit, class: x.meta.class },
    machine: x.meta.machine,
    times,
    steps: x.steps.map(clean),
    probes: downsample(x.probes, x.maxProbes ?? 360),
    cache: x.cache,
  };
}

/** A short table of the steps for the job log and the step summary. */
export function stepTable(rec) {
  const rows = rec.steps.map((s) => `${String(Math.round((s.endMs - s.startMs) / 100) / 10).padStart(8)} s  ${s.name}${s.exit ? `  (exit ${s.exit})` : ""}`);
  const q = rec.times.createdMs == null ? "queue n/a" : `queue ${(rec.times.startedMs - rec.times.createdMs) / 1000} s`;
  const peak = rec.probes.reduce((a, p) => Math.max(a, p.cpuPct), 0);
  const mem = rec.probes.reduce((a, p) => Math.max(a, p.memUsedMb), 0);
  const top = (k) => rec.probes.reduce((a, p) => (p[k] == null ? a : Math.max(a ?? 0, p[k])), null);
  const swap = top("swapUsedMb"), cmp = top("compressorMb"), lvl = top("pressureLevel");
  const pressure = swap == null && cmp == null && lvl == null ? "" : `, peak swap ${swap ?? "n/a"} MB, compressor ${cmp ?? "n/a"} MB, pressure level ${lvl ?? "n/a"}`;
  return [`telemetry ${rec.ident.provider}/${rec.ident.lane}/${rec.ident.job} [${rec.ident.class}] ${q}, job ${(rec.times.endedMs - rec.times.startedMs) / 1000} s, ${rec.probes.length} probes, peak cpu ${peak}%, peak mem ${mem} MB${pressure}`, ...rows].join("\n");
}
