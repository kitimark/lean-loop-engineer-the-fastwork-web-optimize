// Twin of lean/Fw/Device/Session.lean (TS stand-in until the reductions run as fwcore); test/device-record.test.mjs checks every
// function against golden/device/session.jsonl. Integer units: times in hundredths of a ms, positions in tenth px, part values
// per mille. Nothing is decided here that Lean does not decide; reducePass/compareZones are maps over those decisions.
import { readFileSync } from 'node:fs';
import { replayOk as loaderOk } from '../../measure-chromium/src/profile.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/session.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
/** The constants Lean owns, read from the generated golden. */
export const CONST = Object.freeze(GOLDEN.find((l) => l.kind === 'consts'));
/** The session plan: one entry per step, in order, with the banner text Lean wrote. */
export const PLAN = Object.freeze(GOLDEN.filter((l) => l.kind === 'plan').map(({ step, arm, seconds, text }) => Object.freeze({ step, arm, seconds, text })));
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

/** Frame pairs in which the page moved but the part's value stayed mid-transition. */
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
    parts: Object.fromEntries(Object.entries(r.p).map(([n, vs]) => { const sr = r.y.map((y, i) => [y, vs[i]]); return [n, { maxStep: maxStep(sr), stalls: stalls(sr) }]; })),
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

/** The page units of a record (ms, px) <-> the integer form (hundredths of a ms, tenth px). */
export function normalize(rec) {
  const c = (v, k) => Math.round(v * k);
  return {
    schema: 'fw.phone.record.int/1', arm: rec.arm, pass: rec.pass, w: rec.viewport.w, h: rec.viewport.h, maxY10: c(rec.maxY, 10),
    t: rec.frames.t.map((v) => c(v, 100)), y: rec.frames.y.map((v) => c(v, 10)), p: rec.frames.p,
    touches: rec.touches.map(([t, ph, x, y, n]) => [c(t, 100), ph, c(x, 10), c(y, 10), n]),
  };
}

export function denormalize(r) {
  return {
    schema: 'fw.phone.record/1', arm: r.arm, pass: r.pass, viewport: { w: r.w, h: r.h, dpr: 3 }, maxY: r.maxY10 / 10,
    frames: { t: r.t.map((v) => v / 100), y: r.y.map((v) => v / 10), p: r.p },
    touches: r.touches.map(([t, ph, x, y, n]) => [t / 100, ph, x / 10, y / 10, n]),
  };
}
