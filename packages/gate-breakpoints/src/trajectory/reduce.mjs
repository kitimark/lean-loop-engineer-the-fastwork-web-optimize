// The pure side of the trajectory probe: TypeScript twin of lean/Fw/Gate/Trajectory.lean, checked against
// packages/contracts/golden/gate/trajectory.jsonl (test/trajectory.test.mjs). Every function below mirrors a Lean definition of the
// same name; `reduceRun` (the loop over nodes, properties and steps) is the only part Lean does not hold (a listed TS stand-in).
//
// A reading (Val) is null (absent), an array of integers (a number x 1000) or a string. A sample is { m, since, els, rep, cls, ph, t0 }:
// `since` is the ms since the last nav class change (null: none happened), `cls` the nav classes that are on, `ph` the index of
// the phase it was read in, `t0` the ms its reads started at, rounded (null: not recorded); `annotate` adds `ord`.
import { colourFromV1 } from './kit.mjs';

export const TOL = { discrete: 0, geometry: 1000, unit: 10, colour: 2000 };
export const ALLOWED_WIDTHS = [390, 640, 641, 1280];

const pass = 'pass';
const fail = (w) => `fail:${w}`;
const skip = (s) => `skip:${s}`;

const inBand = (t, win, xs) => xs.every((x, j) => {
  const c = win.map((w) => w[j] ?? 0);
  return Math.min(...c) - t <= x && x <= Math.max(...c) + t;
});
const sameNums = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

/** One element: the rewrite's reading against the window of the original's readings. */
export function judgeVal(kind, win, r) {
  if (win.length === 0) return skip('noSample');
  if (r === null) return win.every((w) => w === null) ? pass : fail('missing');
  if (win.some((w) => w === null)) return fail('missing');
  if (typeof r === 'string') {
    if (!win.every((w) => typeof w === 'string')) return fail('type');
    return win.includes(r) ? pass : fail('differs');
  }
  if (!win.every((w) => Array.isArray(w))) return fail('type');
  if (win.some((w) => w.length !== r.length)) return fail('shape');
  if (kind === 'discrete') return win.some((w) => sameNums(w, r)) ? pass : fail('differs');
  return inBand(TOL[kind], win, r) ? pass : fail('apart');
}

/** Several verdicts as one: the first failure, else a pass if any passed, else a skip. */
export function combine(vs) {
  const f = vs.find((v) => v.startsWith('fail:'));
  if (f) return f;
  return vs.includes(pass) ? pass : skip('noSample');
}

/** All elements of a node: counts must match, then each element on its own. */
export function judgeEls(kind, win, r) {
  if (win.length === 0) return skip('noSample');
  if (win.some((w) => w.length !== r.length)) return fail('count');
  return combine(r.map((rv, i) => judgeVal(kind, win.map((w) => w[i] ?? null), rv ?? null)));
}

const between = (a, b, m) => Math.min(a, b) <= m && m <= Math.max(a, b);

export function nearest(ms, m) {
  let best = 0;
  for (let k = 0; k < ms.length; k++) if (Math.abs(ms[k] - m) < Math.abs(ms[best] - m)) best = k;
  return best;
}

const pairHit = (ms, m, j) => (j + 1 < ms.length && between(ms[j], ms[j + 1], m)) || (j > 0 && between(ms[j - 1], ms[j], m));

/** The original's samples aligned to the morph value `m`: the ends of the enclosing pairs (else the nearest sample) and one sample on each side. */
export function window(ms, m) {
  if (ms.length === 0) return [];
  const idx = ms.map((_, j) => j);
  const hasPair = idx.some((j) => pairHit(ms, m, j));
  const near = nearest(ms, m);
  const core = idx.filter((j) => (hasPair ? pairHit(ms, m, j) : j === near));
  return idx.filter((i) => core.some((j) => i <= j + 1 && j <= i + 1));
}

/** Lean `reach`: one bucket (a tenth of the morph, x 10000). */
export const REACH = 1000;
/** Lean `beyond`: `m` is farther than REACH below every sample of `ms`, or above every one. */
export const beyond = (ms, m) => ms.every((x) => x + REACH < m) || ms.every((x) => m + REACH < x);

/** Lean `windowOne`: the samples of ONE pass a rewrite sample at `m` is compared with, or null (no counterpart: a coverage failure). */
export const windowOne = (orig, m) => {
  if (m === null || m === undefined) return null;
  if (orig.some((s) => s.m === null || s.m === undefined)) return null;
  const ms = orig.map((s) => s.m);
  if (beyond(ms, m)) return null;
  return window(ms, m).map((i) => orig[i]).filter((s) => s !== undefined);
};

/** Lean `repsOf`: the passes of a pooled list, each once, in order of first appearance. */
export const repsOf = (orig) => [...new Set(orig.map((s) => s.rep ?? 0))];

/**
 * Lean `windowOf`: the window of a pooled list is the union of the windows of its passes (each aligned on its own through
 * `windowOne`, so a neighbouring pair never crosses a pass boundary), or null when no pass has one.
 */
export const windowOf = (orig, m) => {
  const ws = repsOf(orig).map((r) => windowOne(orig.filter((s) => (s.rep ?? 0) === r), m)).filter((w) => w !== null);
  return ws.length === 0 ? null : ws.flat();
};

