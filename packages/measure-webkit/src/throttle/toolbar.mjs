// Twin of the toolbar reducers of Lean Fw.Measure.MorphEndCount (step cadence of visualViewport.height, gestures, fade onsets, refresh rate,
// the per-flag verdict, the Timeline window). test/throttle-toolbar.test.mjs checks it against the tb-* rows of
// packages/contracts/golden/device/morph-end-count.jsonl. Times are hundredths of a ms, heights and morph values as the recorder writes them.
import { events, opens, rates, lockCounts, hasMorphReads, byDirection } from './morph-end.mjs';
import { cmp } from '../touchlock.mjs';
import { excludeReason } from './finish-report.mjs';

export const ARMS = Object.freeze({
  default: '',
  'touch-first': '?fw=morph.mount:touch-first',
  'open-once': '?fw=morph.mount:open-once',
  unthrottle: '?fw=engine.scroll:unthrottle',
  'overscroll-lock': '?fw=morph.mount:overscroll-lock',
  threaded: '?fw=morph.panel:threaded',
});
export const ARM_ORDER = Object.freeze(Object.keys(ARMS));
export const FLAG_ARMS = Object.freeze(ARM_ORDER.filter((a) => a !== 'default'));
export const LOOK_CHANGE = Object.freeze(new Set(['touch-first', 'open-once', 'overscroll-lock']));
export const FLAG_OF = Object.freeze({
  'touch-first': 'morph.mount:touch-first', 'open-once': 'morph.mount:open-once', unthrottle: 'engine.scroll:unthrottle',
  'overscroll-lock': 'morph.mount:overscroll-lock', threaded: 'morph.panel:threaded',
});

export const BURST_MAX_CS = 50000;
export const LIFTED_BELOW_CS = 5000;
export const WIN_START = 4;
export const WIN_CAP_MS = 10000;

export function stepFrames(vh) {
  const out = [];
  for (let i = 1; i < vh.length; i++) if (vh[i] !== vh[i - 1]) out.push(i);
  return out;
}

export function stepGaps(t, fs) {
  const out = [];
  for (let k = 0; k + 1 < fs.length; k++) {
    const x = t[fs[k]], y = t[fs[k + 1]];
    if (x === undefined || y === undefined) continue;
    if (y - x > 0 && y - x <= BURST_MAX_CS) out.push(y - x);
  }
  return out;
}

export const medianCs = (l) => [...l].sort((a, b) => a - b)[Math.floor(l.length / 2)] ?? 0;

export const stepsLifted = (gaps) => gaps.length > 0 && medianCs(gaps) < LIFTED_BELOW_CS;

export const gestureOf = (g, i) => g[i] ?? 0;
export const gestureCount = (g) => Math.max(0, ...g);
export const perGesture = (g, frames) => Array.from({ length: gestureCount(g) }, (_, k) => frames.filter((i) => gestureOf(g, i) === k + 1).length);

export function onsetFrames(r) {
  const out = [];
  for (let i = 0; i < r.length; i++) if (r[i] > 0 && (i === 0 ? 0 : r[i - 1]) === 0) out.push(i);
  return out;
}

export const refreshHz = (gapCs) => (gapCs === 0 ? 0 : Math.floor((Math.floor(200000 / gapCs) + 1) / 2));
export const foldOf = (hz) => Math.floor(hz / 10);

/** Lean `tbPass` over the recorder arrays (t in hundredths of a ms) and the Timeline counts. */
export function tbPass(t, vh, r, d, g, reversals, layout, recalc, frames) {
  return {
    gestures: gestureCount(g), reversals, swaps: events(r, d).length, onsets: opens(r),
    onsetGestures: perGesture(g, onsetFrames(r)).filter((x) => x > 0).length,
    gaps: stepGaps(t, stepFrames(vh)), peak: Math.max(0, ...r), settled: (r[r.length - 1] ?? 0) === 0, layout, recalc, frames,
  };
}

export const cmpBy = (num, den, base, cand) => cmp(rates(base.map((p) => [num(p), den(p)])), rates(cand.map((p) => [num(p), den(p)])));

