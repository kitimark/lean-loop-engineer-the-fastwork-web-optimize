import os from 'node:os';

export function cpuTimes(cpus = os.cpus()) {
  let idle = 0, total = 0;
  for (const c of cpus) { idle += c.times.idle; total += c.times.user + c.times.nice + c.times.sys + c.times.idle + c.times.irq; }
  return { idle, total };
}

export function idlePct(a, b) {
  const dt = b.total - a.total;
  return dt > 0 ? Math.round(((b.idle - a.idle) / dt) * 1000) / 10 : null;
}

let last = null;

export function loadStamp({ now = Date.now, loadavg = os.loadavg, cpus = os.cpus } = {}) {
  const t0 = now();
  const c = cpus(), cur = cpuTimes(c);
  const idle = last ? idlePct(last, cur) : null;
  last = cur;
  return { ts: new Date(t0).toISOString(), load1: Math.round(loadavg()[0] * 100) / 100, idle, cpus: c.length };
}

export function resetLoadStamp() { last = null; }
