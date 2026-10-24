// Twin of lean/Fw/Device/Session.lean (TS stand-in until the reductions run as fwcore); test/device-record.test.mjs checks every
// function against golden/device/session.jsonl. Integer units: times in hundredths of a ms, positions in tenth px, part values
// per mille. Nothing is decided here that Lean does not decide; reducePass/compareZones are maps over those decisions.
import { readFileSync } from 'node:fs';
import { replayOk as loaderOk } from '../../measure-chromium/src/profile.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/session.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
/** The constants Lean owns, read from the generated golden. */
export const CONST = Object.freeze(GOLDEN.find((l) => l.kind === 'consts'));
const PLANS = new Map();
for (const { set, step, arm, seconds, text } of GOLDEN.filter((l) => l.kind === 'plan')) {
  if (!PLANS.has(set)) PLANS.set(set, []);
  PLANS.get(set).push(Object.freeze({ step, arm, seconds, text }));
}
/** The session plan for the rewrite arms that stay (`['rewrite','v2']`, ...): one entry per step, with the banner text Lean wrote. */
export function planFor(kept) {
  const p = PLANS.get(kept.join('+'));
  if (!p) throw new Error(`no plan for the arms [${kept}] (Lean writes plans for ${[...PLANS.keys()].join(' | ')})`);
  return Object.freeze(p);
}
/** The longest plan (all three rewrite arms). */
export const PLAN = planFor(['rewrite', 'v2', 'look']);

/** Lean `sameFlags`: two flag lists name the same page when each entry of one is in the other. */
export const sameFlags = (a, b) => a.every((x) => b.includes(x)) && b.every((x) => a.includes(x));

/** Lean `dedupArms`: the arms of [[arm, flags]] that stay; an arm whose flags equal those of an earlier kept arm is dropped. */
export function dedupArms(xs) {
  const seen = [], out = [];
  for (const [arm, flags] of xs) if (!seen.some((s) => sameFlags(flags, s))) { seen.push(flags); out.push(arm); }
  return out;
}
export const ZONES = Object.freeze(['hero', 'finish', 'rest']);

export const zoneOf = (vh10, maxY10, y) => (y < 2 * vh10 ? 'hero' : maxY10 - y < vh10 ? 'finish' : 'rest');

/** Moving frames of [t, y] pairs: {dt, y} where the position changed from the frame before. */
export function movingRows(frames) {
  const rows = [];
  for (let i = 1; i < frames.length; i++) if (frames[i][1] !== frames[i - 1][1]) rows.push({ dt: frames[i][0] - frames[i - 1][0], y: frames[i][1] });
  return rows;
}

const maxOf0 = (l) => l.reduce((m, v) => Math.max(m, v), 0);
const per100 = (k, n) => (n === 0 ? 0 : Math.floor((10000 * k) / n));
const medianOf = (dts) => { const s = [...dts].sort((a, b) => a - b); return s[Math.floor(s.length / 2)] ?? 0; };

/** Counts over 34 and 50 ms, per 100 frames (hundredths), longest and median interval of a set of moving frames. */
export function stat(rows) {
  const over34 = rows.filter((r) => CONST.slow < r.dt).length;
  const over50 = rows.filter((r) => CONST.bad < r.dt).length;
  const dts = rows.map((r) => r.dt);
  return { n: rows.length, over34, over50, per34: per100(over34, rows.length), per50: per100(over50, rows.length), longest: maxOf0(dts), median: medianOf(dts) };
}

export const inZone = (vh10, maxY10, z, rows) => rows.filter((r) => zoneOf(vh10, maxY10, r.y) === z);

export const spread = (l) => (l.length === 0 ? 0 : Math.max(...l) - Math.min(...l));

/** An arm beats (or loses to) the original only beyond the original's pass-to-pass spread; lower is better. */
export function verdict(orig, arm) {
  if (orig.length < 2 || arm.length === 0) return 'unresolved';
  const sp = spread(orig);
  if (Math.max(...arm) + sp < Math.min(...orig)) return 'beats';
  if (Math.max(...orig) + sp < Math.min(...arm)) return 'worse';
  return 'same';
}

/**
 * Lean `partSeries`: each value paired with the scroll position it was computed from. The recorder's rAF callback runs before the
 * page's in a frame, so the value read in frame i+1 is the one the page wrote in frame i from ys[i].
 */
