import { overallNames } from './end-wktr.mjs';
import { FLOOR_BAND, MIN_FRAMES, readingOf, readingRate, rowsByKey } from './end-floor-dirty.mjs';

/** Lean `ScrollParkVerdict.band` and `minRead`: the floor band and the fewest frames of a readable arm. */
export const BAND = FLOOR_BAND;
export const MIN_READ = MIN_FRAMES;

/** The site build of each mode of the lane: v2-proved's four relevant flags plus the engine-check stand-ins of `end-floor-dirty`. */
const BASE_FW = 'morph.geom:on,morph.tween:geom-timed,platform:faded-pause';
export const PARK_FW = {
  v2p: `${BASE_FW},engine.scroll:unthrottle,hero.exit:threaded`,
  nohero: `${BASE_FW},engine.scroll:unthrottle`,
  nout: `${BASE_FW},hero.exit:threaded`,
  base: BASE_FW,
  hp: `${BASE_FW},engine.scroll:unthrottle,hero.exit:threaded-park`,
  up: `${BASE_FW},engine.scroll:unthrottle-park,hero.exit:threaded`,
  both: `${BASE_FW},engine.scroll:unthrottle-park,hero.exit:threaded-park`,
};
export const PARK_KEYS = Object.keys(PARK_FW);
export const parkMode = (key) => `park-${key}-thr-off`;
export const isParkMode = (mode) => /^park-(v2p|nohero|nout|base|hp|up|both)-thr-off$/.test(mode);
export const PARK_ARMS = ['rs-idle-pbpd', 'rs-idle-pbpm'];
/** The arms read: the end-of-page idle arm and the mid-page idle arm (50 percent of the scroll range). */
export const READ_ARMS = ['idle-pbpd', 'idle-pbpm'];
export const armLabel = (a) => (a === 'idle-pbpd' ? 'end-of-page idle' : 'mid-page idle');
export const FILE_OF = (key) => `accel-${parkMode(key)}-1.json`;

const rd = (x) => `frames ${x.frames} recalcs ${x.recalcs} rate ${readingRate(x)} per 100 rAF callbacks`;
const short = (x) => x.frames < MIN_READ;

/** Lean `split`: which of a flag's two readings holds the floor. */
export function split({ full, minusF, onlyF, base }) {
  if ([full, minusF, onlyF, base].some(short)) return 'unread';
  if (readingRate(full) <= BAND) return 'noFloor';
  if (BAND < readingRate(base)) return 'baseFloor';
  if (readingRate(onlyF) <= BAND) return 'innocent';
  if (readingRate(minusF) <= BAND) return 'sole';
  return 'shared';
}

/** Lean `park`: the park arm against the reference arm. */
export function park(on, off) {
  if (!(MIN_READ <= on.frames && MIN_READ <= off.frames && on.frames === off.frames)) return 'unread';
  if (readingRate(on) <= BAND) return 'noFloor';
  if (readingRate(off) <= BAND) return 'cut';
  if (readingRate(off) + BAND < readingRate(on)) return 'partial';
  return 'none';
}

export const overallS = (ss) => overallNames(ss.filter((s) => s !== 'unread'));
export const overallP = (ps) => overallNames(ps.filter((p) => p !== 'unread'));

const NO_READING = { frames: 0, recalcs: 0 };

/** The readings of one job: reports by key -> arm -> reading. */
export function readingsOf(reports) {
  const out = {};
  for (const key of PARK_KEYS) {
    const rep = reports[key];
    out[key] = {};
    for (const arm of READ_ARMS) {
      const row = rep ? rowsByKey(rep).get(arm) : undefined;
      out[key][arm] = row ? readingOf(row) : NO_READING;
    }
  }
  return out;
}

const FLAGS = [
  { flag: 'hero.exit:threaded', minus: 'nohero', only: 'nout' },
  { flag: 'engine.scroll:unthrottle', minus: 'nout', only: 'nohero' },
];
const PARKS = [
  { key: 'hp', name: 'hero.exit:threaded-park' },
  { key: 'up', name: 'engine.scroll:unthrottle-park' },
  { key: 'both', name: 'both parks' },
];

export function decideParkJob(reports) {
  const r = readingsOf(reports);
  const splits = [];
  const parks = [];
  for (const arm of READ_ARMS) {
    for (const f of FLAGS) {
      const x = { full: r.v2p[arm], minusF: r[f.minus][arm], onlyF: r[f.only][arm], base: r.base[arm] };
      splits.push({ arm, flag: f.flag, x, v: split(x) });
    }
    for (const p of PARKS) parks.push({ arm, key: p.key, name: p.name, on: r.v2p[arm], off: r[p.key][arm], v: park(r.v2p[arm], r[p.key][arm]) });
  }
  return { r, splits, parks };
}

export function jobLinesS(label, reports) {
  const d = decideParkJob(reports);
  const lines = [];
  for (const arm of READ_ARMS) {
    for (const key of PARK_KEYS) lines.push(`scroll-park ${label} ${armLabel(arm)} ${key}: ${rd(d.r[key][arm])}`);
  }
  for (const s of d.splits) {
    lines.push(`scroll-park-split ${label} ${armLabel(s.arm)} ${s.flag}: reference ${readingRate(s.x.full)}, without the flag ${readingRate(s.x.minusF)}, the flag alone ${readingRate(s.x.onlyF)}, neither ${readingRate(s.x.base)} per 100, verdict ${s.v}`);
  }
  for (const p of d.parks) {
    lines.push(`scroll-park-effect ${label} ${armLabel(p.arm)} ${p.name}: reference ${rd(p.on)}, park ${rd(p.off)}, verdict ${p.v}`);
  }
  return { lines, d };
}

export function overallLinesS(ds) {
  const lines = [];
  if (ds.length === 0) return lines;
  for (let i = 0; i < ds[0].splits.length; i++) {
    const s0 = ds[0].splits[i];
    const vs = ds.map((d) => d.splits[i].v);
    lines.push(`scroll-park-split overall ${armLabel(s0.arm)} ${s0.flag}: ${overallS(vs)} (jobs ${vs.join(' | ')})`);
  }
  for (let i = 0; i < ds[0].parks.length; i++) {
    const p0 = ds[0].parks[i];
    const vs = ds.map((d) => d.parks[i].v);
    lines.push(`scroll-park-effect overall ${armLabel(p0.arm)} ${p0.name}: ${overallP(vs)} (jobs ${vs.join(' | ')})`);
  }
  return lines;
}

export function rowLineS(job, file, i, row, occurrence) {
  const x = readingOf(row);
  return `${job} ${file} rows[${i}] ${row.arm}${occurrence > 1 ? `#${occurrence}` : ''}: ${rd(x)}, reps ${row.rs?.reps ?? 0}, dirty windows ${(row.rs?.dn ?? []).length}`;
}
