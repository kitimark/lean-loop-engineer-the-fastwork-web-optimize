import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { jobLinesE, overallE } from './end-wktr.mjs';

const read = (f) => JSON.parse(readFileSync(f, 'utf8'));
export const KEYS = ['base', 'fp', 'comp', 'both'];

export function decideDirsE(dirs, pass = 1) {
  const ds = [];
  const lines = [];
  for (const dir of dirs) {
    const fs = KEYS.map((k) => join(dir, `accel-end-${k}-thr-off-${pass}.json`));
    if (!fs.every((f) => existsSync(f))) { lines.push(`end-wktr ${dir}: result files missing`); continue; }
    const r = jobLinesE(dir, Object.fromEntries(KEYS.map((k, i) => [k, read(fs[i])])));
    ds.push(r.d);
    lines.push(...r.lines);
  }
  const o = overallE(ds);
  for (const [k, v] of Object.entries(o.cells)) lines.push(`end-wktr overall ${k}: ${v}`);
  lines.push(`end-wktr overall compositor flip residual cause: ${o.cause}`, `end-wktr overall compositor flip mechanism: ${o.mech}`);
  return { lines, overall: o, jobs: ds };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const oi = args.indexOf('--out');
  const out = oi >= 0 ? args.splice(oi, 2)[1] : null;
  const r = decideDirsE(args);
  if (out) writeFileSync(out, r.lines.join('\n') + '\n');
  for (const l of r.lines) console.log(l);
}