export const partSeries = (ys, vs) => ys.slice(0, Math.max(0, vs.length - 1)).map((y, i) => [y, vs[i + 1]]);

/** Frame pairs in which the page moved but the part's value stayed mid-transition (pairs from `partSeries`). */
export function stalls(series) {
  let n = 0;
  for (let i = 1; i < series.length; i++) {
    const [a, b] = [series[i - 1], series[i]];
    if (a[0] !== b[0] && a[1] === b[1] && a[1] > 0 && a[1] < 1000) n++;
  }
  return n;
}

export function maxStep(series) {
  let m = 0;
  for (let i = 1; i < series.length; i++) m = Math.max(m, Math.abs(series[i][1] - series[i - 1][1]));
  return m;
}

/** Strokes of a touch stream [t, ph, x, y, n]: start to stop; a cancel or a second start drops the open one. */
export function strokes(touches) {
  const out = [];
  let cur = null;
  for (const e of touches) {
    if (cur === null) { if (e[1] === 's') cur = [e]; continue; }
    if (e[1] === 's') cur = [e];
    else if (e[1] === 'm') cur.push(e);
    else if (e[1] === 'e') { cur.push(e); out.push(cur); cur = null; }
    else cur = null;
  }
  return out;
}

export function isTap(s) {
  if (s.length === 0) return false;
  const [a, z] = [s[0], s[s.length - 1]];
  return z[0] - a[0] <= CONST.tapMs && s.every((e) => Math.abs(e[2] - a[2]) <= CONST.tapTravel && Math.abs(e[3] - a[3]) <= CONST.tapTravel);
}

/** A tap: [end time, start x, start y]. */
export const tapOf = (s) => (isTap(s) ? [s[s.length - 1][0], s[0][2], s[0][3]] : null);
export const taps = (touches) => strokes(touches).map(tapOf).filter((t) => t !== null);

const near = (a, b) => Math.abs(a[1] - b[1]) <= CONST.nearPx && Math.abs(a[2] - b[2]) <= CONST.nearPx;
const triple = (a, b, c) => b[0] - a[0] <= CONST.gapMs && c[0] - b[0] <= CONST.gapMs && near(a, b) && near(b, c);

/** The third tap of every triple tap, scanning from the left; a mark uses its three taps once. */
export function marksOf(tp) {
  const out = [];
  let i = 0;
  while (i + 2 < tp.length) {
    if (triple(tp[i], tp[i + 1], tp[i + 2])) { out.push(tp[i + 2]); i += 3; } else i++;
  }
  return out;
}

export function yAt(frames, t) {
  const before = frames.filter((f) => f[0] <= t);
  return before.length > 0 ? before[before.length - 1][1] : frames.length > 0 ? frames[0][1] : 0;
}

export function feltOf(vh10, maxY10, frames, m) {
  const y = yAt(frames, m[0]);
  const win = frames.filter((f) => m[0] - CONST.lookback <= f[0] && f[0] <= m[0]);
  return { t: m[0], y, zone: zoneOf(vh10, maxY10, y), stat: stat(movingRows(win)) };
}

export const frameOf = (t0, t) => Math.max(0, Math.floor(((t - t0) * CONST.hz) / 100000));

const clampPt = (w10, h10, [x, y]) => [Math.max(0, Math.min(w10, x)), Math.max(0, Math.min(h10, y))];

function posAt(s, t0, j) {
  const before = s.filter((e) => frameOf(t0, e[0]) <= j);
  const e = before.length > 0 ? before[before.length - 1] : s[0];
  return [e[2], e[3]];
}

export function strokeOf(t0, floor, w10, h10, s) {
  const ks = Math.max(frameOf(t0, s[0][0]), floor);
  const ke = Math.max(frameOf(t0, s[s.length - 1][0]), ks + 1);
  return { f0: ks, path: Array.from({ length: ke - ks + 1 }, (_, i) => clampPt(w10, h10, posAt(s, t0, ks + i))) };
}

export const replayStrokes = (touches) => strokes(touches).filter((s) => !isTap(s));
export const t0Of = (ss) => (ss.length > 0 ? ss[0][0][0] : 0);
export const singleFinger = (touches) => touches.every((e) => e[4] <= 1);

