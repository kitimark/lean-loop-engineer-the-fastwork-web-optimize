// Host load stamp: written at the start and the end of every pass (outside the timed window) so a count that comes out
// quarantined can be checked against how busy the Mac was, and so the host gate (sim-host.mjs `hostOk`) can refuse a pass.
// It reads the kernel's counters in process and starts no child: the `top -l 2` sample it replaced was a spawnSync, and on a
// CI Simulator VM (load1 87-993 on 3 cores) `top` did not exit, so the whole event loop, the stall watchdog included, stood
// still for 18-23 minutes (run 40282962088, jobs sim-r1 and sim-r3; research/notes/2026/10-2x-wk-sim-hang.md).
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