/** Lean `rules`: the rules of apps/site/src/parts/nav/nav.module.css that declare a transition, by selector line. */
export const RULES = [
  { line: 6, node: 'nav', on: [], off: [], minW: null, reduce: false, spec: 1, set: [['opacity', 280, 0], ['transform', 320, 0], ['visibility', 0, 320]], delay: null },
  { line: 41, node: 'nav', on: [], off: ['is-morphing'], minW: null, reduce: false, spec: 2, set: [['background', 700, 0], ['opacity', 280, 0], ['transform', 320, 0], ['visibility', 0, 320], ['width', 680, 0]], delay: null },
  { line: 63, node: 'nav', on: ['is-scroll-hidden'], off: [], minW: null, reduce: false, spec: 2, set: [['opacity', 280, 0], ['transform', 320, 0], ['visibility', 0, 320]], delay: null },
  { line: 73, node: 'nav', on: [], off: ['is-scroll-hidden'], minW: null, reduce: false, spec: 2, set: null, delay: 0 },
  { line: 78, node: 'nav', on: ['is-hero-pill'], off: ['is-hero-chrome-ready'], minW: 600, reduce: false, spec: 3, set: [], delay: null },
  { line: 83, node: 'nav', on: ['is-hero-pill', 'is-hero-chrome-ready'], off: [], minW: 600, reduce: false, spec: 3, set: [['background', 700, 0], ['opacity', 700, 0], ['transform', 320, 0], ['width', 680, 0]], delay: null },
  { line: 106, node: 'logo', on: [], off: [], minW: null, reduce: false, spec: 1, set: [['color', 240, 0]], delay: null },
  { line: 128, node: 'actions', on: [], off: [], minW: null, reduce: false, spec: 1, set: [['gap', 680, 0]], delay: null },
  { line: 141, node: 'actions', on: ['is-morphing'], off: [], minW: null, reduce: false, spec: 3, set: [], delay: null },
  { line: 167, node: 'earn', on: [], off: [], minW: null, reduce: false, spec: 2, set: [['max-width', 680, 0], ['opacity', 320, 120], ['padding-inline', 680, 0]], delay: null },
  { line: 189, node: 'earn', on: ['is-hero-pill'], off: [], minW: null, reduce: false, spec: 4, set: [['max-width', 680, 0], ['opacity', 200, 0], ['padding-inline', 680, 0]], delay: null },
  { line: 201, node: 'earn', on: ['is-earn-still'], off: [], minW: null, reduce: false, spec: 4, set: [], delay: null },
  { line: 290, node: 'nav', on: [], off: ['is-morphing'], minW: null, reduce: true, spec: 2, set: [['background', 320, 0], ['opacity', 280, 0], ['transform', 320, 0], ['visibility', 0, 320]], delay: null },
  { line: 297, node: 'nav', on: ['is-morphing'], off: [], minW: null, reduce: true, spec: 2, set: [], delay: null },
  { line: 298, node: 'earn', on: [], off: [], minW: null, reduce: true, spec: 2, set: [], delay: null },
];

/** Lean `cssOf`: the CSS properties whose transitions move a probe property. */
export const cssOf = (node, prop) => ({
  'nav|visibility': ['visibility'], 'nav|rect': ['width', 'transform'], 'nav|background-color': ['background', 'background-color'],
  'nav|opacity': ['opacity'], 'nav|transform.lin': ['transform'], 'nav|transform.shift': ['transform'], 'logo|color': ['color'],
  'actions|gap': ['gap', 'column-gap'], 'earn|opacity': ['opacity'], 'earn|max-width': ['max-width'],
})[`${node}|${prop}`] ?? [];

/** Lean `driver`: the class under which JS drives the morph frame by frame. Under it the judge treats every sample as
 * at rest; rules 6 and 167 still run transitions driven by `--morph` (nav transform/opacity, earn max-width/opacity/padding),
 * which are judged strictly against the m-window. */
export const DRIVER = 'is-morphing';

/** Lean `applies`. */
export const applies = (r, node, width, cls) => r.node === node && r.on.every((c) => cls.includes(c)) && !r.off.some((c) => cls.includes(c))
  && (r.minW === null || width > r.minW) && !r.reduce;

/** Lean `before`: cascade order (specificity, then source line). */
const before = (a, b) => a.spec < b.spec || (a.spec === b.spec && a.line < b.line);

/** Lean `lastBy`: the rule latest in cascade order, the first of equals. */
const lastBy = (rs) => rs.reduce((acc, r) => (acc === null || before(acc, r) ? r : acc), null);

/** Lean `transitionsOf`. */
export function transitionsOf(node, width, cls) {
  const rs = RULES.filter((r) => applies(r, node, width, cls));
  const setR = lastBy(rs.filter((r) => r.set !== null));
  const set = setR === null ? [] : setR.set;
  const dl = lastBy(rs.filter((r) => r.delay !== null && (setR === null || before(setR, r))));
  return dl === null ? set : set.map(([p, d]) => [p, d, dl.delay]);
}

/** Lean `durOf`. */
export function durOf(node, prop, width, cls) {
  if (cls.includes(DRIVER)) return null;
  const css = cssOf(node, prop);
  const t = transitionsOf(node, width, cls).filter(([p]) => css.includes(p)).reduce((a, [, d, l]) => Math.max(a, d + l), 0);
  return t === 0 ? null : t;
}

/** Lean `startLag`. */
export const START_LAG = 200;

/** Lean `inFlight`: `d` maps a class set to its transition time. */
export const inFlight = (d, s) => { const t = d(s.cls); return t !== null && s.since !== null && s.since < t + START_LAG; };

const sameCls = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

/** Lean `restarts`. */
const restarts = (p, s) => p === null || !sameCls(p.cls, s.cls) || (s.since !== null && (p.since === null || s.since < p.since));

/** Lean `annotate`: each sample with `ord`, the number of earlier epochs of its pass with its class set. */
export function annotate(seg) {
  const st = new Map();
  return seg.map((s) => {
    const x = st.get(s.rep) ?? { prev: null, ord: 0, seen: [] };
    if (restarts(x.prev, s)) { x.ord = x.seen.filter((c) => sameCls(c, s.cls)).length; x.seen.push(s.cls); }
    x.prev = s; st.set(s.rep, x);
    return { ...s, ord: x.ord };
  });
}

/** Lean `inEpoch`. */
const inEpoch = (r, o) => o.rep === r.rep && sameCls(o.cls, r.cls) && o.ord === r.ord;

/** Lean `isCore`. */
const isCore = (r, o) => inEpoch(r, o) && o.ph === r.ph && o.since !== null && r.since !== null && Math.abs(o.since - r.since) <= START_LAG;

/** Lean `flightWindow`. */
export function flightWindow(seg, r) {
  const p = seg.filter((o) => o.rep === r.rep);
  const core = p.map((_, i) => i).filter((i) => isCore(r, p[i]));
  if (core.length === 0) return [];
  const lo = core[0], hi = core[core.length - 1];
  return p.filter((o, i) => i + 1 === lo || (lo <= i && i <= hi + 1 && inEpoch(r, o)));
}

/** Lean `endOf`. */
const endOf = (seg, w) => { const e = seg.filter((o) => inEpoch(w, o)); return e.length === 0 ? null : e[e.length - 1]; };

/** Lean `settledRef`. */
export const settledRef = (d, seg, w) => { if (!inFlight(d, w)) return w; const e = endOf(seg, w); return e !== null && !inFlight(d, e) ? e : null; };