/** The replay strokes of a pass in a w x h px viewport, null when a second finger was ever down. */
export function replay(touches, w, h) {
  if (!singleFinger(touches)) return null;
  const ss = replayStrokes(touches), t0 = t0Of(ss);
  const out = [];
  let floor = 0;
  for (const s of ss) {
    const st = strokeOf(t0, floor, w * 10, h * 10, s);
    out.push(st);
    floor = st.f0 + st.path.length;
  }
  return out;
}

/** Frame of each felt mark on the replay grid. */
export function markFrames(touches) {
  const t0 = t0Of(replayStrokes(touches));
  return marksOf(taps(touches)).map((m) => frameOf(t0, m[0]));
}

/** What the CI profile loader accepts of a replay (the loader's own check, run here before a profile is written). */
export const replayOk = (w, h, strokes_) => loaderOk(w * 10, h * 10, CONST.maxReplayFrames, strokes_);

/** Lean `reducePass`: the record in integer form -> the report. */
export function reducePass(r) {
  const frames = r.t.map((t, i) => [t, r.y[i]]);
  const vh10 = r.h * 10;
  const rows = movingRows(frames);
  const tp = taps(r.touches);
  return {
    total: stat(rows),
    zones: Object.fromEntries(ZONES.map((z) => [z, stat(inZone(vh10, r.maxY10, z, rows))])),
    taps: tp.length,
    felt: marksOf(tp).map((m) => feltOf(vh10, r.maxY10, frames, m)),
    parts: Object.fromEntries(Object.entries(r.p).map(([n, vs]) => [n, { maxStep: maxStep(r.y.map((y, i) => [y, vs[i]])), stalls: stalls(partSeries(r.y, vs)) }])),
  };
}

/**
 * The comparison of arms: for every zone (and the whole pass) the per-pass count over 50 ms per 100 frames of each arm, and
 * Lean's verdict of each non-original arm against the original passes. `reports` is [{arm, report}].
 */
export function compareZones(reports) {
  const arms = [...new Set(reports.map((x) => x.arm))];
  const keys = ['total', ...ZONES];
  const val = (rep, k) => (k === 'total' ? rep.total : rep.zones[k]).per50;
  const per = (arm, k) => reports.filter((x) => x.arm === arm).map((x) => val(x.report, k));
  return keys.map((k) => ({
    zone: k, original: per('original', k), spread: spread(per('original', k)),
    arms: arms.filter((a) => a !== 'original').map((a) => ({ arm: a, per50: per(a, k), verdict: verdict(per('original', k), per(a, k)) })),
  }));
}

export const CLASS_CONST = Object.freeze(GOLDEN.find((l) => l.kind === 'class.consts'));
export const CLASSES = Object.freeze(['moving', 'still']);

const jumpAt = (vh, k) => k < vh.length && Math.abs(vh[k] - vh[Math.max(0, k - 1)]) >= CLASS_CONST.moveMin;

export function movingAt(vh, i) {
  for (let k = Math.max(0, i + 1 - CLASS_CONST.moveWin); k <= i + CLASS_CONST.moveWin; k++) if (jumpAt(vh, k)) return true;
  return false;
}

export const classes = (vh) => vh.map((_, i) => (movingAt(vh, i) ? 'moving' : 'still'));

export const hasField = (r) => Array.isArray(r.vh) && r.vh.length > 0 && r.vh.length === r.t.length;
export const classesOf = (r) => (hasField(r) ? classes(r.vh) : r.t.map(() => 'still'));

export function movingRowsC(frames) {
  const rows = [];
  for (let i = 1; i < frames.length; i++) {
    if (frames[i][1] !== frames[i - 1][1]) rows.push({ cls: frames[i][2], row: { dt: frames[i][0] - frames[i - 1][0], y: frames[i][1] } });
  }
  return rows;
}

export function reduceClass(r, c) {
  const cs = classesOf(r);
  const n = Math.min(r.t.length, r.y.length, cs.length);
  const fs = Array.from({ length: n }, (_, i) => [r.t[i], r.y[i], cs[i]]);
  const vh10 = r.h * 10;
  const rows = movingRowsC(fs).filter((x) => x.cls === c).map((x) => x.row);
  return {
    total: stat(rows),
    zones: Object.fromEntries(ZONES.map((z) => [z, stat(inZone(vh10, r.maxY10, z, rows))])),
    frames: fs.filter((f) => f[2] === c).length,
  };
}

