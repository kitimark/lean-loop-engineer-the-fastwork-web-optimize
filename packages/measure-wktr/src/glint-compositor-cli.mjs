import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { decideJobC, jobLineC, overallJobsC } from './glint-compositor.mjs';

const read = (f) => JSON.parse(readFileSync(f, 'utf8'));

export function decideDirsC(dirs, pass = 1) {
  const ds = [];
  const lines = [];
  for (const dir of dirs) {
    const b = join(dir, `accel-glint-base-thr-off-${pass}.json`);
    const c = join(dir, `accel-glint-comp-thr-off-${pass}.json`);
    if (!existsSync(b) || !existsSync(c)) { lines.push(`glint-compositor ${dir}: result files missing`); continue; }
    const d = decideJobC(read(b), read(c));
    ds.push(d);
    lines.push(jobLineC(dir, 'idle', d.idle), jobLineC(dir, 'flip', d.flip));
  }
  const o = overallJobsC(ds);
  lines.push(`glint-compositor overall idle: ${o.idle}`, `glint-compositor overall flip: ${o.flip}`);
  return { lines, overall: o, jobs: ds };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  for (const l of decideDirsC(process.argv.slice(2)).lines) console.log(l);
}
