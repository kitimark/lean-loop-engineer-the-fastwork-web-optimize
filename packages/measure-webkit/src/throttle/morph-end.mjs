import { reduce as finishReduce, armOf, verdict } from './finish.mjs';
import { reduce as lockReduce, refusal as lockRefusal } from '../touchlock.mjs';

const FLAGS = 'morph.end.clamp:on,morph.end.flip:on,morph.end.release:on';

export const COMPOSITIONS = Object.freeze({
  rewrite: '',
  clamp: '?fw=morph.end.clamp:on',
  flip: '?fw=morph.end.flip:on',
  release: '?fw=morph.end.release:on',
  all: '?preset=morph-end-all',
  'all-unthrottle': `?fw=${FLAGS},engine.scroll:unthrottle`,
});

export const ARM_ORDER = Object.freeze(Object.keys(COMPOSITIONS));

export const EXTRA_SEARCHES = Object.freeze(Object.values(COMPOSITIONS).filter((s) => s.startsWith('?fw=') && s.includes(',')));

export const dirName = (d) => (d < 0 ? 'up' : d > 0 ? 'down' : 'none');

export function events(r, d) {
  const out = [];
  let last = 0;
  for (let i = 1; i < r.length; i++) {
    const diff = r[i] - r[i - 1];
    if (diff === 0) continue;
    const s = diff > 0 ? 1 : -1;
    if (last !== 0 && s !== last) out.push({ kind: s < 0 ? 'close' : 'reopen', frame: i, dir: dirName(d[i] ?? 0) });
    last = s;
  }
  return out;
}

const ZERO = () => ({ up: 0, down: 0, none: 0 });

export function byDirection(evs) {
  const out = { close: ZERO(), reopen: ZERO() };
  for (const e of evs) out[e.kind][e.dir]++;
  return out;
}

export function stretches(o) {
  const out = [];
  for (let i = 0; i < o.length; i++) {
    if (!o[i]) continue;
    let j = i;
    while (j + 1 < o.length && o[j + 1]) j++;
    out.push([i, j]);
    i = j;
  }
  return out;
}

export function lockCounts(rec) {
  const total = { stretches: 0, refused: {}, reversals: 0, fights: 0, displaced: 0 };
  for (const [a, b] of stretches(rec.o)) {
    const frames = [];
    for (let i = a; i <= b; i++) frames.push([rec.y[i], 1]);
    const calls = (rec.ca ?? []).filter((c) => c[2] >= a && c[2] <= b + 1).map((c) => [c[0], 1]);
    const run = { frames, events: [], calls };
    const why = lockRefusal(run);
    if (why) { total.refused[why] = (total.refused[why] ?? 0) + 1; continue; }
    const k = lockReduce(run);
    total.stretches++;
    total.reversals += k.frameReversals;
    total.fights += k.frameFights;
    total.displaced += k.displacedFrames;
  }
  return total;
}

const median = (xs) => {
  if (!xs.length) return null;
  const s = [...xs].sort((x, y) => x - y);
  return s[Math.floor(s.length / 2)];
};

export const medianGap = (t) => median(t.slice(1).map((x, i) => x - t[i]));

export const framesOf = (rec) => rec.y.map((y, i) => [y, rec.mx[i], rec.o[i] === 1]);

export const hasMorphReads = (rec) => Array.isArray(rec.r) && Array.isArray(rec.d) && rec.r.length === rec.y.length;

export function passCounts(rec) {
  const fin = finishReduce(framesOf(rec));
  const evs = hasMorphReads(rec) ? events(rec.r, rec.d) : [];
  const dirs = byDirection(evs);
  const rises = hasMorphReads(rec) ? rec.r.filter((x, i) => x > 0 && (i === 0 || rec.r[i - 1] === 0)).length : 0;
  return {
    finish: fin, opens: rises, closes: dirs.close, reopens: dirs.reopen, lock: lockCounts(rec),
    wobble: rec.wobble ?? null, moves: rec.moves ?? null, maxR: hasMorphReads(rec) ? Math.max(0, ...rec.r) : null, gap: medianGap(rec.t),
  };
}

const sum = (l) => l.reduce((a, b) => a + b, 0);
const sumDir = (l) => ({ up: sum(l.map((x) => x.up)), down: sum(l.map((x) => x.down)), none: sum(l.map((x) => x.none)) });

export function armRow(counts) {
  const fin = counts.map((c) => c.finish);
  const arm = armOf(fin);
  const short = sum(fin.map((f) => f.short));
  return {
    usable: counts.length, frames: arm.frames, band: arm.runs, short,
    shortPer1000: arm.frames ? Math.round((short * 10000) / arm.frames) / 10 : null,
    opens: sum(counts.map((c) => c.opens)), closes: sumDir(counts.map((c) => c.closes)), reopens: sumDir(counts.map((c) => c.reopens)),
    stretches: sum(counts.map((c) => c.lock.stretches)), reversals: sum(counts.map((c) => c.lock.reversals)),
    fights: sum(counts.map((c) => c.lock.fights)), displaced: sum(counts.map((c) => c.lock.displaced)),
    firstOpenReversals: sum(fin.map((f) => f.reversals)), reached: fin.filter((f) => f.reached).length,
    opened: fin.filter((f) => f.late !== null).length, late: fin.map((f) => f.late),
    wobble: sum(counts.map((c) => c.wobble ?? 0)), moves: sum(counts.map((c) => c.moves ?? 0)),
    gap: median(counts.map((c) => c.gap).filter((g) => g !== null)),
    fightsPerPass: counts.map((c) => c.lock.fights),
  };
}

export function verdicts(base, comp) {
  return {
    band: verdict({ runs: base.band, frames: base.frames }, { runs: comp.band, frames: comp.frames }),
    short: verdict({ runs: base.short, frames: base.frames }, { runs: comp.short, frames: comp.frames }),
  };
}