export const reduceByClass = (r) => ({ moving: reduceClass(r, 'moving'), still: reduceClass(r, 'still') });

export const classVals = (z, rs) => rs.filter((r) => r.frames !== 0).map((r) => (z === null ? r.total : r.zones[z] ?? { per50: 0 }).per50);

export const compareClass = (z, orig, arm) => verdict(classVals(z, orig), classVals(z, arm));

export function compareClasses(reports) {
  const arms = [...new Set(reports.map((x) => x.arm))];
  return CLASSES.flatMap((c) => ['total', ...ZONES].map((k) => {
    const z = k === 'total' ? null : k;
    const per = (arm) => classVals(z, reports.filter((x) => x.arm === arm).map((x) => x[c]));
    return {
      class: c, zone: k, original: per('original'),
      arms: arms.filter((a) => a !== 'original').map((a) => ({ arm: a, vals: per(a), verdict: verdict(per('original'), per(a)) })),
    };
  }));
}

export function normalize(rec) {
  const c = (v, k) => Math.round(v * k);
  return {
    schema: 'fw.phone.record.int/1', arm: rec.arm, pass: rec.pass, w: rec.viewport.w, h: rec.viewport.h, maxY10: c(rec.maxY, 10),
    t: rec.frames.t.map((v) => c(v, 100)), y: rec.frames.y.map((v) => c(v, 10)), p: rec.frames.p,
    touches: rec.touches.map(([t, ph, x, y, n]) => [c(t, 100), ph, c(x, 10), c(y, 10), n]),
    ...(rec.frames.vh ? { vh: rec.frames.vh.map((v) => c(v, 10)) } : {}),
  };
}

export function denormalize(r) {
  return {
    schema: 'fw.phone.record/1', arm: r.arm, pass: r.pass, viewport: { w: r.w, h: r.h, dpr: 3 }, maxY: r.maxY10 / 10,
    frames: { t: r.t.map((v) => v / 100), y: r.y.map((v) => v / 10), p: r.p, ...(r.vh ? { vh: r.vh.map((v) => v / 10) } : {}) },
    touches: r.touches.map(([t, ph, x, y, n]) => [t / 100, ph, x / 10, y / 10, n]),
  };
}

export const CONST2 = Object.freeze(GOLDEN.find((l) => l.kind === 'v2.consts'));

export const slotOf = (t0, t) => Math.floor(((t - t0) * CONST2.slotNum + CONST2.slotHalf) / CONST2.slotDen);

export function framesOf(r) {
  const parts = Object.values(r.p ?? {});
  const n = Math.min(r.t.length, r.y.length);
  return Array.from({ length: n }, (_, k) => [r.t[k], r.y[k], parts.map((vs) => vs[k] ?? 0)]);
}

const sameList = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

export function ivs(frames) {
  if (frames.length === 0) return [];
  const t0 = frames[0][0];
  const out = [];
  for (let i = 1; i < frames.length; i++) {
    const [a, b] = [frames[i - 1], frames[i]];
    const moving = b[1] !== a[1];
    out.push([i, b[0], b[0] - a[0], slotOf(t0, b[0]) - slotOf(t0, a[0]), b[1], moving, moving || !sameList(a[2], b[2])]);
  }
  return out;
}
const I = Object.freeze({ i: 0, t: 1, dt: 2, dk: 3, y: 4, moving: 5, animating: 6 });

export const skip = (v) => v[I.dk] > 1;
export const bandOf = (h) => (h <= CONST2.bands[0] ? 'good' : h <= CONST2.bands[1] ? 'warning' : h <= CONST2.bands[2] ? 'critical' : 'urgent');

const sortI = (l) => [...l].sort((a, b) => a - b);
export const medianL = (l) => sortI(l)[Math.floor(l.length / 2)] ?? 0;
export const p95L = (l) => sortI(l)[Math.max(0, Math.floor((95 * l.length + 99) / 100) - 1)] ?? 0;

export function run30(vs) {
  let last = -2, cur = 0, best = 0;
  for (const v of vs) {
    if (!skip(v)) continue;
    cur = v[I.i] === last + 1 ? cur + 1 : 1;
    last = v[I.i];
    best = Math.max(best, cur);
  }
  return best;
}

