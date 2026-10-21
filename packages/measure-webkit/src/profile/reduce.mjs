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
/** The kinds whose time is a frame's render work. */
export const RENDER = Object.freeze(KINDS_ROW.render);
/** Largest disagreement between the start and end clock offsets of a window (Lean `driftTol`). */
export const DRIFT_TOL = KINDS_ROW.driftTol;
export const ZONES = Object.freeze(['hero', 'finish', 'rest']);

export const isRender = (k) => RENDER.includes(k);
/** Lean `nestedOf`: a record is nested when an ancestor's type is a render kind. */
export const nestedOf = (ancestors) => ancestors.some(isRender);
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

/** Lean `cell`: [count, summed duration] of a kind. */
export function cell(k, rs) {
  const ks = rs.filter((r) => r.kind === k);
  return [ks.length, ks.reduce((s, r) => s + r.dur, 0)];
}

/** Lean `renderWork`: summed duration of the render kinds that no render record encloses. */
export const renderWork = (rs) => rs.filter((r) => isRender(r.kind) && !r.nested).reduce((s, r) => s + r.dur, 0);

/** Lean `perFrameUs`. */
export const perFrameUs = (work, frames) => (frames === 0 ? 0 : Math.floor((10 * work) / frames));

/** Lean `profile`: `{ frames, cells: [[kind, n, dur]], work, perFrame }` of zone `z`. */
export function profile(vh10, maxY10, frames, off, ws, z, rs) {
  const zr = zoneRecs(vh10, maxY10, frames, off, ws, z, rs);
  const n = zoneFrames(vh10, maxY10, ws, z, frames).length;
  const w = renderWork(zr);
  return { frames: n, cells: KINDS.map((k) => [k, ...cell(k, zr)]), work: w, perFrame: perFrameUs(w, n) };
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
 * One window from one page: the clock offset from the start and end marks, whether the drift is within tolerance, and the profile of
 * each zone. `page` is `{ frames: [[tHundredths, yTenthPx]], vh10, maxY10, w0, w1, marks: {a, b} }` on the page clock;
 * `records` are the raw Timeline records. A window whose offsets drift apart is refused (`profiles: null`).
 */
export function profileWindow(page, records) {
  const tl = markTimes(records);
  if (!tl.has('wk:a') || !tl.has('wk:b')) return { ok: false, reason: 'marks-missing', profiles: null };
  const offA = offsetOf(tl.get('wk:a'), page.marks.a);
  const offB = offsetOf(tl.get('wk:b'), page.marks.b);
  if (!driftOk(offA, offB)) return { ok: false, reason: 'drift', offA, offB, profiles: null };
  const off = meanOffset(offA, offB);
  const recs = flattenTimeline(records);
  const ws = [[page.w0, page.w1]];
  const profiles = {};
  for (const z of ZONES) profiles[z] = profile(page.vh10, page.maxY10, page.frames, off, ws, z, recs);
  return { ok: true, off, offA, offB, profiles };
}
