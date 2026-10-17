// Host monitor for the WebKit lane (webkit-quiet): what the Mac (the CI VM) was doing while a pass ran, outside the page.
// Three instruments, all I/O glue; the decisions about them live in Lean (Fw.Measure.Quiet) and fwcore.
//   topSampler  : one `top -l 0 -s 1` child at 1 Hz -> {t, load1, user, sys, idle, top:[{cmd, cpu}]} per sample.
//   lagMonitor  : a 20 ms timer in this process; lag = how late it fired (a direct reading of CPU contention seen by the harness).
//   burners     : N busy-loop children (`yes > /dev/null`), the dose of added load in the dose-response arms.
// Only children this module started are killed, by pid. Counts never depend on any of this; it only records.
import { spawn } from 'node:child_process';

/** Parse the text of `top -l N -n K -o cpu -stats pid,command,cpu` into samples (the first sample is the since-boot average: dropped by the caller). */
export function parseTop(text) {
  const out = [];
  for (const block of String(text).split(/^Processes:/m).slice(1)) {
    const la = block.match(/Load Avg:\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)/);
    const cpu = block.match(/CPU usage:\s*([\d.]+)% user,\s*([\d.]+)% sys,\s*([\d.]+)% idle/);
    if (!la || !cpu) continue;
    const top = [];
    const after = block.split(/^PID\s.*$/m)[1] || '';
    for (const line of after.split('\n')) {
      const m = line.match(/^\s*(\d+)\s+(.+?)\s+([\d.]+)\s*$/);
      if (m) top.push({ cmd: m[2].trim().slice(0, 40), cpu: Number(m[3]) });
    }
    out.push({ load1: Number(la[1]), user: Number(cpu[1]), sys: Number(cpu[2]), idle: Number(cpu[3]), top });
  }
  return out;
}

/** Start `top` streaming at 1 Hz; `stop()` kills that child (by pid) and resolves the samples [{t, ...}] without the first. */
export function topSampler({ topN = 4 } = {}) {
  const samples = [];
  let buf = '', skipped = false, dead = false;
  const child = spawn('top', ['-l', '0', '-s', '1', '-n', String(topN), '-o', 'cpu', '-stats', 'pid,command,cpu'], { stdio: ['ignore', 'pipe', 'ignore'] });
  child.on('error', () => { dead = true; });
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', (d) => {
    buf += d;
    const parts = buf.split(/^(?=Processes:)/m);
    buf = parts.pop(); // the last block may be incomplete
    for (const p of parts) for (const s of parseTop(p)) {
      if (!skipped) { skipped = true; continue; }
      samples.push({ t: Date.now() - 1000, ...s }); // a block is emitted when the next header arrives, one period after its sample
    }
  });
  return {
    stop() {
      return new Promise((resolve) => {
        const flush = () => { for (const s of parseTop(buf)) { if (skipped) samples.push({ t: Date.now(), ...s }); } buf = ''; resolve(samples); };
        if (dead || child.exitCode !== null) return flush();
        child.once('exit', flush);
        child.kill('SIGTERM');
        setTimeout(() => resolve(samples), 2000).unref();
      });
    },
  };
}

/** Event-loop lag monitor: a timer every `everyMs`; `stop()` returns [{t, lag}] (lag in ms, >= 0). */
export function lagMonitor(everyMs = 20) {
  const out = [];
  let last = performance.now();
  const h = setInterval(() => { const n = performance.now(); out.push({ t: Date.now(), lag: Math.max(0, Math.round((n - last - everyMs) * 10) / 10) }); last = n; }, everyMs);
  return { stop() { clearInterval(h); return out; } };
}

/** Summary of lag samples inside [t0, t1]: count, mean, p95, max (ms). */
export function lagSummary(samples, t0, t1) {
  const v = samples.filter((s) => s.t >= t0 && s.t <= t1).map((s) => s.lag).sort((a, b) => a - b);
  if (!v.length) return { n: 0, mean: null, p95: null, max: null };
  const mean = v.reduce((a, b) => a + b, 0) / v.length;
  return { n: v.length, mean: Math.round(mean * 10) / 10, p95: v[Math.min(v.length - 1, Math.floor(v.length * 0.95))], max: v.at(-1) };
}

/** Max lag per `bucketMs` bucket from t0 to t1 (a compact record: one number per bucket). */
export function lagBuckets(samples, t0, t1, bucketMs = 250) {
  const n = Math.max(1, Math.ceil((t1 - t0) / bucketMs));
  const b = new Array(n).fill(0);
  for (const s of samples) { if (s.t < t0 || s.t > t1) continue; const i = Math.min(n - 1, Math.floor((s.t - t0) / bucketMs)); if (s.lag > b[i]) b[i] = s.lag; }
  return { bucketMs, max: b };
}

/** Start `n` busy-loop children; `stop()` kills them (by pid). */
export function burners(n) {
  const kids = [];
  for (let i = 0; i < n; i++) kids.push(spawn('yes', [], { stdio: ['ignore', 'ignore', 'ignore'] }));
  return { n, pids: kids.map((k) => k.pid), stop() { for (const k of kids) { try { k.kill('SIGKILL'); } catch { /* already gone */ } } } };
}