export function stat2(e, vs) {
  const n = vs.length, dts = vs.map((v) => v[I.dt]);
  const count = (p) => vs.filter(p).length;
  const skips = count(skip), over25 = count((v) => CONST2.miss < v[I.dt]);
  const over34 = count((v) => CONST2.slow < v[I.dt]), over50 = count((v) => CONST2.bad < v[I.dt]);
  const span = dts.reduce((s, d) => s + d, 0);
  const late = dts.reduce((s, d) => s + Math.max(0, d - e), 0);
  const hitch = span <= 0 ? 0 : Math.floor((late * 100000) / span);
  return {
    n, skips, lost: vs.reduce((s, v) => s + Math.max(0, v[I.dk] - 1), 0), over25, over34, over50,
    perSkip: per100(skips, n), per25: per100(over25, n), per34: per100(over34, n), per50: per100(over50, n),
    span, late, hitch, band: bandOf(hitch), median: medianL(dts), p95: p95L(dts), longest: maxOf0(dts), run30: run30(vs),
  };
}

export const expected = (vs) => medianL(vs.map((v) => v[I.dt]));

export const tapsW = (touches) => strokes(touches).flatMap((s) => { const tp = tapOf(s); return tp ? [[s[0][0], tp]] : []; });

export function marksW(tp) {
  const out = [];
  let i = 0;
  while (i + 2 < tp.length) {
    if (triple(tp[i][1], tp[i + 1][1], tp[i + 2][1])) { out.push([tp[i][0], tp[i + 2][1]]); i += 3; } else i++;
  }
  return out;
}

export const feltWindow = (anchor, vs) => vs.filter((v) => anchor - CONST2.lookback <= v[I.t] && v[I.t] <= anchor);

export function feltV2(vh10, maxY10, e, frames, vs, [anchor, tap]) {
  const y = yAt(frames, anchor), w = feltWindow(anchor, vs);
  return { y, zone: zoneOf(vh10, maxY10, y), all: stat2(e, w), animating: stat2(e, w.filter((v) => v[I.animating])), oldEmpty: feltOf(vh10, maxY10, frames, tap).stat.n === 0 };
}

export const drags = (touches) => strokes(touches).filter((s) => !isTap(s) && s.every((e) => e[4] <= 1));

export function startLatency(frames, s) {
  const a = s[0], z = s[s.length - 1];
  const before = frames.filter((f) => f[0] <= a[0]);
  if (before.length < 2) return null;
  const [f1, f2] = [before[before.length - 1], before[before.length - 2]];
  if (f1[1] !== f2[1]) return null;
  const f = frames.find((g) => a[0] < g[0] && g[0] <= z[0] && g[1] !== f1[1]);
  return f ? f[0] - a[0] : null;
}

export function fingerY(s, t) {
  const before = s.filter((e) => e[0] <= t);
  return before.length > 0 ? before[before.length - 1][3] : (s[0]?.[3] ?? 0);
}

export function offsetMax(maxY10, frames, s) {
  const a = s[0], z = s[s.length - 1];
  const y0 = yAt(frames, a[0]);
  const during = frames.filter((f) => a[0] < f[0] && f[0] <= z[0]);
  const r = during.find((f) => f[1] !== y0);
  if (!r) return null;
  const after = during.filter((f) => r[0] <= f[0] && 0 < f[1] && f[1] < maxY10);
  return after.reduce((m, f) => Math.max(m, Math.abs((f[1] - r[1]) - (fingerY(s, r[0]) - fingerY(s, f[0])))), 0);
}

const SELS = Object.freeze({ all: () => true, animating: (v) => v[I.animating], moving: (v) => v[I.moving] });
const ZONE_KEYS = Object.freeze(['whole', ...ZONES]);

