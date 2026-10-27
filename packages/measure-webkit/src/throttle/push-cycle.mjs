import { stretches } from './morph-end.mjs';
import { reduce as lockReduce, refusal as lockRefusal } from '../touchlock.mjs';

export const CYCLES = 6;
export const LEG_FRAMES = 24;
export const THROTTLE_MS = 100;
export const MiB = 1024 * 1024;
export const H1_MIN_CHANGES = 3;
export const H1_MIN_SLOW = 5;
export const TICK = 1600;
export const LIFT_GAP = 3200;
export const FINGER_X = 215;
export const START_Y = 700;
export const STEP_PX = 14;
export const TOP_Y = START_Y - STEP_PX * (LEG_FRAMES - 1);

export const single = (c) => c.first + c.promo + c.run;
export const openWork = (c, keep, k) => c.run + (k === 0 ? c.first : 0) + (k === 0 || !keep ? c.promo : 0);
export const cycleWork = (c, keep, k) => openWork(c, keep, k) + c.close + c.toolbar;
export const series = (c, keep, n) => Array.from({ length: n }, (_, k) => cycleWork(c, keep, k));
export const totalWork = (c, keep, n) => series(c, keep, n).reduce((a, b) => a + b, 0);

const sum = (l) => l.reduce((a, b) => a + b, 0);

export function trend(xs) {
  if (xs.length === 0) return 'flat';
  const [f, ...t] = xs;
  if (6 * t.length * f < 5 * sum(t)) return 'rises';
  if (6 * sum(t) < 5 * t.length * f) return 'falls';
  return 'flat';
}

export const cycleFlags = (n) => Array.from({ length: n }, () => [false, true]).flat();
export function reattachPaint(area, flags) {
  let s = 0;
  for (let i = 0; i + 1 < flags.length; i++) if (flags[i + 1] && !flags[i]) s += area;
  return s;
}
export const cyclePx = (dpr, a, n) => reattachPaint(a, cycleFlags(n)) * dpr ** 2;
export const poolCap = (mac) => (mac ? 256 * MiB : 64 * MiB);
export const realloc = (cap, released) => released - Math.min(released, cap);

export const updatesIn = (span) => Math.floor(span / THROTTLE_MS) + 1;
export function h1Verdict(o) {
  if (o.changes < H1_MIN_CHANGES) return 'open';
  if (o.slowNear + o.slowFar < H1_MIN_SLOW) return 'open';
  if (o.framesNear === 0 || o.framesFar === 0) return 'open';
  return 2 * o.slowFar * o.framesNear <= o.slowNear * o.framesFar ? 'holds' : 'refuted';
}

export function h2Verdict(o) {
  if (o.stretchesFirst === 0 || o.stretchesLater < 2) return 'open';
  return o.fightsFirst * o.stretchesLater < o.fightsLater * o.stretchesFirst ? 'holds' : 'refuted';
}

export function h3Verdict(o) {
  if (o.cyclesSeen < 3 || o.firstCyclePx === 0) return 'open';
  if (o.firstCyclePx <= o.laterCyclePx) return 'holds';
  return 2 * o.laterCyclePx < o.firstCyclePx ? 'refuted' : 'open';
}
export function h4Verdict(o) {
  if (o.freedBytes === 0) return 'open';
  if (o.freedBytes <= 64 * MiB) return 'refuted';
  return o.freedBytes <= 256 * MiB ? 'holds' : 'open';
}

export const dwellFrames = (ms) => Math.floor((ms * 60) / 1000);
export const cycleLen = (d) => 2 * LEG_FRAMES + 2 * d;
export const endFrame = (n, d) => n * cycleLen(d);
export const windowOf = (d, k) => [k * cycleLen(d), (k + 1) * cycleLen(d)];

