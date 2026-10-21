// Twin of lean/Fw/Measure/WebKitProfile.lean (TS stand-in until the reductions run as fwcore); test/profile.test.mjs checks every
// function against golden/measure/webkit-profile.jsonl. Integer units: times in hundredths of a ms, positions in tenth px.
// Only flattenTimeline, markTimes and toHundredths are glue (they read the Timeline protocol and convert units); they decide nothing.
import { readFileSync } from 'node:fs';
import { dedupArms } from '../device-session.mjs';
import { hitchVerdict } from '../../../gate-breakpoints/src/smooth/reduce.mjs';

const GOLDEN = readFileSync(new URL('../../../contracts/golden/measure/webkit-profile.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
const KINDS_ROW = GOLDEN.find((l) => l.kind === 'kinds');
/** The Timeline record types that are counted, in output order (Lean `kinds`, read from the golden). */
export const KINDS = Object.freeze(KINDS_ROW.kinds);
/** The kinds whose time is a frame's render work (Lean `isWork`; `Composite` is a count, not work). */
export const WORK = Object.freeze(KINDS_ROW.work);
/** The kinds whose cell carries a time (Lean `isTimed`). */
export const TIMED = Object.freeze(KINDS_ROW.timed);
/** Largest disagreement between the start and end clock offsets of a window (Lean `driftTol`). */
export const DRIFT_TOL = KINDS_ROW.driftTol;
export const ZONES = Object.freeze(['hero', 'finish', 'rest']);

export const isWork = (k) => WORK.includes(k);
export const isTimed = (k) => TIMED.includes(k);
/** Lean `nestedOf`: a record is nested when an ancestor's type is a work kind. */
export const nestedOf = (ancestors) => ancestors.some(isWork);
/** Lean `driftOk`. */
export const driftOk = (a, b) => Math.abs(a - b) <= DRIFT_TOL;
/** Lean `meanOffset` (integer division rounds down). */
export const meanOffset = (a, b) => Math.floor((a + b) / 2);
/** Lean `offsetOf`: the Timeline clock minus the page clock for one mark seen on both. */
export const offsetOf = (tl, page) => tl - page;

const zoneOf = (vh10, maxY10, y) => (y < 2 * vh10 ? 'hero' : maxY10 - y < vh10 ? 'finish' : 'rest');

/** Lean `yAt` (Session): the position of the last frame at or before `t`, else the first frame's, else 0. */
export function posAt(frames, t) {
  let last = null;
  for (const f of frames) if (f[0] <= t) last = f;
  return last ? last[1] : frames.length ? frames[0][1] : 0;
}

/** Lean `inWins`: the time lies in one of the half-open windows. */
export const inWins = (ws, t) => ws.some((w) => w[0] <= t && t < w[1]);

/** Lean `zoneOfRec`: the zone of the scroll position of the frame a record started in. */
export const zoneOfRec = (vh10, maxY10, frames, off, r) => zoneOf(vh10, maxY10, posAt(frames, r.t - off));

/** Lean `zoneRecs`. Records are `{ kind, t, dur, nested }`. */
export const zoneRecs = (vh10, maxY10, frames, off, ws, z, rs) =>
  rs.filter((r) => inWins(ws, r.t - off) && zoneOfRec(vh10, maxY10, frames, off, r) === z);

/** Lean `zoneFrames`. */
export const zoneFrames = (vh10, maxY10, ws, z, fs) => fs.filter((f) => inWins(ws, f[0]) && zoneOf(vh10, maxY10, f[1]) === z);

/** Lean `winLen`. */
export const winLen = (w) => Math.max(0, w[1] - w[0]);

/** Lean `span`: the sum of the window lengths. */
export const span = (ws) => ws.reduce((s, w) => s + winLen(w), 0);

/** Lean `sweepStep`: the state is [end of what is covered, covered length]. */
export const sweepStep = (st, iv) => {
  const s = Math.max(iv[0], st[0]);
  return s < iv[1] ? [iv[1], st[1] + (iv[1] - s)] : st;
};

/** Lean `unionLen`: the measure of the union of the intervals, swept in start order from `lo`. */
export const unionLen = (lo, ivs) => [...ivs].sort((a, b) => a[0] - b[0]).reduce(sweepStep, [lo, 0])[1];

/** Lean `clipped`: the records of window `w` that start in it, as intervals on the page clock ended at the window's end. */
export const clipped = (off, w, rs) =>
  rs.filter((r) => w[0] <= r.t - off && r.t - off < w[1]).map((r) => [r.t - off, Math.min(r.t - off + r.dur, w[1])]);

/** Lean `coveredIn`. */
export const coveredIn = (off, w, rs) => Math.max(0, unionLen(w[0], clipped(off, w, rs)));

/** Lean `covered`: the time the records cover over the windows (never above `span`, Lean `covered_le_span`). */
export const covered = (off, ws, rs) => ws.reduce((s, w) => s + coveredIn(off, w, rs), 0);

/** Lean `cell`: [count, covered time] of a kind; `Composite` has a count and no time. */
export function cell(k, off, ws, rs) {
  const ks = rs.filter((r) => r.kind === k);
  return [ks.length, isTimed(k) ? covered(off, ws, ks) : 0];
}

/** Lean `renderWork`: the time covered by the top-level work records, clipped to the windows. */
export const renderWork = (off, ws, rs) => covered(off, ws, rs.filter((r) => isWork(r.kind) && !r.nested));

/** Lean `perFrameUs`. */
export const perFrameUs = (work, frames) => (frames === 0 ? 0 : Math.floor((10 * work) / frames));

/** Lean `profile`: `{ frames, cells: [[kind, n, covered time]], work, perFrame, span }` of zone `z`. */
export function profile(vh10, maxY10, frames, off, ws, z, rs) {
  const zr = zoneRecs(vh10, maxY10, frames, off, ws, z, rs);
  const n = zoneFrames(vh10, maxY10, ws, z, frames).length;
  const w = renderWork(off, ws, zr);
  return { frames: n, cells: KINDS.map((k) => [k, ...cell(k, off, ws, zr)]), work: w, perFrame: perFrameUs(w, n), span: span(ws) };
}

/** Lean `medianNat`. */
export function medianNat(l) {
  const s = [...l].sort((a, b) => a - b);
  return s[Math.floor(l.length / 2)] ?? 0;
}

/** Lean `zoneVerdict`: `first` when the first arm does less render work per frame, against the A/A pair; at least 5 reps each. */
export const zoneVerdict = (a, b, aa1, aa2) => hitchVerdict(a, b, aa1, aa2);

/** Lean `armsOf` (Session's dedup of the rewrite arms by resolved flags). */
export const armsOf = (xs) => dedupArms(xs);

// ---- glue: the Timeline protocol and units ----

/** Seconds (Timeline) or milliseconds (page) to hundredths of a ms. */
export const toHundredths = (ms) => Math.round(ms * 100);

/**
 * The Timeline records, flattened with the render ancestry: `{ kind, t, dur, nested }`, t and dur in hundredths of a ms on the
 * Timeline clock. `startTime`/`endTime` are seconds.
 */
export function flattenTimeline(records) {
  const out = [];
  const walk = (r, ancestors) => {
    const t = toHundredths(r.startTime * 1000);
    const dur = r.endTime != null ? Math.max(0, toHundredths((r.endTime - r.startTime) * 1000)) : 0;
    out.push({ kind: r.type, t, dur, nested: nestedOf(ancestors) });
    for (const c of r.children ?? []) walk(c, [...ancestors, r.type]);
  };
  for (const r of records) walk(r, []);
  return out;
}

/** The Timeline time (hundredths of ms) of each `performance.mark(name)` TimeStamp record, by name (first occurrence). */
export function markTimes(records) {
  const m = new Map();
  const walk = (r) => {
    if (r.type === 'TimeStamp' && r.data && typeof r.data.message === 'string' && !m.has(r.data.message)) m.set(r.data.message, toHundredths(r.startTime * 1000));
    for (const c of r.children ?? []) walk(c);
  };
  for (const r of records) walk(r);
  return m;
}

/**
 * The raw input of one window, as kept in the artifact: the page (frames, viewport, window, marks), the Timeline times of the two
 * marks and the counted records `[kind index in KINDS, t, dur, nested 0|1]` (hundredths of ms, Timeline clock). Re-reducing it with
 * `profileFromRaw` gives the window's profile again, so the reduction can change without a new run.
 */
export function rawOf(page, records) {
  const tl = markTimes(records);
  const recs = flattenTimeline(records).filter((r) => KINDS.includes(r.kind)).map((r) => [KINDS.indexOf(r.kind), r.t, r.dur, r.nested ? 1 : 0]);
  return { page, tl: { a: tl.get('wk:a') ?? null, b: tl.get('wk:b') ?? null }, recs };
}

/**
 * One window from its raw input: the clock offset from the start and end marks, whether the drift is within tolerance, and the
 * profile of each zone. `raw.page` is `{ frames: [[tHundredths, yTenthPx]], vh10, maxY10, w0, w1, marks: {a, b} }` on the page clock.
 * A window whose offsets drift apart is refused (`profiles: null`).
 */
export function profileFromRaw(raw) {
  const { page, tl } = raw;
  if (tl.a == null || tl.b == null) return { ok: false, reason: 'marks-missing', profiles: null };
  const offA = offsetOf(tl.a, page.marks.a);
  const offB = offsetOf(tl.b, page.marks.b);
  if (!driftOk(offA, offB)) return { ok: false, reason: 'drift', offA, offB, profiles: null };
  const off = meanOffset(offA, offB);
  const recs = raw.recs.map(([k, t, dur, nested]) => ({ kind: KINDS[k], t, dur, nested: nested === 1 }));
  const ws = [[page.w0, page.w1]];
  const profiles = {};
  for (const z of ZONES) profiles[z] = profile(page.vh10, page.maxY10, page.frames, off, ws, z, recs);
  return { ok: true, off, offA, offB, profiles };
}

/** One window from one page and its raw Timeline records: `profileFromRaw (rawOf ...)`, with the raw input returned beside it. */
export function profileWindow(page, records) {
  const raw = rawOf(page, records);
  return { ...profileFromRaw(raw), raw };
}
