import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { jobLinesP, overallLinesP, rowLineP } from './end-floor-probe.mjs';

export const FILE = 'accel-probe-v2p-thr-off-1.json';

export function decideDirsP(dirs) {
  const lines = [];
  const ds = [];
  for (const dir of dirs) {
    const f = join(dir, FILE);
    if (!existsSync(f)) { lines.push(`end-floor-probe ${dir}: result file missing`); continue; }
    const r = jobLinesP(dir, JSON.parse(readFileSync(f, 'utf8')));
    ds.push(r.d);
    lines.push(...r.lines);
  }
  lines.push(...overallLinesP(ds));
  return { lines, jobs: ds };
}

export function rowsOfRunP(dir) {
  const lines = [];
  const jobs = readdirSync(dir).filter((d) => /^wktr-j\d+$/.test(d)).sort();
  for (const job of jobs) {
    const f = join(dir, job, FILE);
    if (!existsSync(f)) continue;
    const j = JSON.parse(readFileSync(f, 'utf8'));
    const seen = new Map();
    j.rows.forEach((row, i) => {
      if (!row.rs) return;
      const n = (seen.get(row.arm) ?? 0) + 1;
      seen.set(row.arm, n);
      lines.push(rowLineP(job, FILE, i, row, n));
    });
  }
  return lines;
}

// verdict:  end-floor-probe-cli.mjs <job dir>... [--out verdict.txt]
// rows:     end-floor-probe-cli.mjs --rows <run dir holding wktr-j<n>> [--out rows.txt]
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const take = (flag) => { const i = args.indexOf(flag); return i >= 0 ? args.splice(i, 2)[1] : null; };
  const out = take('--out');
  const rowsDir = take('--rows');
  const lines = rowsDir ? rowsOfRunP(rowsDir) : decideDirsP(args).lines;
  if (out) writeFileSync(out, lines.join('\n') + '\n');
  else for (const l of lines) console.log(l);
}
