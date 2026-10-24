import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { drawOf, drawWorst } from './pathpix-exit.mjs';

const ARMS = ['N', 'F'];
const px = (r) => (r ? `${r.changed} (max ${r.maxDelta})` : 'n/a');

export function zoneReads(job) {
  const out = {};
  for (const n of ARMS) {
    const rows = job.cells.frames.filter((f) => f.floor && f.arms[n] && !f.arms[n].missing);
    const read = (z) => (rows.length ? drawWorst(rows.map((f) => drawOf(f.floor[z], f.arms[n][z]))) : 'missing');
    out[n] = { band: read('band'), rest: read('rest') };
  }
  return out;
}

export function zoneTable(jobs) {
  const L = [];
  L.push(`| job | floor, whole frame | floor in the word band | ${ARMS.map((n) => `${n} in the band | ${n} outside the band`).join(' | ')} |`);
  L.push(`|---|---|---|${ARMS.map(() => '---|---').join('|')}|`);
  for (const j of jobs) {
    const fl = j.cells.floorMax;
    const bandFloor = Math.max(0, ...j.cells.frames.filter((f) => f.floor?.band).map((f) => f.floor.band.changed));
    const z = zoneReads(j);
    L.push(`| ${j.label} | ${fl.changed} (max ${fl.maxDelta}) | ${bandFloor} | ${ARMS.map((n) => `${z[n].band} | ${z[n].rest}`).join(' | ')} |`);
  }
  L.push('');
  L.push(`| phase | t ms | ${jobs.map((j) => `${j.label} floor band`).join(' | ')} | ${ARMS.map((n) => jobs.map((j) => `${j.label} ${n} band (max)`).join(' | ')).join(' | ')} | ${ARMS.map((n) => jobs.map((j) => `${j.label} ${n} outside`).join(' | ')).join(' | ')} |`);
  L.push(`|---|---|${'---|'.repeat(jobs.length * (1 + 2 * ARMS.length))}`);
  const first = jobs[0].cells.frames;
  first.forEach((f0, idx) => {
    const fr = jobs.map((j) => j.cells.frames[idx]);
    const cell = (f, n, z) => (f?.arms[n] && !f.arms[n].missing ? px(f.arms[n][z]) : 'missing');
    L.push(`| ${f0.phase} | ${f0.t} | ${fr.map((f) => (f?.floor?.band ? f.floor.band.changed : 'n/a')).join(' | ')} | ${ARMS.map((n) => fr.map((f) => cell(f, n, 'band')).join(' | ')).join(' | ')} | ${ARMS.map((n) => fr.map((f) => (f?.arms[n] && !f.arms[n].missing ? f.arms[n].rest.changed : 'missing')).join(' | ')).join(' | ')} |`);
  });
  return L.join('\n');
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  const jobs = process.argv.slice(2).map((a) => {
    const [label, file] = a.split('=');
    return { label, cells: JSON.parse(readFileSync(file, 'utf8')) };
  });
  if (!jobs.length) { console.error('usage: node src/pathpix-exit-draw-zones.mjs <label>=<cells.json> ...'); process.exit(2); }
  console.log(zoneTable(jobs));
}
