import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { drawOf, drawWorst } from './pathpix-exit.mjs';
import { fwcoreCall } from './handoff.mjs';

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

/** The outside-band lane of one arm: the changed-pixel count of each frame, in frame order (a missing frame is left out, so Lean sees a short lane). */
export const outsideLane = (job, n) => job.cells.frames.filter((f) => f.arms[n] && !f.arms[n].missing).map((f) => f.arms[n].rest.changed);

/** Give each job `above`, `{N, F}` = `{base, above}` from fwcore `gate.pathpixDrawBase` (Lean `drawBase`, `aboveBase`); this file only formats it. */
export async function withAbove(jobs) {
  const reps = await fwcoreCall([{ id: 0, op: 'gate.pathpixDrawBase', lanes: jobs.flatMap((j) => ARMS.map((n) => outsideLane(j, n))) }]);
  if (reps[0].error !== undefined) throw new Error(`fwcore: ${reps[0].error}`);
  return jobs.map((j, i) => ({ ...j, above: Object.fromEntries(ARMS.map((n, k) => [n, reps[0].lanes[i * ARMS.length + k]])) }));
}

/** The above-baseline table: per job and arm the baseline of the outside lane and, per frame, the count above it (`n/a` when Lean pins no baseline). */
export function aboveTable(jobs) {
  const L = [];
  const cols = ARMS.flatMap((n) => jobs.map((j) => ({ j, n })));
  L.push(`| outside the band | ${cols.map(({ j, n }) => `${j.label} ${n}`).join(' | ')} |`);
  L.push(`|---|${cols.map(() => '---|').join('')}`);
  L.push(`| baseline | ${cols.map(({ j, n }) => j.above[n].base ?? 'n/a').join(' | ')} |`);
  jobs[0].cells.frames.forEach((f0, idx) => {
    L.push(`| above baseline, ${f0.phase} ${f0.t} ms | ${cols.map(({ j, n }) => j.above[n].above?.[idx] ?? 'n/a').join(' | ')} |`);
  });
  return L.join('\n');
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
  if (jobs.every((j) => j.above)) { L.push(''); L.push(aboveTable(jobs)); }
  return L.join('\n');
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  const jobs = process.argv.slice(2).map((a) => {
    const [label, file] = a.split('=');
    return { label, cells: JSON.parse(readFileSync(file, 'utf8')) };
  });
  if (!jobs.length) { console.error('usage: node src/pathpix-exit-draw-zones.mjs <label>=<cells.json> ...'); process.exit(2); }
  console.log(zoneTable(await withAbove(jobs)));
}