const chan = (els) => els.map((v) => (Array.isArray(v) ? v.slice(0, 3) : v));
const alpha = (els) => els.map((v) => (Array.isArray(v) ? v.slice(3) : v));

/** Lean `matchOne`. */
export function matchOne(kind, win, r) {
  const vs = win.map((w) => judgeEls(kind, [w], r));
  return vs.some((v) => !v.startsWith('fail:')) ? pass : combine(vs);
}

/** Lean `judgeColour`. */
export const judgeColour = (core, win, r) =>
  combine([matchOne('colour', core.map((x) => chan(x.els)), chan(r.els)), judgeEls('colour', win.map((x) => alpha(x.els)), alpha(r.els))]);

/** Lean `isCoreIn`. */
export const isCoreIn = (r, o) => isCore({ ...r, rep: o.rep }, o);

export const envelope = (seg, r) => repsOf(seg).flatMap((q) => flightWindow(seg, { ...r, rep: q }));

function judgeWithBy(kind, d, settle, fw, core, win, r) {
  if (inFlight(d, r)) {
    if (fw.length === 0) return win === null ? fail('coverage') : judgeEls(kind, win.map((s) => s.els), r.els);
    return kind === 'colour' ? judgeColour(fw.filter(core), fw, r) : judgeEls(kind, fw.map((s) => s.els), r.els);
  }
  if (win === null) return fail('coverage');
  const ref = win.map(settle).filter((w) => w !== null);
  return ref.length === 0 ? fail('coverage') : judgeEls(kind, ref.map((x) => x.els), r.els);
}

export const judgeWith = (kind, d, seg, fw, core, win, r) => judgeWithBy(kind, d, (w) => settledRef(d, seg, w), fw, core, win, r);

export const judgeUnit = (kind, d, seg, win, r) => judgeWith(kind, d, seg, envelope(seg, r), (o) => isCoreIn(r, o), win, r);

/** Lean `judgeOwn`. */
export const judgeOwn = (kind, d, seg, win, r) => judgeWith(kind, d, seg, flightWindow(seg, r), (o) => isCore(r, o), win, r);

/** Lean `bucket`: the tenth of a morph value (floor((m + 500) / 1000), clamped to 0..10); 11 for no morph value. */
export const bucket = (m) => (m === null || m === undefined ? 11 : Math.min(10, Math.max(0, Math.floor((m + 500) / 1000))));

/** Lean `needsSample`: the interior buckets of a push. */
export const needsSample = (b) => b >= 1 && b <= 9;

/** Lean `headOf`. */
export const headOf = (seg, q, p) => seg.find((o) => (o.rep ?? 0) === q && o.ph === p + 1) ?? null;

/** Lean `windowPass`. */
export function windowPass(d, seg, orig, r, q) {
  const p = orig.filter((s) => (s.rep ?? 0) === q);
  const h = headOf(seg, q, r.ph);
  const hasM = r.m !== null && r.m !== undefined;
  return h !== null && hasM && !inFlight(d, r) && h.m === r.m && !p.some((s) => s.m === r.m) ? [h] : windowOne(p, r.m);
}

/** Lean `windowAt`. `ph` is 'push' or 'hold'. */
export function windowAt(ph, d, seg, orig, r) {
  if (ph !== 'push') return windowOf(orig, r.m);
  const ws = repsOf(orig).map((q) => windowPass(d, seg, orig, r, q)).filter((w) => w !== null);
  return ws.length === 0 ? null : ws.flat();
}

/** Lean `bucketVerdict`. `ph` is 'push' or 'hold'; `seg` the original's annotated samples of the whole path, `orig` and `rew` the phase's. */
export function bucketVerdict(ph, kind, d, seg, orig, rew, b) {
  const rs = rew.filter((r) => bucket(r.m) === b);
  if (rs.length === 0) return ph === 'push' && needsSample(b) ? fail('coverage') : skip('noSample');
  return combine(rs.map((r) => judgeUnit(kind, d, seg, windowAt(ph, d, seg, orig, r), r)));
}

/** Lean `byM`: twelve verdicts, one per bucket, of phase `p` of the two arms' whole paths. */
export function byM(ph, p, kind, d, oSeg, wSeg) {
  const seg = annotate(oSeg), rew = annotate(wSeg).filter((r) => r.ph === p), orig = seg.filter((o) => o.ph === p);
  return Array.from({ length: 12 }, (_, b) => [b, bucketVerdict(ph, kind, d, seg, orig, rew, b)]);
}

/** Lean `byStep`: one verdict per step of the original; each arm's steps in order are one pass. */
export function byStep(kind, d, orig, rew) {
  const seg = annotate(orig.map(([, o]) => o)), rs = annotate(rew.map(([, r]) => r));
  return orig.map(([step], i) => {
    const j = rew.findIndex(([s]) => s === step);
    return [step, j >= 0 ? judgeUnit(kind, d, seg, [seg[i]], rs[j]) : skip('noSample')];
  });
}

/** The widths of a run from the comma list of the `widths` input; null when refused. */
export function pickWidths(s) {
  if (s === '') return [...ALLOWED_WIDTHS];
  const parts = s.split(',');
  if (!parts.every((p) => /^[0-9]+$/.test(p))) return null;
  const ns = parts.map(Number);
  return ns.every((n) => ALLOWED_WIDTHS.includes(n)) && new Set(ns).size === ns.length ? ns : null;
}

export const isFail = (v) => v.startsWith('fail:');
export const laneFails = (vs) => vs.some(isFail);

// ---- against the faithful arm (Lean `rel`, `laneRed`) -----------------------------------------------------------------------

/**
 * Lean `rel`: what one unit says relative to the same unit of the faithful arm (the default config against the original). A unit
 * the baseline lacks is not a failure there.
 *
 * `new` fails here and passes (or is not compared) there; `both` fails in both, so the candidate did not cause it; `cleared` fails
 * only there; `ok` fails in neither. `unmeasured`: the candidate fails on content (a difference) where the faithful arm fails on
 * coverage, so the faithful arm was not measured there and the unit has no verdict either way. `undecided`: the candidate's open@1
 * is `skip:firstOpen` where the faithful arm does not fail, or the faithful arm's is `skip:firstOpen` where the candidate fails;
 * `stableRel` also gives it to a unit that is new against one member of its `family` and not new against another.
 */
