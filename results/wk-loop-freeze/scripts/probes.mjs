// usage: node probes.mjs <dir>...   one row per job (sim-tick-<job>-<n> artifacts under <dir>): the sampler's own gaps,
// swap and memory. The sampler is a separate process (scripts/ci-telemetry/sampler.mjs): a gap in its samples that matches
// a late tick of the measure process is a stall of both, not of one.
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const jobs = new Map();
for (const dir of process.argv.slice(2)) {
  for (const d of readdirSync(dir)) {
    const m = /^sim-tick-(.+)-(\d+)$/.exec(d);
    const f = join(dir, d, 'probes.jsonl');
    if (!m || !existsSync(f)) continue;
    const key = `${dir.split('/').pop()}/${m[1]}`;
    const rows = jobs.get(key) ?? new Map();
    for (const l of readFileSync(f, 'utf8').split('\n').filter(Boolean)) { const p = JSON.parse(l); rows.set(p.atMs, p); }
    jobs.set(key, rows);
  }
}
const num = (a) => a.filter((x) => typeof x === 'number');
for (const [key, rows] of [...jobs].sort()) {
  const ps = [...rows.values()].sort((a, b) => a.atMs - b.atMs);
  let worst = 0, at = 0, over30 = 0;
  for (let i = 1; i < ps.length; i++) { const g = (ps[i].atMs - ps[i - 1].atMs) / 1000; if (g > 30) over30++; if (g > worst) { worst = g; at = ps[i - 1].atMs; } }
  const so = num(ps.map((p) => p.swapOuts)), sw = num(ps.map((p) => p.swapUsedMb)), mem = num(ps.map((p) => p.memUsedMb)), fr = num(ps.map((p) => p.freePct));
  console.log(key.padEnd(24), `n=${ps.length}`.padEnd(7), `maxGap ${worst.toFixed(0)}s@${new Date(at).toISOString().slice(11, 19)}`.padEnd(20), `gaps>30s ${over30}`.padEnd(11),
    `swapMax ${Math.max(...sw)}MB`.padEnd(15), `swapOuts ${Math.max(...so)}`.padEnd(18), `memMax ${Math.max(...mem)}`.padEnd(13), `freeMin ${Math.min(...fr)}%`);
}
