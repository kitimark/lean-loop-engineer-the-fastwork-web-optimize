// Host load stamp at the start and end of every pass; the host gate (sim-host.mjs) reads it. It reads kernel counters in
// process and starts no child: the `top` call it replaced stopped the event loop for 1399 s on a loaded CI VM (research/notes/2026/10-2x-wk-sim-hang.md).
import os from 'node:os';

/** Idle and total CPU time (ms, summed over cores) since boot. */
export function cpuTimes(cpus = os.cpus()) {
  let idle = 0, total = 0;
  for (const c of cpus) { idle += c.times.idle; total += c.times.user + c.times.nice + c.times.sys + c.times.idle + c.times.irq; }
  return { idle, total };
}

/** CPU idle percent between two `cpuTimes` readings (one decimal), or null when no CPU time passed between them. */
export function idlePct(a, b) {
  const dt = b.total - a.total;
  return dt > 0 ? Math.round(((b.idle - a.idle) / dt) * 1000) / 10 : null;
}

let last = null;

/**
 * The stamp: time, 1-minute load average, core count, and `idle`, the CPU idle percent since the previous stamp of this
 * process (null for the first). At a pass end that is the idle share over the pass. Never blocks.
 */
export function loadStamp({ now = Date.now, loadavg = os.loadavg, cpus = os.cpus } = {}) {
  const t0 = now();
  const c = cpus(), cur = cpuTimes(c);
  const idle = last ? idlePct(last, cur) : null;
  last = cur;
  return { ts: new Date(t0).toISOString(), load1: Math.round(loadavg()[0] * 100) / 100, idle, cpus: c.length };
}

/** Forget the previous reading (tests). */
export function resetLoadStamp() { last = null; }