export function rel(cand, base) {
  const c = isFail(cand), b = base !== undefined && isFail(base);
  if (c) return b ? (base === fail('coverage') && cand !== fail('coverage') ? 'unmeasured' : 'both') : base === skip('firstOpen') ? 'undecided' : 'new';
  if (b) return 'cleared';
  return cand === skip('firstOpen') ? 'undecided' : 'ok';
}
export const laneRed = (rels) => rels.includes('new');
export const dropPass = (seg, q) => seg.filter((s) => (s.rep ?? 0) !== q);

export const family = (seg) => { const qs = repsOf(seg); return qs.length < 2 ? [seg] : [seg, ...qs.map((q) => dropPass(seg, q))]; };

const cleanRel = (r) => r !== 'new' && r !== 'undecided';

export const stableRel = (rs) => (rs.every((r) => r === 'new') ? 'new' : rs.every(cleanRel) ? rs[0] : 'undecided');

/** Lean `stableOf` of one unit: `cf`, `bf` are its candidate and faithful verdicts against each member of the original's `family`. */
export const unitRel = (cf, bf) => stableRel(cf.map((c, i) => rel(c, bf?.[i])));

export const laneExit = (refused, strict, lane) => (refused ? 2 : !strict ? 0 : lane === 'red' ? 1 : lane === 'undecided' ? 3 : 0);
/** Lean `exitJoin`: the exit over several engines, refused (2) over RED (1) over UNDECIDED (3) over CLEAN (0). */
export const exitJoin = (a, b) => [2, 1, 3].find((c) => a === c || b === c) ?? 0;
export const laneOf = (rels) => (laneRed(rels) ? 'red' : rels.includes('undecided') ? 'undecided' : 'clean');


/** Lean `armCheck`: 'ok' or 'refused:config'. An arm is { site, want, config, mode }, each of the last three a string or null. */
export function armCheck(a) {
  if (a.site === 'orig') return (a.config ?? null) === null && (a.mode ?? null) === null ? 'ok' : 'refused:config';
  const { want, config, mode } = { want: a.want ?? null, config: a.config ?? null, mode: a.mode ?? null };
  return want !== null && config !== null && mode !== null && want !== '' && config === want && mode === 'hydrate' ? 'ok' : 'refused:config';
}
/** Lean `runCheck`: a run is measured as asked iff it has arms and each is. */
export const runCheck = (arms) => (arms.length > 0 && arms.every((a) => armCheck(a) === 'ok') ? 'ok' : 'refused:config');

// ---- timing (Lean `quantile`, `readsDominate`) --------------------------------------------------------------------------------

/** Lean `quantile`: the nearest-rank quantile, p from 1 to 100; null for no samples. */
export function quantile(xs, p) {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(Math.ceil((p * s.length) / 100) - 1, s.length - 1)];
}
/** Lean `readsDominate`. */
export const readsDominate = (readP50, gapP50) => gapP50 > 0 && gapP50 <= 2 * readP50;

// ---- reading the raw output of run.mjs (TS stand-in: the loops; the decisions are the functions above) ------------------

// The close rule of the earn button (Lean section `CloseStart`). Every value is an integer (property value x 1000), so
// every comparison is the exact one Lean makes.

/** Lean `startOn`. */
export const startOn = (node, prop) => node === 'earn' && (prop === 'opacity' || prop === 'max-width');

/** Lean `startTr`: [duration, delay] or null. */
export function startTr(node, prop, width, cls) {
  const css = cssOf(node, prop);
  const t = transitionsOf(node, width, cls).find(([p]) => css.includes(p));
  return t === undefined ? null : [t[1], t[2] ?? 0];
}

/** Lean `fullOf`: opacity 1; max-width 9.5rem up to 640 px, else 11rem; times 1000. */
export const fullOf = (prop, width) => (prop === 'opacity' ? 1000 : width <= 640 ? 152000 : 176000);

/** Lean `startFor`: { tr, full } or null. */
export const startFor = (node, prop, width) =>
  (startOn(node, prop) ? { tr: (cls) => startTr(node, prop, width, cls), full: fullOf(prop, width) } : null);

/** Lean `closePh`. */
export const CLOSE_PH = 2;

/** Lean `startJitter`. */
export const START_JITTER = 80;

/** Lean `Nav.darkCut` x 10000: the morph value at which the earn button is fully collapsed. */
export const DARK_CUT = 2000;

const clampCut = (m) => Math.min(DARK_CUT, Math.max(0, m));

/** Lean `oneNum`. */
const oneNum = (els) => (els.length === 1 && Array.isArray(els[0]) && els[0].length === 1 ? els[0][0] : null);

const has = (x) => x !== null && x !== undefined;

/** Lean `retargets`. */
const retargets = (a, b) => has(a.m) && has(b.m) && clampCut(a.m) !== clampCut(b.m);

/** Lean `triggersOf`. */
export function triggersOf(ps) {
  const out = [];
  for (let j = 1; j < ps.length; j++) if (retargets(ps[j - 1], ps[j])) out.push(ps[j]);
  return out;
}

const passOf = (seg, q) => seg.filter((s) => (s.rep ?? 0) === q);

/** Lean `origFirst`. */
export const origFirst = (seg, r) => triggersOf(passOf(seg, r.rep ?? 0).filter((s) => s.ph === r.ph))[0] ?? null;

export const excess = (lo, hi, w) => (w < lo ? lo - w : hi < w ? w - hi : 0);

export const startCheck = (kind, full, seg, prior, r) => startCheckAt(kind, full, origFirst(seg, r), prior, r);

/** Lean `excess`. */
function startCheckAt(kind, full, o, prior, r) {
  const q = triggersOf([...prior, r])[0] ?? null;
  if (q === null || o === null) return null;
  const s = oneNum(o.els), w = oneNum(q.els), x = oneNum(r.els);
  if (s === null || w === null || x === null) return null;
  return excess(s, s, w) <= TOL[kind] && excess(s, full, x) <= TOL[kind];
}

/** Lean `judgeStart`. */
export function judgeStart(kind, d, full, seg, win, prior, r) {
  const c = startCheck(kind, full, seg, prior, r);
  return c === true ? pass : c === false ? fail('apart') : judgeUnit(kind, d, seg, win, r);
}