export function reduceV2(r) {
  const frs = framesOf(r), vs = ivs(frs), e = expected(vs), vh10 = r.h * 10;
  const frames = frs.map((f) => [f[0], f[1]]);
  const idx = frs.findIndex((f) => zoneOf(vh10, r.maxY10, f[1]) === 'finish');
  const fe = idx < 0 ? frs.length : idx;
  const zoneKeep = (z) => (z === 'whole' ? () => true : (v) => zoneOf(vh10, r.maxY10, v[I.y]) === z);
  const part = (keep) => Object.fromEntries(Object.entries(SELS).map(([s, k]) => [s, stat2(e, vs.filter((v) => keep(v) && k(v)))]));
  const ds = drags(r.touches);
  return {
    expected: e,
    sets: Object.fromEntries(Object.entries(SELS).map(([s, k]) => [s, Object.fromEntries(ZONE_KEYS.map((z) => [z, stat2(e, vs.filter((v) => k(v) && zoneKeep(z)(v)))]))])),
    traversal: { first: part((v) => v[I.i] <= fe), later: part((v) => fe < v[I.i]) },
    felt: marksW(tapsW(r.touches)).map((m) => feltV2(vh10, r.maxY10, e, frames, vs, m)),
    starts: ds.map((s) => startLatency(frames, s)).filter((d) => d !== null),
    offsets: ds.map((s) => offsetMax(r.maxY10, frames, s)).filter((d) => d !== null),
  };
}

const spreadOf = (l) => ({ n: l.length, median: medianL(l), p95: p95L(l), max: maxOf0(l) });
const FELT_KEYS = Object.freeze(['n', 'skips', 'over25', 'over34', 'over50', 'perSkip', 'hitch', 'band']);
const pick = (o, ks) => Object.fromEntries(ks.map((k) => [k, o[k]]));

export function summarizeV2(date, passes) {
  const out = passes.map(({ arm, pass, record }) => {
    const rep = reduceV2(record);
    return {
      arm, pass, viewport: { w: record.w, h: record.h }, frames: record.t.length, expected: rep.expected, sets: rep.sets,
      traversal: rep.traversal,
      felt: rep.felt.map((f) => ({ zone: f.zone, oldEmpty: f.oldEmpty, all: pick(f.all, FELT_KEYS), animating: pick(f.animating, FELT_KEYS) })),
      touch: { drags: drags(record.touches).length, starts: spreadOf(rep.starts), offsets: spreadOf(rep.offsets) },
    };
  });
  const arms = [...new Set(out.map((p) => p.arm))];
  const felt = arms.map((arm) => {
    const fs = out.filter((p) => p.arm === arm).flatMap((p) => p.felt);
    const has = (k) => fs.filter((f) => f.all[k] > 0).length;
    return { arm, marks: fs.length, oldEmpty: fs.filter((f) => f.oldEmpty).length, newEmpty: fs.filter((f) => f.all.n === 0).length,
      skip: has('skips'), over25: has('over25'), over34: has('over34'), over50: has('over50'),
      windowPerSkip: medianL(fs.map((f) => f.all.perSkip)), passPerSkip: out.filter((p) => p.arm === arm).map((p) => p.sets.all.whole.perSkip) };
  });
  const per = (arm, z, k) => out.filter((p) => p.arm === arm).map((p) => p.sets.all[z][k]);
  const compare = ['perSkip', 'hitch'].flatMap((k) => ['whole', ...ZONES].map((z) => ({
    metric: k, zone: z, original: per('original', z, k), spread: spread(per('original', z, k)),
    arms: arms.filter((a) => a !== 'original').map((a) => ({ arm: a, values: per(a, z, k), verdict: verdict(per('original', z, k), per(a, z, k)) })),
  })));
  return {
    schema: 'fw.phone.session.v2/1', date, reduction: 'Fw.Device.Stats.reduceV2', displayHz: 120, pageHz: 60,
    units: { time: 'hundredths of a ms', per: 'hundredths per 100 intervals', hitch: 'hundredths of a ms per s', offset: 'tenth px' },
    passes: out, felt, compare,
  };
}

const ms = (v) => (v / 100).toFixed(1);
const pc = (v) => (v / 100).toFixed(2);

