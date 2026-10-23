import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { cell } from './pairs.mjs';

const dir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SUFFIXES = ['', '.s2', '.s3'];

/** One row per (arm, state) over the committed sessions of that arm: the session run id, nearest later load, floors and the verdict word. */
export function sessionRows(armId) {
  const rows = [];
  for (const sfx of SUFFIXES) {
    const f = join(dir, `mac-${armId}${sfx}.json`);
    if (!existsSync(f)) continue;
    const j = JSON.parse(readFileSync(f, 'utf8'));
    for (const s of j.states) {
      const c = cell(s);
      const lf = s.loads.laterFloors ?? null;
      rows.push({ arm: armId, session: sfx || '.s1', run: j.run, state: s.id, nearest: c.nearest, floor: c.floor, x: c.x, above: c.above, laterFloors: lf, loads: s.loads.arm.length, maxDelta: c.maxDelta, grade: s.grade });
    }
  }
  return rows;
}

const ARMS = ['hero-exit-threaded', 'morph-panel-threaded', 'morph-panel-threaded-fade', 'people-carousel-crop'];

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const rows = ARMS.flatMap(sessionRows);
  const f = (r) => `${r.nearest} / ${r.floor} (${r.x}x ${r.above ? 'above' : 'within'})${r.laterFloors && r.laterFloors.n > 1 ? `, floors ${r.laterFloors.min}-${r.laterFloors.median}-${r.laterFloors.max} of ${r.laterFloors.n} pairs` : ''}`;
  console.log('| arm | state | session | run | nearest later load / floor | max delta | grade |');
  console.log('|---|---|---|---|---|---|---|');
  for (const r of rows) console.log(`| ${r.arm} | ${r.state} | ${r.session} | ${r.run.slice(-24)} | ${f(r)} | ${r.maxDelta} | ${r.grade} |`);
  if (process.argv.includes('--write')) writeFileSync(join(dir, 'mac-sessions.json'), JSON.stringify({ schema: 'fw.gpu-safari-sessions/1', rows }, null, 1) + '\n');
}