/** Lean `startBucket`. */
export function startBucket(kind, d, full, seg, orig, rew) {
  const rs = rew.map((r, i) => [passOf(rew.slice(0, i), r.rep ?? 0), r]).filter(([, r]) => bucket(r.m) === 0);
  if (rs.length === 0) return skip('noSample');
  return combine(rs.map(([ps, r]) => judgeStart(kind, d, full, seg, windowAt('push', d, seg, orig, r), ps, r)));
}

/** Lean `closeOf`. */
const closeOf = (seg, r) => passOf(seg, r.rep ?? 0).filter((s) => s.ph === CLOSE_PH || s.ph === CLOSE_PH + 1);

/** Lean `settleAt`. */
export const settleAt = (dur, delay) => dur + delay + START_JITTER;

/** Lean `settleCheck`: true, false, or null (undecided). */
export function settleCheck(kind, e, seg, r) {
  const q = triggersOf(closeOf(seg, r)).at(-1) ?? null;
  if (q === null) return null;
  const t = e.tr(q.cls), x = oneNum(r.els);
  if (t === null || !has(q.t0) || !has(r.t0) || x === null) return null;
  return settleAt(t[0], t[1]) <= r.t0 - q.t0 ? excess(e.full, e.full, x) <= TOL[kind] : null;
}

/** Lean `settleAnd`. */
export const settleAnd = (v, cs) => (v === pass && cs.includes(false) ? fail('apart') : v);

/** Lean `byMStart`: `byM`, with bucket 0 of the close by `startBucket` and the close-hold by `settleAnd` when `e` is
 * given. */
export function byMStart(ph, p, kind, d, e, oSeg, wSeg) {
  const v = byM(ph, p, kind, d, oSeg, wSeg);
  if (e === null) return v;
  if (ph === 'push' && p === CLOSE_PH) {
    const seg = annotate(oSeg), orig = seg.filter((o) => o.ph === p), rew = annotate(wSeg).filter((r) => r.ph === p);
    return v.map(([b, x]) => (b === 0 ? [b, startBucket(kind, d, e.full, seg, orig, rew)] : [b, x]));
  }
  if (ph === 'hold' && p === CLOSE_PH + 1) {
    const ws = annotate(wSeg), here = ws.filter((r) => r.ph === p);
    return v.map(([b, x]) => [b, settleAnd(x, here.filter((r) => bucket(r.m) === b).map((r) => settleCheck(kind, e, ws, r)))]);
  }
  return v;
}

/** Lean `idOn`. */
export const idOn = (node, prop) => node === 'nav' && prop === 'background-color';

/** Lean `cutM`. */
export const CUT_M = 10;

/** Lean `mixFrom` and `mixTo`: [red, alpha], 0 to 255. */
export const MIX_FROM = [255, 26];
export const MIX_TO = [19, 255];

const idDen = (m) => MIX_FROM[1] * (10000 - m) + MIX_TO[1] * m;
const idNum = (m) => 1000 * (MIX_FROM[0] * MIX_FROM[1] * (10000 - m) + MIX_TO[0] * MIX_TO[1] * m);

/** Lean `redOk`. */
export const redOk = (m, x) => idNum(m) - 500 * idDen(m) <= x * idDen(m) && x * idDen(m) <= idNum(m) + 500 * idDen(m);

/** Lean `alphaOk`. */
export const alphaOk = (m, a) => idDen(m) - 5000 <= 10 * a && 10 * a <= idDen(m) + 5000;

const hasDriver = (s) => s.cls.includes(DRIVER);

const redAlpha = (els) => (els.length === 1 && Array.isArray(els[0]) && els[0].length === 4 ? [els[0][0], els[0][3]] : null);

/** Lean `idFresh`. */
export const idFresh = (s) => s.since !== null && s.since <= START_LAG;

/** Lean `idCheck`: true, false, or null (undecided). `conv` maps a stored reading to sRGB (identity in Lean). */
export function idCheck(d, q, r, conv = (v) => v) {
  if (q === null || !hasDriver(q) || hasDriver(r) || !inFlight(d, r) || !idFresh(r)) return null;
  const xa = redAlpha(r.els.map(conv));
  if (!has(q.m) || !has(r.m) || xa === null) return null;
  return CUT_M <= q.m && r.m <= CUT_M && redOk(q.m, xa[0]) && alphaOk(q.m, xa[1]);
}

/** Lean `idJudge`. */
export function idJudge(kind, d, seg, win, q, r, conv) {
  const c = idCheck(d, q, r, conv);
  return c === true ? pass : c === false ? fail('apart') : judgeUnit(kind, d, seg, win, r);
}

/** Lean `withPrev`: [prev or null, sample]. */
export function withPrev(ws) {
  const last = new Map();
  return ws.map((r) => {
    const q = last.get(r.rep ?? 0) ?? null;
    last.set(r.rep ?? 0, r);
    return [q, r];
  });
}

/** Lean `byMId`. */
export function byMId(ph, p, kind, d, oSeg, wSeg, conv) {
  const seg = annotate(oSeg), orig = seg.filter((o) => o.ph === p), ws = withPrev(annotate(wSeg)).filter(([, r]) => r.ph === p);
  return Array.from({ length: 12 }, (_, b) => {
    const rs = ws.filter(([, r]) => bucket(r.m) === b);
    if (rs.length === 0) return [b, ph === 'push' && needsSample(b) ? fail('coverage') : skip('noSample')];
    return [b, combine(rs.map(([q, r]) => idJudge(kind, d, seg, windowAt(ph, d, seg, orig, r), q, r, conv)))];
  });
}

/** Lean `byMRule`. */
export const byMRule = (ph, p, kind, d, e, id, oSeg, wSeg, conv) =>
  (id ? byMId(ph, p, kind, d, oSeg, wSeg, conv) : byMStart(ph, p, kind, d, e, oSeg, wSeg));

export const OPEN_PH = 0;

export const firstFrame = (ph, p, b) => ph === 'push' && p === OPEN_PH && b === 1;

export const hasBucket = (seg, p, b) => seg.some((s) => s.ph === p && bucket(s.m) === b);

export const ALPHA = [1n, 20n];

const chanceCmp = (no, j, nw) => {
  if (no === 0) return nw === 0 ? 1 : -1;
  const lhs = ALPHA[1] * BigInt(Math.max(0, no - j)) ** BigInt(nw), rhs = ALPHA[0] * BigInt(no) ** BigInt(nw);
  return lhs > rhs ? 1 : lhs < rhs ? -1 : 0;
};

