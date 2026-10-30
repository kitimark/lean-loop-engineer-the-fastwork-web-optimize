import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { FILE_OF, PARK_KEYS, jobLinesS, overallLinesS, rowLineS } from './scroll-park.mjs';

/** The reports of one job directory, by key; a key without a file is absent (its arms read as unread). */
export function reportsOf(dir) {
  const reports = {};
  for (const key of PARK_KEYS) {
    const f = join(dir, FILE_OF(key));
    if (existsSync(f)) reports[key] = JSON.parse(readFileSync(f, 'utf8'));
  }
  return reports;
}

export function decideDirsS(dirs) {
  const lines = [];
  const ds = [];
  for (const dir of dirs) {
    const reports = reportsOf(dir);
    if (Object.keys(reports).length === 0) {
      lines.push(`scroll-park ${dir}: no result file`);
      continue;
    }
    const r = jobLinesS(dir, reports);
    ds.push(r.d);
    lines.push(...r.lines);
  }
  lines.push(...overallLinesS(ds));
  return { lines, jobs: ds };
}

export function rowsOfRunS(dir) {
  const lines = [];
  const jobs = readdirSync(dir).filter((d) => /^wktr-j\d+$/.test(d)).sort();
  for (const job of jobs) {
    for (const key of PARK_KEYS) {
      const f = join(dir, job, FILE_OF(key));
      if (!existsSync(f)) continue;
      const j = JSON.parse(readFileSync(f, 'utf8'));
      const seen = new Map();
      j.rows.forEach((row, i) => {
        if (!row.rs?.dn) return;
        const n = (seen.get(row.arm) ?? 0) + 1;
        seen.set(row.arm, n);
        lines.push(rowLineS(job, FILE_OF(key), i, row, n));
      });
    }
  }
  return lines;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const take = (flag) => {
    const i = args.indexOf(flag);
    return i >= 0 ? args.splice(i, 2)[1] : null;
  };
  const out = take('--out');
  const rowsDir = take('--rows');
  const lines = rowsDir ? rowsOfRunS(rowsDir) : decideDirsS(args).lines;
  if (out) writeFileSync(out, lines.join('\n') + '\n');
  else for (const l of lines) console.log(l);
}
