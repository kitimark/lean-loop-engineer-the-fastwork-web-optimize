import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { framesOf, rate } from './end-floor.mjs';

export const rowLine = (job, file, i, row) => {
  const fs = framesOf(row);
  const wins = row.rs.wins ?? [];
  const per = new Map();
  let noMut = 0;
  for (const f of fs) {
    const muts = new Set(f.keys.filter((k) => typeof k === 'string' && k.startsWith('mut:')));
    if (muts.size === 0) noMut += 1;
    for (const k of muts) per.set(k, (per.get(k) ?? 0) + 1);
  }
  const keys = [...per.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([k, n]) => `${k}=${n}`);
  return [
    `${job} ${file} rows[${i}] ${row.arm}:`,
    `frames ${fs.length},`,
    `rate ${fs.length === 0 ? '-' : rate(fs)} per 100 frames,`,
    `r=0 ${fs.filter((f) => f.r === 0).length},`,
    `r=1 ${fs.filter((f) => f.r === 1).length},`,
    `wins ${wins.length === 0 ? '-' : `${Math.min(...wins)} to ${Math.max(...wins)}`},`,
    `frames without mut: key ${noMut},`,
    `frames per mut: key ${keys.length === 0 ? '-' : keys.join(' ')}`,
  ].join(' ');
};

export function rowsOfRun(dir) {
  const lines = [];
  const jobs = readdirSync(dir).filter((d) => /^wktr-j\d+$/.test(d)).sort();
  for (const job of jobs) {
    const files = readdirSync(join(dir, job)).filter((f) => /^accel-.*\.json$/.test(f)).sort();
    for (const file of files) {
      const j = JSON.parse(readFileSync(join(dir, job, file), 'utf8'));
      j.rows.forEach((row, i) => { if (row.rs) lines.push(rowLine(job, file, i, row)); });
    }
  }
  return lines;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const oi = args.indexOf('--out');
  const out = oi >= 0 ? args.splice(oi, 2)[1] : null;
  const lines = rowsOfRun(args[0]);
  if (out) writeFileSync(out, lines.join('\n') + '\n');
  else for (const l of lines) console.log(l);
}