export const firstCover = (no, k, nw) =>
  (k >= 1 && chanceCmp(no, k - 1, nw) <= 0 ? 'missing' : chanceCmp(no, k + 1, nw) > 0 ? 'late' : 'undecided');

export const coverVerdict = (c) => (c === 'missing' ? fail('coverage') : c === 'late' ? skip('firstLate') : skip('firstOpen'));

export const passes = (seg, p) => new Set(seg.filter((s) => s.ph === p).map((s) => s.rep ?? 0)).size;

export const passesIn = (seg, p, b) => new Set(seg.filter((s) => s.ph === p && bucket(s.m) === b).map((s) => s.rep ?? 0)).size;

export const firstVerdict = (ph, p, b, oSeg, wSeg, v) =>
  firstFrame(ph, p, b) && !hasBucket(wSeg, p, b) && v === fail('coverage')
    ? coverVerdict(firstCover(passes(oSeg, p), passesIn(oSeg, p, b), passes(wSeg, p))) : v;

export const byMFirst = (ph, p, kind, d, e, id, oSeg, wSeg, conv) =>
  byMRule(ph, p, kind, d, e, id, oSeg, wSeg, conv).map(([b, v]) => [b, firstVerdict(ph, p, b, oSeg, wSeg, v)]);

export const byMFamEach = (ph, p, kind, d, e, id, oSeg, wSeg, conv) => family(oSeg).map((o) => byMFirst(ph, p, kind, d, e, id, o, wSeg, conv));

export function byMFam(ph, p, kind, d0, e, id, oSeg, wSeg, conv) {
  const durs = new Map();
  const d = (cls) => { const k = JSON.stringify(cls); if (!durs.has(k)) durs.set(k, d0(cls)); return durs.get(k); };
  const seg = annotate(oSeg), orig = seg.filter((o) => o.ph === p);
  const reps = repsOf(seg), origReps = repsOf(orig);
  const drops = reps.length < 2 ? [null] : [null, ...reps];
  const strictPass = new Map(reps.map((q) => [q, seg.filter((o) => o.rep === q)]));
  const segPass = new Map(reps.map((q) => [q, passOf(seg, q)]));
  const origPass = new Map(origReps.map((q) => [q, passOf(orig, q)]));
  const epoch = (o) => JSON.stringify([o.rep, o.cls, o.ord]);
  const ends = new Map(seg.map((o) => [epoch(o), o]));
  const settled = new Map();
  const settle = (w) => {
    if (!settled.has(w)) {
      const end = ends.get(epoch(w)) ?? null;
      settled.set(w, !inFlight(d, w) ? w : end !== null && !inFlight(d, end) ? end : null);
    }
    return settled.get(w);
  };
  const pieces = new Map();
  const pieceOf = (r) => {
    if (!pieces.has(r)) {
      pieces.set(r, {
        env: reps.map((q) => flightWindow(strictPass.get(q), { ...r, rep: q })),
        win: origReps.map((q) => (ph === 'push' ? windowPass(d, segPass.get(q), origPass.get(q), r, q) : windowOne(origPass.get(q), r.m))),
      });
    }
    return pieces.get(r);
  };
  const empty = (b) => (ph === 'push' && needsSample(b) ? fail('coverage') : skip('noSample'));
  const ws = annotate(wSeg), rew = ws.filter((r) => r.ph === p);
  const inB = (b) => rew.filter((r) => bucket(r.m) === b);
  const starts = e !== null && ph === 'push' && p === CLOSE_PH
    ? rew.map((r, i) => [passOf(rew.slice(0, i), r.rep ?? 0), r]).filter(([, r]) => bucket(r.m) === 0).map(([prior, r]) => [prior, r, origFirst(seg, r)]) : null;
  const settles = e !== null && ph === 'hold' && p === CLOSE_PH + 1
    ? Array.from({ length: 12 }, (_, b) => inB(b).map((r) => settleCheck(kind, e, ws, r))) : null;
  const ids = id ? withPrev(ws).filter(([, r]) => r.ph === p) : null;
  return drops.map((q) => {
    const keep = (x) => x !== q;
    const winOf = (r) => { const w = pieceOf(r).win.filter((x, i) => keep(origReps[i]) && x !== null); return w.length === 0 ? null : w.flat(); };
    const unit = (r) => judgeWithBy(kind, d, settle, pieceOf(r).env.filter((_, i) => keep(reps[i])).flat(), (o) => isCoreIn(r, o), winOf(r), r);
    const oSegQ = q === null ? oSeg : dropPass(oSeg, q);
    const rule = (b) => {
      if (id) {
        const rs = ids.filter(([, r]) => bucket(r.m) === b);
        if (rs.length === 0) return empty(b);
        return combine(rs.map(([prev, r]) => { const c = idCheck(d, prev, r, conv); return c === true ? pass : c === false ? fail('apart') : unit(r); }));
      }
      if (starts !== null && b === 0) {
        if (starts.length === 0) return skip('noSample');
        return combine(starts.map(([prior, r, first]) => {
          const c = startCheckAt(kind, e.full, keep(r.rep ?? 0) ? first : null, prior, r);
          return c === true ? pass : c === false ? fail('apart') : unit(r);
        }));
      }
      const rs = inB(b);
      const v = rs.length === 0 ? empty(b) : combine(rs.map(unit));
      return settles !== null ? settleAnd(v, settles[b]) : v;
    };
    return Array.from({ length: 12 }, (_, b) => [b, firstVerdict(ph, p, b, oSegQ, wSeg, rule(b))]);
  });
}

export const PHASES = [['open', 'push'], ['open-hold', 'hold'], ['close', 'push'], ['close-hold', 'hold']];

/** A property is read in every frame of a push with the lean read set when the registry marks it `lean` (the discrete ones and the logo rectangle). */
export const isLeanProp = (p) => p.lean === true;

/** The nav's classes that are on in a row, in registry order: the class set every node's transitions are keyed by. */
const clsOf = (row, navCls) => navCls.filter(([i]) => row.nodes?.nav?.[0]?.[i] === 'on').map(([, name]) => name);

const sampleOf = (row, ni, pi, withM, ph, navCls) => ({
  m: withM && row.m !== null && row.m !== undefined ? row.m : null,
  since: row.since ?? null,
  els: (row.nodes[ni] ?? []).map((e) => (e[pi] === undefined ? null : e[pi])),
  rep: row.rep ?? 0,
  cls: clsOf(row, navCls),
  ph,
  t0: typeof row.t0 === 'number' ? Math.round(row.t0) : null,
});

