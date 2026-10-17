// Host load stamp: written at the start and the end of every pass (outside the timed window) so a count that comes out
// quarantined can be checked against how busy the Mac was. `idle` is the CPU idle percent over a 1 s `top` sample.
import os from 'node:os';
import { spawnSync } from 'node:child_process';

export function loadStamp() {
  const t0 = Date.now();
  let idle = null;
  const r = spawnSync('top', ['-l', '2', '-n', '0', '-s', '1'], { encoding: 'utf8', timeout: 15000 });
  const m = [...String(r.stdout || '').matchAll(/CPU usage:.*?([\d.]+)% idle/g)].pop();
  if (m) idle = Number(m[1]);
  return { ts: new Date(t0).toISOString(), load1: Math.round(os.loadavg()[0] * 100) / 100, idle, cpus: os.cpus().length };
}
