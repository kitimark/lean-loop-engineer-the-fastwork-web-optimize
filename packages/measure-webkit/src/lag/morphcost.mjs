// Twin of the "Morph zones: cost per frame of two arms" section of lean/Fw/Measure/WkCost.lean; test/lag-morphcost.test.mjs
// checks it against golden/measure/wkcost.jsonl. A sums record is { frames, paintUs, compUs, bound } as `sumsOf` returns it.
import { frac, ratio, verdict } from './reduce.mjs';
import { sumsOf } from './cost.mjs';

export const MORPH_ZONES = Object.freeze(['idle', 'open', 'rest', 'close']);
export const METRICS = Object.freeze(['paint', 'comp']);
const sumOf = (m, s) => (m === 'paint' ? s.paintUs : s.compUs);

/** The sums of each morph zone and of calm scroll in one recorded cost pass (`fw.webkit.lag.cost.morph/1` and the scroll cost). */
export const passSums = (cost) => ({
  zones: MORPH_ZONES.map((z) => [z, sumsOf(z, cost.morph.costs)]),
  calm: sumsOf('scroll-calm', cost.scroll.costs),
});

/** Lean `PassSums.zone`: zero frames when the pass has none. */
export const zoneOf = (p, z) => (p.zones.find((e) => e[0] === z) ?? [z, { frames: 0, paintUs: 0, compUs: 0, bound: 0 }])[1];

/** Raw view: mean microseconds per frame of a zone as a fraction, null without frames (Lean `rawPF`). */
export const rawPF = (m, w) => (w.frames > 0 ? frac(sumOf(m, w), w.frames) : null);

/** Normalized view: per-frame mean over the same pass's calm-scroll per-frame mean, null without frames or time (Lean `normPF`). */
export const normPF = (m, w, b) => (w.frames > 0 && b.frames > 0 && sumOf(m, b) > 0 ? ratio(w.frames, b.frames, sumOf(m, w), sumOf(m, b)) : null);

/** Both views agreeing is the verdict; otherwise overlap (Lean `cellVerdict`). */
export const cellVerdict = (raw, norm) => (raw === norm ? norm : 'overlap');

const rawVals = (m, z, ps) => ps.map((p) => rawPF(m, zoneOf(p, z))).filter((x) => x !== null);
const normVals = (m, z, ps) => ps.map((p) => normPF(m, zoneOf(p, z), p.calm)).filter((x) => x !== null);
export const rawVerdict = (m, z, base, flag) => verdict(rawVals(m, z, base), rawVals(m, z, flag));
export const normVerdict = (m, z, base, flag) => verdict(normVals(m, z, base), normVals(m, z, flag));
export const cell = (m, z, base, flag) => cellVerdict(rawVerdict(m, z, base, flag), normVerdict(m, z, base, flag));

/** The cell rows [zone, metric, raw, norm, cell] of a run, every morph zone and both metrics. */
export const cellRows = (base, flag) =>
  MORPH_ZONES.flatMap((z) => METRICS.map((m) => [z, m, rawVerdict(m, z, base, flag), normVerdict(m, z, base, flag), cell(m, z, base, flag)]));

/** Win or loss only when every cell separates the arms the same way; otherwise the reason it is unresolved (Lean `outcome`). */
export function outcome(cs) {
  if (cs.length === 0) return 'empty';
  if (cs.every((c) => c === 'lower')) return 'win';
  if (cs.every((c) => c === 'higher')) return 'loss';
  if (cs.some((c) => c === 'lower') && cs.some((c) => c === 'higher')) return 'mixed';
  return 'overlap';
}

/** The outcome of two arms of recorded passes, a pass being the object a lag.json holds. */
export const armsOutcome = (basePasses, flagPasses) => {
  const b = basePasses.map((p) => passSums(p.cost)), f = flagPasses.map((p) => passSums(p.cost));
  const rows = cellRows(b, f);
  return { rows, outcome: outcome(rows.map((r) => r[4])) };
};