/**
 * Units of one width of one engine from the two arms' raw readings: [{ width, path, phase, node, prop, kind, step, verdict }].
 * `registries`: { hero, morph, page } as exported by registry.mjs (node lists and the page properties). A path that either arm
 * did not walk (`--paths hero`) has no units. In a push phase read with a lean set, only the lean properties are units.
 */
export function reduceWidth({ width, orig, rewrite, registries }) {
  const units = [];
  const navCls = (registries.morph.find((n) => n.id === 'nav')?.props ?? []).map((p, i) => [i, p.name, p.r]).filter(([, , r]) => r === 'cls').map(([i, name]) => [i, name]);
  const durFor = (node, prop) => (cls) => durOf(node, prop, width, cls);
  const push = (path, phase, node, prop, kind, rows) => { for (const [step, verdict, fam] of rows) units.push({ width, path, phase, node, prop, kind, step, verdict, fam: fam ?? [verdict] }); };
  const stepRows = (rows) => rows.filter((r) => r.frame === 'rest');
  const byStepOf = (path, phase, nodes, oRows, rRows) => {
    for (const n of nodes) {
      n.props.forEach((p, pi) => {
        const o = oRows.map((r) => [r.step, sampleOf(r, n.id, pi, false, 0, navCls)]);
        const w = rRows.map((r) => [r.step, sampleOf(r, n.id, pi, false, 0, navCls)]);
        push(path, phase, n.id, p.id, p.kind, byStep(p.kind, durFor(n.id, p.id), o, w));
      });
    }
  };
  const pageRows = (rows) => rows.map((r) => ({ ...r, nodes: { page: [r.page] } }));
  const pageNode = [{ id: 'page', props: registries.page }];
  if (orig.hero && rewrite.hero) {
    const oHero = stepRows(orig.hero.rows), wHero = stepRows(rewrite.hero.rows);
    byStepOf('hero', 'path', registries.hero, oHero, wHero);
    byStepOf('hero', 'path', pageNode, pageRows(oHero), pageRows(wHero));
  }
  if (orig.morph && rewrite.morph) {
    byStepOf('morph', 'approach', registries.morph, orig.morph.approach, rewrite.morph.approach);
    const pathOf = (arm, ni, pi) => PHASES.flatMap(([q], k) => (arm.morph.phases[q] ?? []).map((r) => sampleOf(r, ni, pi, true, k, navCls)));
    PHASES.forEach(([phase, ph], k) => {
      const lean = (rewrite.morph.phaseReads?.[phase] ?? 'full') === 'lean';
      for (const n of registries.morph) {
        n.props.forEach((p, pi) => {
          if (lean && !isLeanProp(p)) return;
          const fams = byMFam(ph, k, p.kind, durFor(n.id, p.id), startFor(n.id, p.id, width), idOn(n.id, p.id),
            pathOf(orig, n.id, pi), pathOf(rewrite, n.id, pi), colourFromV1);
          push('morph', phase, n.id, p.id, p.kind, fams[0].map(([b, v], i) => [`${phase}@${b}`, v, fams.map((vs) => vs[i][1])]));
        });
      }
    });
  }
  return units;
}

/** The unit's identity across arms: the same width, path, phase, node, property and step. */
export const unitKey = (u) => `${u.width}|${u.path}|${u.phase}|${u.node}|${u.prop}|${u.step}`;

/** Every arm a raw run opened: { run, path, site, want, config, mode }. */
export function armsOf(raw) {
  const out = [];
  for (const r of raw.runs) {
    for (const path of ['hero', 'morph']) {
      if (!r[path]) continue;
      for (const a of [r[path].arm, ...(r[path].extraArms ?? [])]) out.push({ role: r.role ?? (r.site === 'orig' ? 'orig' : 'cand'), width: r.width, path, site: r.site, want: r.want ?? null, config: a?.config ?? null, mode: a?.mode ?? null });
    }
  }
  return out;
}

const roleOf = (r) => r.role ?? (r.site === 'orig' ? 'orig' : 'cand');

/** Milliseconds as whole tenths (Lean `quantile` takes naturals); the reports divide by ten. */
const tenths = (ms) => Math.max(0, Math.round(ms * 10));
const ms1 = (x) => (x === null ? null : x / 10);

/** Timing of the samples: per role and push/hold phase, the read cost (t1 - t0) and the gap between two samples. */
export function timingOf(raw) {
  const out = [];
  for (const role of ['orig', 'base', 'cand']) {
    const runs = raw.runs.filter((r) => roleOf(r) === role && r.morph);
    for (const [phase] of PHASES) {
      const reads = [], gaps = [];
      for (const r of runs) {
        const rows = (r.morph.phases[phase] ?? []).filter((x) => typeof x.t0 === 'number' && typeof x.t1 === 'number');
        rows.forEach((x, i) => { reads.push(tenths(x.t1 - x.t0)); if (i + 1 < rows.length && rows[i + 1].rep === x.rep) gaps.push(tenths(rows[i + 1].t0 - x.t0)); });
      }
      if (reads.length === 0) continue;
      const row = { role, phase, n: reads.length, readP50: quantile(reads, 50), readP90: quantile(reads, 90), gapP50: quantile(gaps, 50), gapP90: quantile(gaps, 90) };
      row.dominate = row.gapP50 !== null && readsDominate(row.readP50, row.gapP50);
      for (const k of ['readP50', 'readP90', 'gapP50', 'gapP90']) row[k] = ms1(row[k]);
      out.push(row);
    }
    const hero = raw.runs.filter((r) => roleOf(r) === role && r.hero);
    const hreads = hero.flatMap((r) => r.hero.rows.filter((x) => typeof x.t0 === 'number').map((x) => tenths(x.t1 - x.t0)));
    if (hreads.length > 0) out.push({ role, phase: 'hero', n: hreads.length, readP50: ms1(quantile(hreads, 50)), readP90: ms1(quantile(hreads, 90)), gapP50: null, gapP90: null, dominate: false });
  }
  return out;
}

/**
 * Everything the lane says about a raw run. First the arms: a run whose arms were not measured as asked is `refused` and has no
 * units (never a pass). Then the units of the candidate (against the original) and, unit by unit, against the same unit of the
 * faithful arm: `rel` new / both / cleared / ok. `red` = some unit is new.
 */