export function phoneSamples(ms) {
  const dw = ms * 100;
  const up = Array.from({ length: LEG_FRAMES }, (_, i) => [TICK * i, FINGER_X * 10, (START_Y - STEP_PX * i) * 10]);
  const t1 = TICK * (LEG_FRAMES - 1) + dw;
  const down = Array.from({ length: LEG_FRAMES }, (_, i) => [t1 + TICK * (i + 1), FINGER_X * 10, (TOP_Y + STEP_PX * (i + 1)) * 10]);
  const t2 = t1 + TICK * LEG_FRAMES + dw;
  return [...up, [t1, FINGER_X * 10, TOP_Y * 10], ...down, [t2, FINGER_X * 10, (TOP_Y + STEP_PX * LEG_FRAMES) * 10]];
}
export const phoneLift = (ms) => TICK * (2 * LEG_FRAMES - 1) + 2 * ms * 100 + TICK;
export function phoneProfile(n, ms) {
  const lift = phoneLift(ms);
  return {
    id: `push-cycle-${n}x${ms}`, w: 430, h: 775, load: 'warm',
    swipes: Array.from({ length: n }, (_, i) => ({ start: i * (lift + LIFT_GAP), lift, s: phoneSamples(ms) })),
  };
}

export const SLOW = Object.freeze([34, 50]);
export const NEAR_MS = 300;

const median = (xs) => {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
};

export function viewportChanges(rec) {
  const frames = [];
  for (let i = 1; i < rec.t.length; i++) if (rec.ih[i] !== rec.ih[i - 1] || rec.vh[i] !== rec.vh[i - 1]) frames.push(i);
  const groups = [];
  for (const i of frames) {
    const g = groups[groups.length - 1];
    if (g && rec.t[i] - rec.t[g[g.length - 1]] < NEAR_MS) g.push(i); else groups.push([i]);
  }
  return groups.map((g) => ({ first: g[0], last: g[g.length - 1] }));
}

export function nearMask(rec, groups = viewportChanges(rec)) {
  const near = new Array(rec.t.length).fill(false);
  for (const g of groups) {
    const end = rec.t[g.last] + NEAR_MS;
    for (let i = g.first; i < rec.t.length && rec.t[i] <= end; i++) near[i] = true;
  }
  return near;
}

export function cycleRanges(rec) {
  const st = stretches(rec.o);
  return st.map(([a], k) => [a, k + 1 < st.length ? st[k + 1][0] - 1 : rec.t.length - 1]);
}

function lockOf(rec, a, b) {
  const frames = [];
  for (let i = a; i <= b; i++) frames.push([rec.y[i], 1]);
  const calls = (rec.ca ?? []).filter((c) => c[2] >= a && c[2] <= b + 1).map((c) => [c[0], 1]);
  const run = { frames, events: [], calls };
  if (lockRefusal(run)) return null;
  const k = lockReduce(run);
  return { reversals: k.frameReversals, fights: k.frameFights, displaced: k.displacedFrames };
}

/** True when the gap that ends at frame i overlaps a quiet range (a census or a rest, in page ms): it is not a cycle's frame. */
export const maskedGap = (rec, i) => (rec.quiet ?? []).some(([a, b]) => rec.t[i - 1] < b && rec.t[i] > a);

export function recordCycles(rec) {
  const near = nearMask(rec);
  const st = stretches(rec.o);
  const evAt = (xs, a, b) => (xs ?? []).filter((f) => f >= a && f <= b).length;
  return cycleRanges(rec).map(([a, b], k) => {
    const gaps = [];
    for (let i = a + 1; i <= b; i++) if (!maskedGap(rec, i)) gaps.push(rec.t[i] - rec.t[i - 1]);
    const [oa, ob] = st[k];
    let nearFrames = 0, slowNear34 = 0, slowNear50 = 0, slowFar34 = 0, slowFar50 = 0;
    for (let i = a + 1; i <= b; i++) {
      if (maskedGap(rec, i)) continue;
      const g = rec.t[i] - rec.t[i - 1];
      if (near[i]) { nearFrames++; slowNear34 += g > 34; slowNear50 += g > 50; } else { slowFar34 += g > 34; slowFar50 += g > 50; }
    }
    const groups = viewportChanges(rec).filter((g) => g.first >= a && g.first <= b);
    return {
      k, from: a, to: b, frames: b - a + 1, openFrames: ob - oa + 1,
      slow34: gaps.filter((g) => g > 34).length, slow50: gaps.filter((g) => g > 50).length,
      medianGap: median(gaps), maxGap: gaps.length ? Math.max(...gaps) : null,
      viewportChanges: groups.length, nearFrames, farFrames: gaps.length - nearFrames, slowNear34, slowNear50, slowFar34, slowFar50,
      resizes: evAt(rec.rz, a, b), vvResizes: evAt(rec.vvr, a, b), vvScrolls: evAt(rec.vvs, a, b),
      lock: lockOf(rec, oa, ob),
    };
  });
}

