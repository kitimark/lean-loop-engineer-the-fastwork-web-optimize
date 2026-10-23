import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { FLAG_ARMS } from './plan.mjs';
import { CI_PAIRS } from './ci-pairs.mjs';

const dir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = (f) => (existsSync(join(dir, f)) ? JSON.parse(readFileSync(join(dir, f), 'utf8')) : null);

export const cell = (s) => {
  if (!s) return null;
  const nearest = s.loads.laterNearest ?? s.loads.nearest, floor = s.loads.floor ?? s.loads.spread;
  return { nearest, floor, x: Math.round((10 * nearest) / Math.max(floor, 1)) / 10, above: nearest > floor, maxDelta: s.counts.inside.maxDelta, grade: s.grade, stable: s.stable };
};

export function pairRows() {
  const rows = [];
  for (const a of FLAG_ARMS) {
    const mac = read(`mac-${a.id}.json`), sim = read(`${a.id}.json`);
    const ids = new Set([...(mac?.states ?? []).map((s) => s.id), ...(sim?.states ?? []).map((s) => s.id)]);
    for (const id of ids) {
      const m = cell(mac?.states?.find((s) => s.id === id)), i = cell(sim?.states?.find((s) => s.id === id));
      rows.push({ arm: a.id, state: id, mac: m, sim: i, ci: CI_PAIRS[a.id] ?? null });
    }
  }
  return rows;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const rows = pairRows();
  const f = (c) => (c ? `${c.nearest}/${c.floor} (${c.x}x${c.above ? ' above' : ' within'})` : '-');
  console.log('| arm | state | macOS Safari: nearest later load / floor | Simulator: nearest / floor |');
  console.log('|---|---|---|---|');
  for (const r of rows) console.log(`| ${r.arm} | ${r.state} | ${f(r.mac)} | ${f(r.sim)} |`);
  if (process.argv.includes('--write')) writeFileSync(join(dir, 'mac-vs-sim.json'), JSON.stringify({ schema: 'fw.gpu-safari-pairs/1', rows }, null, 1) + '\n');
}
