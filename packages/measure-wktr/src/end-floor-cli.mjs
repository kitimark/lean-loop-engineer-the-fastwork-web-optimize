import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { jobLinesF, overallFloor, WRITERS, ARM_OF } from './end-floor.mjs';
import { overall } from './end-floor-window.mjs';

export const SETS = ['v2p'];

export function decideDirsF(dirs, pass = 1) {
  const lines = [];
  const by = Object.fromEntries(SETS.map((k) => [k, []]));
  for (const dir of dirs) {
    for (const k of SETS) {
      const f = join(dir, `accel-floor-${k}-thr-off-${pass}.json`);
      if (!existsSync(f)) { lines.push(`end-floor ${dir} ${k}: result file missing`); continue; }
      const r = jobLinesF(`${dir} ${k}`, JSON.parse(readFileSync(f, 'utf8')));
      by[k].push(r.d);
      lines.push(...r.lines);
    }
  }
  const overallBy = {};
  for (const k of SETS) {
    if (by[k].length === 0) continue;
    overallBy[k] = overallFloor(by[k]);
    for (const w of [...WRITERS, 'write']) lines.push(`end-floor overall ${k} ${ARM_OF[w]}: ${overallBy[k].cells[w]}`);
    lines.push(`end-floor overall ${k} finding: ${overallBy[k].finding}`);
    for (const key of [...new Set(by[k].flatMap((d) => d.win.map((w) => `${w.arm}[${w.k}]`)))]) {
      const reads = by[k].map((d) => d.win.find((w) => `${w.arm}[${w.k}]` === key)?.facts.verdict ?? 'unread');
      const pinned = by[k].filter((d) => d.win.some((w) => `${w.arm}[${w.k}]` === key && w.facts.pin === 'pinned')).length;
      lines.push(`end-floor-window overall ${k} ${key}: ${overall(reads)} (jobs ${reads.join(' ')}), pinned windows in ${pinned} of ${by[k].length} jobs`);
    }
  }
  return { lines, overall: overallBy, jobs: by };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const oi = args.indexOf('--out');
  const out = oi >= 0 ? args.splice(oi, 2)[1] : null;
  const r = decideDirsF(args);
  if (out) writeFileSync(out, r.lines.join('\n') + '\n');
  for (const l of r.lines) console.log(l);
}