export function verdictInputs(passes, thr = 34) {
  const key = thr === 50 ? ['slowNear50', 'slowFar50'] : ['slowNear34', 'slowFar34'];
  const h1 = { changes: 0, slowNear: 0, framesNear: 0, slowFar: 0, framesFar: 0 };
  const h2 = { stretchesFirst: 0, fightsFirst: 0, stretchesLater: 0, fightsLater: 0 };
  for (const cyc of passes.map(recordCycles)) {
    for (const c of cyc) {
      h1.changes += c.viewportChanges; h1.slowNear += c[key[0]]; h1.framesNear += c.nearFrames; h1.slowFar += c[key[1]]; h1.framesFar += c.farFrames;
      if (!c.lock) continue;
      if (c.k === 0) { h2.stretchesFirst++; h2.fightsFirst += c.lock.fights; } else { h2.stretchesLater++; h2.fightsLater += c.lock.fights; }
    }
  }
  return { h1, h2 };
}

export function indexSeries(passes, field, n = CYCLES) {
  const out = new Array(n).fill(0), seen = new Array(n).fill(0);
  for (const cyc of passes.map(recordCycles)) cyc.slice(0, n).forEach((c, k) => { out[k] += c[field] ?? 0; seen[k]++; });
  return { sums: out, passes: seen };
}

export const USER_FLAGS = Object.freeze([
  'nav:earn-logical', 'hero.countdown:strip', 'platform:fade-threaded', 'platform.glint:offscreen-pause', 'platform.sweep:offscreen-pause',
  'morph.columns:idle-none', 'morph.countdown:strip', 'engine.events:quiet', 'engine.scroll:unthrottle',
]);

const NEEDS = Object.freeze({ 'hero.countdown:strip': ['morph.countdown:strip'] });

/** Arms of task morph-push-sim: the rewrite without the flag, with morph.geom, and with morph.geom and the timed tween. */
export const MORPH_ARMS = Object.freeze({
  'morph-base': '', 'morph-geom': '?fw=morph.geom:on', 'morph-timed': '?fw=morph.geom:on,morph.tween:geom-timed',
});

export function searchOf(arm) {
  if (arm === 'original') return null;
  if (arm === 'rewrite') return '';
  if (arm === 'user') return `?fw=${USER_FLAGS.join(',')}`;
  if (arm in MORPH_ARMS) return MORPH_ARMS[arm];
  if (arm.startsWith('off-')) {
    const gone = [arm.slice(4), ...(NEEDS[arm.slice(4)] ?? [])];
    const rest = USER_FLAGS.filter((f) => !gone.includes(f));
    if (rest.length === USER_FLAGS.length) throw new Error(`unknown flag in ${arm}`);
    return `?fw=${rest.join(',')}`;
  }
  throw new Error(`unknown arm ${arm}`);
}

