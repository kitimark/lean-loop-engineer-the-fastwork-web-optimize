// Twin of Lean Fw.Measure.MorphEndCount (lean/Fw/Measure/MorphEndCount.lean): the close and re-open events by finger direction, opens,
// stretches, spring-back fights, pooled counts and the verdict of a brick. test/throttle-morph-end.test.mjs checks it against
// packages/contracts/golden/device/morph-end-count.jsonl. Still runs come from finish.mjs, pin turns from the twin of Fw.Measure.TouchLock.
import { reduce as finishReduce, armOf, verdict } from './finish.mjs';
import { reduce as lockReduce, refusal as lockRefusal, cmp } from '../touchlock.mjs';

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

/** Opens: values above 0 that follow a 0 (the series starts at 0). Lean `opens`. */
export function opens(r) {
  let n = 0;
  for (let i = 0; i < r.length; i++) if (r[i] > 0 && (i === 0 || r[i - 1] === 0)) n++;
  return n;
}

/** A step of `move` is against a finger going `d`. Lean `against`. */
export const against = (d, move) => (d < 0 && move < 0) || (d > 0 && move > 0);

/** The finger direction of the spring-back fight a write [top, open, frame] makes, or null. Lean `fightDir`. */
export function fightDir(ys, ds, w) {
  const [top, open, frame] = w;
  if (frame === 0) return null;
  const y = ys[frame - 1], d = ds[frame - 1];
  if (y === undefined || d === undefined) return null;
  return open && against(d, top - y) ? dirName(d) : null;
}

/** Spring-back fights by finger direction: every write counts at most once. Lean `springBack`. */
export function springBack(ys, ds, ws) {
  const out = ZERO();
  for (const w of ws) { const k = fightDir(ys, ds, w); if (k !== null) out[k]++; }
  return out;
}

export const dirTotal = (b) => b.up + b.down + b.none;

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
  const reads = hasMorphReads(rec);
  return {
    finish: fin, opens: reads ? opens(rec.r) : 0, closes: dirs.close, reopens: dirs.reopen, lock: lockCounts(rec),
    springBack: reads ? springBack(rec.y, rec.d, rec.ca ?? []) : ZERO(),
    wobble: rec.wobble ?? null, moves: rec.moves ?? null, maxR: hasMorphReads(rec) ? Math.max(0, ...rec.r) : null, gap: medianGap(rec.t),
  };
}

export const sum = (l) => l.reduce((a, b) => a + b, 0);
export const sumDir = (l) => ({ up: sum(l.map((x) => x.up)), down: sum(l.map((x) => x.down)), none: sum(l.map((x) => x.none)) });

export function armRow(counts) {
  const fin = counts.map((c) => c.finish);
  const arm = armOf(fin);
  const short = sum(fin.map((f) => f.short));
  return {
    usable: counts.length, frames: arm.frames, band: arm.runs, short,
    shortPer1000: arm.frames ? Math.round((short * 10000) / arm.frames) / 10 : null,
    opens: sum(counts.map((c) => c.opens)), closes: sumDir(counts.map((c) => c.closes)), reopens: sumDir(counts.map((c) => c.reopens)),
    springBack: sumDir(counts.map((c) => c.springBack)), stretches: sum(counts.map((c) => c.lock.stretches)), reversals: sum(counts.map((c) => c.lock.reversals)),
    fights: sum(counts.map((c) => c.lock.fights)), displaced: sum(counts.map((c) => c.lock.displaced)),
    firstOpenReversals: sum(fin.map((f) => f.reversals)), reached: fin.filter((f) => f.reached).length,
    opened: fin.filter((f) => f.late !== null).length, late: fin.map((f) => f.late),
    wobble: sum(counts.map((c) => c.wobble ?? 0)), moves: sum(counts.map((c) => c.moves ?? 0)),
    gap: median(counts.map((c) => c.gap).filter((g) => g !== null)),
    fightsPerPass: counts.map((c) => c.lock.fights),
    revRates: counts.map((c) => [c.lock.reversals, c.opens]), fightRates: counts.map((c) => [dirTotal(c.springBack), c.opens]),
  };
}

export function verdicts(base, comp) {
  return {
    band: verdict({ runs: base.band, frames: base.frames }, { runs: comp.band, frames: comp.frames }),
    short: verdict({ runs: base.short, frames: base.frames }, { runs: comp.short, frames: comp.frames }),
  };
}

/** The counts of several passes: field-wise sums. Lean `total`. */
export const totalCounts = (cs) => ({
  opens: sum(cs.map((c) => c.opens)), closes: sumDir(cs.map((c) => c.closes)), reopens: sumDir(cs.map((c) => c.reopens)),
  springBack: sumDir(cs.map((c) => c.springBack)),
});

/** A pass's count per 1000 open starts, null with no open start. Lean `perThousand`. */
export const perThousand = (count, opens) => (opens === 0 ? null : Math.floor((count * 1000) / opens));

/** The rates of passes given as [count, open starts]. Lean `rates`. */
export const rates = (ps) => ps.map(([c, o]) => perThousand(c, o)).filter((x) => x !== null);

/** win, trade or no-win from the comparison of reversals and fights and whether the still runs lifted or got worse. Lean `brickVerdict`. */
export function brickVerdict(rev, fight, stillLifted, stillWorse) {
  const better = (rev === 'lower' ? 1 : 0) + (fight === 'lower' ? 1 : 0) + (stillLifted ? 1 : 0);
  const worse = (rev === 'higher' ? 1 : 0) + (fight === 'higher' ? 1 : 0) + (stillWorse ? 1 : 0);
  return better === 0 ? 'no-win' : worse === 0 ? 'win' : 'trade';
}

/** One stretch per pass, as [count, open starts] pairs with one open start each. Lean `perStretch`. */
export const perStretch = (counts) => counts.map((c) => [c, 1]);

/**
 * The still runs are worse when, in every job with a rate on both sides, every brick pass is above every faithful pass of that job, and
 * at least one job can be compared. Jobs are [faithful passes, brick passes], each pass [still runs, finish-zone frames]. Lean `stillWorseOf`.
 */
export function stillWorseOf(jobs) {
  const ok = jobs.filter(([f, c]) => rates(f).length > 0 && rates(c).length > 0);
  return ok.length > 0 && ok.every(([f, c]) => cmp(rates(f), rates(c)) === 'higher');
}

/** Lean `verdictOf`: reversals and fights as [count, open starts] per pass, still runs as jobs of [runs, frames] passes, faithful against brick. */
export const verdictOf = (faithRev, candRev, faithFight, candFight, stillJobs, stillLifted) =>
  brickVerdict(cmp(rates(faithRev), rates(candRev)), cmp(rates(faithFight), rates(candFight)), stillLifted, stillWorseOf(stillJobs));

/**
 * The reversals and spring-back fights of the first open stretch of a pass, or null when the pass has none or the pin-turn reducer
 * refuses it. TS glue over the Lean-checked reducers: the stretch comes from `stretches`, its reversals from the TouchLock twin, its
 * fights from `springBack` over the writes that fall in the stretch.
 */
export function firstStretch(rec) {
  const st = stretches(rec.o)[0];
  if (!st || !hasMorphReads(rec)) return null;
  const [a, b] = st;
  const o = rec.o.map((_, i) => (i >= a && i <= b ? 1 : 0));
  const k = lockCounts({ ...rec, o });
  if (!k.stretches) return null;
  const writes = (rec.ca ?? []).filter((c) => c[2] >= a && c[2] <= b + 1);
  return { reversals: k.reversals, fights: dirTotal(springBack(rec.y, rec.d, writes)) };
}
