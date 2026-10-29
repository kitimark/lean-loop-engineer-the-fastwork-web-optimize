// Offline verdicts of task glint-hold-wktr: node glint-cli.mjs <job dir>...  Each dir holds accel-glint-base-thr-off-<p>.json and accel-glint-hold-thr-off-<p>.json
// (result files of the accel lane). Prints one line per job and cell, then the overall verdict per cell, all from glint-hold.mjs (the Lean rule).
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { decideJob, jobLine, overallJobs } from './glint-hold.mjs';

const read = (f) => JSON.parse(readFileSync(f, 'utf8'));

export function decideDirs(dirs, pass = 1) {
  const ds = [];
  const lines = [];
  for (const dir of dirs) {
    const b = join(dir, `accel-glint-base-thr-off-${pass}.json`);
    const h = join(dir, `accel-glint-hold-thr-off-${pass}.json`);
    if (!existsSync(b) || !existsSync(h)) { lines.push(`glint ${dir}: result files missing`); continue; }
    const d = decideJob(read(b), read(h));
    ds.push(d);
    lines.push(jobLine(dir, 'idle', d.idle), jobLine(dir, 'flip', d.flip));
  }
  const o = overallJobs(ds);
  lines.push(`glint overall idle: ${o.idle}`, `glint overall flip: ${o.flip}`);
  return { lines, overall: o, jobs: ds };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  for (const l of decideDirs(process.argv.slice(2)).lines) console.log(l);
}