export function reduceRaw(raw, registries) {
  const arms = armsOf(raw);
  const refusedArms = arms.filter((a) => armCheck(a) !== 'ok');
  const timing = timingOf(raw);
  if (runCheck(arms) !== 'ok') {
    const detail = arms.length === 0 ? 'no arm was opened' : refusedArms.slice(0, 4).map((a) => `${a.role} w=${a.width} ${a.path}: config ${a.config ?? 'none'} mode ${a.mode ?? 'none'} want ${a.want ?? 'none'}`).join('; ');
    return { refused: true, detail, arms, units: [], groups: [], totals: null, rels: null, notes: [], fails: false, red: false, timing };
  }
  const units = [];
  const notes = [];
  const widths = [...new Set(raw.runs.map((r) => r.width))];
  for (const width of widths) {
    const find = (role) => raw.runs.find((r) => r.width === width && roleOf(r) === role);
    const orig = find('orig'), cand = find('cand'), base = find('base');
    if (!orig || !cand) { notes.push(`width ${width}: an arm is missing`); continue; }
    if (!base) notes.push(`width ${width}: no faithful arm, every failure counts as new`);
    for (const run of [orig, cand, ...(base ? [base] : [])]) {
      if (run.hero && !run.hero.ready?.ready) notes.push(`width ${width} ${roleOf(run)}: hero page not ready`);
      if (run.morph && !run.morph.watched) notes.push(`width ${width} ${roleOf(run)}: nav not found`);
      const open = (run.hero?.rows ?? []).filter((r) => r.frame === 'rest' && r.settled === false).length;
      if (open > 0) notes.push(`width ${width} ${roleOf(run)}: ${open} hero steps did not settle`);
    }
    const baseUnits = base ? reduceWidth({ width, orig, rewrite: base, registries }) : [];
    const baseVerdicts = new Map(baseUnits.map((u) => [unitKey(u), u.verdict]));
    const baseFams = new Map(baseUnits.map((u) => [unitKey(u), u.fam]));
    for (const u of reduceWidth({ width, orig, rewrite: cand, registries })) {
      const b = baseVerdicts.get(unitKey(u));
      const bf = baseFams.get(unitKey(u));
      units.push({ ...u, base: b ?? null, relAll: rel(u.verdict, b), rel: unitRel(u.fam, bf) });
    }
  }
  const groups = new Map();
  for (const u of units) {
    const key = `${u.width}\u0000${u.path}\u0000${u.node}\u0000${u.prop}`;
    const g = groups.get(key) ?? { width: u.width, path: u.path, node: u.node, prop: u.prop, kind: u.kind, pass: 0, fail: 0, skip: 0, new: 0, both: 0, cleared: 0, unmeasured: 0, failing: [], newSteps: [] };
    if (u.verdict === pass) g.pass++; else if (isFail(u.verdict)) { g.fail++; g.failing.push(`${u.step}=${u.verdict.slice(5)}`); } else g.skip++;
    if (u.rel === 'both' || u.rel === 'cleared' || u.rel === 'unmeasured') g[u.rel]++;
    if (u.rel === 'new') g.newSteps.push(`${u.step}=${u.verdict.slice(5)}`);
    groups.set(key, g);
  }
  const rels = { ok: 0, both: 0, cleared: 0, new: 0, unmeasured: 0, undecided: 0 };
  for (const u of units) rels[u.rel]++;
  const totals = { units: units.length, pass: 0, fail: 0, skip: 0, coverageFail: 0, coverageNew: 0, firstLate: 0, firstOpen: 0, baseFirstLate: 0, baseFirstOpen: 0, moved: 0 };
  for (const u of units) {
    totals[u.verdict === pass ? 'pass' : isFail(u.verdict) ? 'fail' : 'skip']++;
    if (u.verdict === fail('coverage')) { totals.coverageFail++; if (u.rel === 'new') totals.coverageNew++; }
    if (u.verdict === skip('firstLate')) totals.firstLate++;
    if (u.verdict === skip('firstOpen')) totals.firstOpen++;
    if (u.base === skip('firstLate')) totals.baseFirstLate++;
    if (u.base === skip('firstOpen')) totals.baseFirstOpen++;
    if (u.rel === 'undecided' && u.relAll !== 'undecided') totals.moved++;
  }
  const relList = units.map((u) => u.rel);
  return { refused: false, detail: '', arms, units, groups: [...groups.values()], totals, rels, notes, fails: laneFails(units.map((u) => u.verdict)), red: laneRed(relList), lane: laneOf(relList), timing };
}

export function verdictLines(engine, search, red) {
  const s = search || '(default)';
  if (red.refused) return [`VERDICT trajectory ${engine} search=${s} REFUSED config: ${red.detail}`];
  const lines = [];
  for (const g of red.groups.filter((x) => x.newSteps.length > 0)) {
    lines.push(`VERDICT trajectory ${engine} w=${g.width} ${g.path} ${g.node}.${g.prop} NEW ${g.newSteps.length}/${g.pass + g.fail + g.skip} units: ${g.newSteps.slice(0, 6).join(' ')}${g.newSteps.length > 6 ? ' ...' : ''}`);
  }
  lines.push(`VERDICT trajectory ${engine} search=${s} ${red.lane.toUpperCase()} new=${red.rels.new} both=${red.rels.both} unmeasured=${red.rels.unmeasured} undecided=${red.rels.undecided} cleared=${red.rels.cleared} ok=${red.rels.ok} units=${red.totals.units} fail=${red.totals.fail} coverage=${red.totals.coverageFail} coverage_new=${red.totals.coverageNew}`);
  lines.push(`FIRSTFRAME trajectory ${engine} search=${s} open@1 without a rewrite sample: skip:firstLate candidate ${red.totals.firstLate} faithful ${red.totals.baseFirstLate}, skip:firstOpen candidate ${red.totals.firstOpen} faithful ${red.totals.baseFirstOpen}`);
  for (const t of red.timing) lines.push(`TIMING trajectory ${engine} ${t.role} ${t.phase} n=${t.n} read p50=${t.readP50} p90=${t.readP90} ms gap p50=${t.gapP50 ?? '-'} p90=${t.gapP90 ?? '-'} ms${t.dominate ? ' READS-DOMINATE' : ''}`);
  return lines;
}