export function summaryV2Md(s) {
  const row = (cells) => `| ${cells.join(' | ')} |`;
  const head = (cells) => [row(cells), row(cells.map(() => '---'))];
  const zoneTable = (set) => [
    ...head(['zone', 'arm', 'pass', 'intervals', 'skipped / 100', '> 25 ms / 100', '> 34 ms / 100', '> 50 ms / 100', 'hitch ms/s', 'band', 'p95 ms', 'longest 30 fps run']),
    ...['whole', ...ZONES].flatMap((z) => s.passes.map((p) => {
      const st = p.sets[set][z];
      return row([z, p.arm, p.pass, st.n, pc(st.perSkip), pc(st.per25), pc(st.per34), pc(st.per50), ms(st.hitch), st.band, ms(st.p95), st.run30]);
    })),
  ];
  return [
    `# Phone session ${s.date}, second reduction`, '',
    `Reduced by Lean \`${s.reduction}\` (TS twin checked against golden/device/session.jsonl). Safari draws the page at ${s.pageHz} Hz on this ${s.displayHz} Hz phone; a slot is 1/60 s counted from the first frame, and a skipped slot is an interval that advanced 2 slots or more. Hitch ms/s: time past the pass median interval per second, Apple Organizer bands (good up to 10, warning up to 25, critical up to 50, urgent above). rAF times are when the page started a frame, not when it reached the glass.`, '',
    '## Every interval, per zone', '', ...zoneTable('all'), '',
    '## Intervals in which the page scrolled or a recorded part changed', '', ...zoneTable('animating'), '',
    '## Verdict against the original passes (every interval)', '',
    ...head(['metric', 'zone', 'original', 'spread', 'arm', 'arm passes', 'verdict']),
    ...s.compare.flatMap((c) => c.arms.map((a) => {
      const f = c.metric === 'hitch' ? ms : pc;
      return row([c.metric === 'hitch' ? 'hitch ms/s' : 'skipped / 100', c.zone, c.original.map(f).join(' / '), f(c.spread), a.arm, a.values.map(f).join(' / '), a.verdict]);
    })), '',
    '## First traversal against later ones (every interval)', '',
    ...head(['arm', 'pass', 'part', 'intervals', 'skipped / 100', '> 25 ms / 100', 'hitch ms/s', 'p95 ms']),
    ...s.passes.flatMap((p) => ['first', 'later'].map((k) => {
      const st = p.traversal[k].all;
      return row([p.arm, p.pass, k, st.n, pc(st.perSkip), pc(st.per25), ms(st.hitch), ms(st.p95)]);
    })), '',
    '## Felt marks, window of 3 s before the first tap, every interval', '',
    ...head(['arm', 'marks', 'first window counted nothing', 'new window empty', 'with a skipped slot', 'with > 25 ms', 'with > 34 ms', 'with > 50 ms', 'window skipped / 100, median', 'pass skipped / 100']),
    ...s.felt.map((f) => row([f.arm, f.marks, f.oldEmpty, f.newEmpty, f.skip, f.over25, f.over34, f.over50, pc(f.windowPerSkip), f.passPerSkip.map(pc).join(' / ')])), '',
    '## Touch', '',
    ...head(['arm', 'pass', 'drags', 'from a still page', 'touch to first moving frame, median ms', 'p95 ms', 'max ms', 'page moved before lift', 'finger offset median px', 'p95 px', 'max px']),
    ...s.passes.map((p) => {
      const { starts: a, offsets: o } = p.touch;
      return row([p.arm, p.pass, p.touch.drags, a.n, ms(a.median), ms(a.p95), ms(a.max), o.n, (o.median / 10).toFixed(1), (o.p95 / 10).toFixed(1), (o.max / 10).toFixed(1)]);
    }), '',
    '## Reading notes', '',
    '- A 3 s felt window holds about 180 intervals. At the pass rates above nearly every window has a skipped slot, so compare the window rate with the pass rate.',
    '- "Animating" keeps a frame when the scroll position or a recorded part (hero, people, fade) changed. The morph tween under scroll lock is not a recorded part; its frames are only in "every interval".',
    '- A drag is a stroke that is not a tap, with one finger. Touch latency counts drags that started on a still page and scrolled it before the finger lifted. The finger offset counts the drags in "page moved before lift".',
    '- The expected interval is the pass median at the 1 ms rAF rounding, so a 16 / 17 ms alternation adds no hitch time.',
    '- Slots are counted from the first frame. When the 60 Hz updates move to the other 120 Hz phase, frames sit near a slot edge and the 1 ms rAF rounding pushes them across it, so an interval of 17 to 25 ms can count as a skipped slot next to one that advanced no slot (mechanism INFERRED; counts MEASURED). Skips with an interval of 25 ms or less: original 94 of 952 and 256 of 951, rewrite 187 of 480, look 139 of 358. The verdicts above are the same under a per-interval rule, round(interval / 16.67 ms) > 1.',
    '',
  ].join('\n');
}