export const uploadName = (name) => name.replace(/[:<>|*?"\\]/g, '_');

export const searchesOf = (arms) => [...new Set(arms.filter((a) => a !== 'original' && a !== 'rewrite').map(searchOf))].filter((s) => s !== '');

export const SEP_MIN_PASSES = 3;
export const SEP_DWELL_CYCLES = 6;
export const SEP_WINDOW = Object.freeze([3, 4, 5]);
export const SEP_LAST_READ = 5;
export const SEP_MEASURED_STRETCH = 2391;
export const SEP_MARGIN_PCT = 25;

export const stretch = (dwellMs, fullMs) => (fullMs === 0 ? 0 : Math.floor((dwellMs * 1000) / fullMs));
export const clockIndex = (r, k) => Math.floor((k * r + 500) / 1000);
export const fullCyclesFor = (r) => clockIndex(r, SEP_LAST_READ) + 1;
export const SEP_STRETCH_BOUND = SEP_MEASURED_STRETCH + Math.floor((SEP_MEASURED_STRETCH * SEP_MARGIN_PCT) / 100);
export const SEP_FULL_CYCLES = fullCyclesFor(SEP_STRETCH_BOUND);
export const windowObs = (p, idx) => SEP_WINDOW.flatMap((k) => (idx(k) < p.length ? [p[idx(k)]] : []));
export const sepWindowOf = (ps, idx) => ps.flatMap((p) => windowObs(p, idx));
export const rate = (xs) => (xs.length === 0 ? 0 : Math.floor((sum(xs) * 1000) / xs.length));
const absDiff = (a, b) => Math.abs(a - b);
export const separable = (i, c) => Math.max(i, c) > 0 && Math.max(i, c) <= 2 * absDiff(i, c);

export function pick(i, c, d) {
  if (!separable(i, c)) return 'undecided:inseparable';
  if (3 * absDiff(d, i) <= absDiff(d, c)) return 'cycleDriven';
  if (3 * absDiff(d, c) <= absDiff(d, i)) return 'clockDriven';
  return 'undecided:between';
}

export function sepVerdict(s) {
  const r = stretch(s.periodDwell, s.periodFull);
  if (s.full.length < SEP_MIN_PASSES) return 'undecided:fewFull';
  if (s.dwell.length < SEP_MIN_PASSES) return 'undecided:fewDwell';
  if (s.periodFull === 0 || s.periodDwell === 0) return 'undecided:noPeriod';
  if (SEP_FULL_CYCLES <= clockIndex(r, 5)) return 'undecided:noRoom';
  const idx = sepWindowOf(s.full, (k) => k), clk = sepWindowOf(s.full, (k) => clockIndex(r, k)), dw = sepWindowOf(s.dwell, (k) => k);
  if (!idx.length || !clk.length || !dw.length) return 'undecided:noObs';
  return pick(rate(idx), rate(clk), rate(dw));
}

export const across = (ts) => {
  if (ts.length < SEP_MIN_PASSES) return 'few';
  if (ts.every((t) => t === 'rises')) return 'yes';
  if (ts.every((t) => t !== 'rises')) return 'no';
  return 'mixed';
};
export const readCensus = (passes) => across(passes.map(trend));
export const restMs = (target, spent, cap) => Math.min(Math.max(target - spent, 0), cap);

export function periodMs(rec) {
  const st = stretches(rec.o);
  return st.length > 5 ? Math.round((rec.t[st[5][0]] - rec.t[st[0][0]]) / 5) : 0;
}

export const slowCounts = (rec, thr = 50) => recordCycles(rec).map((c) => (thr === 50 ? c.slow50 : c.slow34));

export const POST_MS = 8000;

export function activeQuiet(rec, postMs = POST_MS) {
  const st = stretches(rec.o);
  const quiet = [];
  let from = -Infinity;
  st.forEach(([a, b], k) => {
    quiet.push([from, rec.t[a]]);
    from = Math.min(rec.t[b] + postMs, k + 1 < st.length ? rec.t[st[k + 1][0]] : Infinity);
  });
  quiet.push([from, Infinity]);
  return [...quiet, ...(rec.quiet ?? [])];
}

export const activeCycles = (rec, postMs = POST_MS) => recordCycles({ ...rec, quiet: activeQuiet(rec, postMs) });

export const censusSeries = (pass, field) => (pass.census ?? []).filter((c) => c.k >= 0 && c.k < SEP_DWELL_CYCLES).map((c) => c[field]);

const meanInt = (xs) => (xs.length ? Math.round(sum(xs) / xs.length) : 0);

export function sepArm(passes, thr = 50) {
  const full = passes.filter((p) => p.profile === 'full'), dwell = passes.filter((p) => p.profile === 'dwell');
  const key = thr === 50 ? 'slow50' : 'slow34';
  const input = {
    full: full.map((p) => activeCycles(p.rec).map((c) => c[key])), dwell: dwell.map((p) => activeCycles(p.rec).map((c) => c[key])),
    periodFull: meanInt(full.map((p) => periodMs(p.rec)).filter(Boolean)), periodDwell: meanInt(dwell.map((p) => periodMs(p.rec)).filter(Boolean)),
  };
  const census = Object.fromEntries(['layers', 'bytes', 'created'].map((f) => [f, readCensus(dwell.map((p) => censusSeries(p, f)))]));
  const trends = Object.fromEntries(['layers', 'bytes', 'created'].map((f) => [f, dwell.map((p) => trend(censusSeries(p, f)))]));
  const r = stretch(input.periodDwell, input.periodFull);
  const rates = { idx: rate(sepWindowOf(input.full, (k) => k)), clk: rate(sepWindowOf(input.full, (k) => clockIndex(r, k))), dwell: rate(sepWindowOf(input.dwell, (k) => k)) };
  return { input, verdict: sepVerdict(input), r, fits: r <= SEP_STRETCH_BOUND, rates, census, trends };
}