export const floorHolds = (base, cand) => base.length > 0 && cand.length > 0 && Math.min(...base) <= Math.min(...cand);

export const sameLook = (base, cand) =>
  floorHolds(base.map((p) => p.peak), cand.map((p) => p.peak))
  && floorHolds(rates(base.map((p) => [p.onsetGestures, p.gestures])), rates(cand.map((p) => [p.onsetGestures, p.gestures])))
  && (!base.every((p) => p.settled) || cand.every((p) => p.settled));

const n = (b) => (b ? 1 : 0);

export const betterN = (rev, reopen, onset, lifted) => n(rev === 'lower') + n(reopen === 'lower') + n(onset === 'lower') + n(lifted);

export const worseN = (rev, reopen, onset, layout, recalc, look) =>
  n(rev === 'higher') + n(reopen === 'higher') + n(onset === 'higher') + n(layout === 'higher') + n(recalc === 'higher') + n(!look);

export function armVerdict(rev, reopen, onset, layout, recalc, lifted, look) {
  if (betterN(rev, reopen, onset, lifted) === 0) return 'no-win';
  return worseN(rev, reopen, onset, layout, recalc, look) === 0 ? 'win' : 'trade';
}

export const liftedBy = (base, cand) => stepsLifted(cand.flatMap((p) => p.gaps)) && !stepsLifted(base.flatMap((p) => p.gaps));

export const columns = (base, cand) => ({
  reversals: cmpBy((p) => p.reversals, (p) => p.gestures, base, cand),
  swaps: cmpBy((p) => p.swaps, (p) => p.gestures, base, cand),
  onsets: cmpBy((p) => p.onsets, (p) => p.gestures, base, cand),
  layout: cmpBy((p) => p.layout, (p) => p.frames, base, cand),
  recalc: cmpBy((p) => p.recalc, (p) => p.frames, base, cand),
  lifted: liftedBy(base, cand),
  look: sameLook(base, cand),
});

export function flagVerdict(base, cand) {
  const c = columns(base, cand);
  return armVerdict(c.reversals, c.swaps, c.onsets, c.layout, c.recalc, c.lifted, c.look);
}

export const enters = (lookChange, v) => !lookChange && v === 'win';

/** The Timeline window: 'wait' | 'record' | 'done' from the gesture counter and the ms spent recording (null before it started). */
export function winPhase(g, inMs) {
  if (inMs === null) return g < WIN_START ? 'wait' : g === WIN_START ? 'record' : 'done';
  return g > WIN_START || inMs >= WIN_CAP_MS ? 'done' : 'record';
}

/** Why a pass cannot count, or null. */
export function reasonOf(p) {
  return excludeReason(p) ?? (hasMorphReads(p.rec) && Array.isArray(p.rec.g) && p.rec.g.length === p.rec.y.length ? null : 'record has no gesture reads');
}

/** The Lean pass record of a recorder record plus the window's Timeline counts ({layout, recalc, frames} or null). */
export function passOf(p) {
  const { rec } = p;
  const w = p.cost && p.cost.frames > 0 ? p.cost : { layout: 0, recalc: 0, frames: 0 };
  return tbPass(rec.t.map((x) => Math.round(x * 100)), rec.vh, rec.r, rec.d, rec.g, lockCounts(rec).reversals, w.layout, w.recalc, w.frames);
}

/** Display facts of one pass that no verdict reads: steps, vh range (tenth px), closes and re-opens. */
export function facts(p) {
  const { rec } = p;
  const dirs = byDirection(events(rec.r, rec.d));
  const sum = (b) => b.up + b.down + b.none;
  return { steps: stepFrames(rec.vh).length, vhMin: Math.min(...rec.vh), vhMax: Math.max(...rec.vh), closes: sum(dirs.close), reopens: sum(dirs.reopen) };
}

/** The refresh rate in Hz from the idle rAF timestamps of a pass (ms), 0 when there are fewer than two. */
export function hzOf(ts) {
  const gaps = ts.slice(1).map((x, i) => Math.round((x - ts[i]) * 100)).filter((x) => x > 0);
  return gaps.length ? refreshHz(medianCs(gaps)) : 0;
}
