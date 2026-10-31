import { BAND, MIN_ROUNDS, STAGES, rate } from './sim-end-floor.mjs';
import { TIER_RANK, delta, overallEdge, overallTier, tier } from './sim-floor-attrib.mjs';
import { overallNames, roundName } from './sim-end-floor.mjs';

export const CENSUS_CAP = 24;
export const ARM_IDS = Object.freeze(['v2p', 'parks', 'pauses', 'both']);
export const LIVE_STAGES = Object.freeze(['end', 'back']);

const FADED = ['platform', 'faded-pause'];
const THREAD = [['engine.scroll', 'unthrottle'], ['hero.exit', 'threaded']];
const V2P = [...THREAD, FADED];
const PARK = [['engine.scroll', 'unthrottle-park'], ['hero.exit', 'threaded-park']];
const PAUSE = [['hero.accent', 'offscreen-pause'], ['hero.cue', 'offscreen-pause'], ['platform.sweep', 'offscreen-pause']];
export const ARM_FLAGS = Object.freeze({ v2p: V2P, parks: [...PARK, FADED], pauses: [...THREAD, ...PAUSE], both: [...PARK, ...PAUSE] });
const HAS = { v2p: [false, false], parks: [true, false], pauses: [false, true], both: [true, true] };
const onOff = (b) => (b ? 'on' : 'off');
export const ARM_SETS = Object.freeze(Object.fromEntries(ARM_IDS.map((id) => [id, [['parks', onOff(HAS[id][0])], ['pauses', onOff(HAS[id][1])]]])));
export const SET_PARTS = Object.freeze({ parks: ['engine.scroll', 'hero.exit'], pauses: ['platform', 'hero.accent', 'hero.cue', 'platform.sweep'] });

export const EDGES = Object.freeze([
  { arm: 'parks', cmp: 'v2p', stages: LIVE_STAGES },
  { arm: 'pauses', cmp: 'v2p', stages: LIVE_STAGES },
  { arm: 'both', cmp: 'parks', stages: LIVE_STAGES },
  { arm: 'both', cmp: 'pauses', stages: LIVE_STAGES },
]);
export const edgeParts = (e) => delta(ARM_SETS[e.cmp], ARM_SETS[e.arm]);
export const edgeRealParts = (e) => delta(ARM_FLAGS[e.cmp], ARM_FLAGS[e.arm]);

export function edgeTier(buildArm, buildCmp, fa, fc, ta, tc) {
  if (ta === 'unreadable' || tc === 'unreadable') return 'unreadable';
  if (ta === 'off' || tc === 'off') return 'offGrid';
  if (buildArm !== buildCmp) return 'notAttributable';
  const d = delta(fc, fa);
  if (d.length !== 1) return 'notAttributable';
  if (ta === tc) return `noEffect:${d[0]}`;
  return `${TIER_RANK[ta] < TIER_RANK[tc] ? 'cut' : 'raised'}:${d[0]}`;
}
export const edgeOf = (build, e, wa, wc) => edgeTier(build, build, ARM_SETS[e.arm], ARM_SETS[e.cmp], tier(wa), tier(wc));

/** The prediction recorded before the first run (sim-floor-attrib section 6): both reaches 100, parks alone and pauses alone stay 200. */
export const PRED_TIER = Object.freeze({ v2p: 'two', parks: 'two', pauses: 'two', both: 'one' });
export const predEdge = (e) => edgeTier('b', 'b', ARM_SETS[e.arm], ARM_SETS[e.cmp], PRED_TIER[e.arm], PRED_TIER[e.cmp]);

export function held(overall, predicted) {
  if (overall === predicted) return 'held';
  if (overall === 'inconclusive' || overall === 'mixed') return 'undecided';
  return 'missed';
}
export const heldGated = (overall, predicted, took) => gate(held(overall, predicted), took);

const hasPrefix = (pre, s) => s.startsWith(pre);
export function kindOf(name) {
  if (hasPrefix('accent-module_idle', name)) return 'accent idle';
  if (hasPrefix('cue-module_scrollFloat', name)) return 'cue float';
  if (hasPrefix('sweep-module_sweepDoc', name)) return 'platform sweep';
  return 'other';
}
const KINDS = ['accent idle', 'cue float', 'platform sweep', 'other'];

export const toCensus = (c, sweep = null) => ({
  byKey: Object.entries(c?.by ?? {}),
  running: (c?.running ?? []).map((x) => x[1]),
  paused: (c?.paused ?? []).map((x) => x[1]),
  parked: c?.parked ?? 0,
  ut: c?.ut ?? 0,
  utParked: c?.utParked ?? 0,
  sweepHidden: Array.isArray(sweep) ? sweep.filter((l) => l[1] === 'running' && !l[4]).length : null,
});
const sumKeys = (c, pre) => c.byKey.filter(([k]) => hasPrefix(pre, k)).reduce((s, [, n]) => s + n, 0);
export const viewDriven = (c) => sumKeys(c, 'view:');
export const scrollDriven = (c) => sumKeys(c, 'scroll:');
export const complete = (c) => c.running.length < CENSUS_CAP && c.paused.length < CENSUS_CAP;
const runningOf = (c, k) => c.running.filter((n) => kindOf(n) === k).length;
const pauseTook = (c, k) => complete(c) && runningOf(c, k) === 0;

const sweepTook = (c) => complete(c) && c.sweepHidden === 0;

export const FLAGS = Object.freeze([
  { name: 'engine.scroll:unthrottle', took: (c) => c.ut > 0 && scrollDriven(c) > 0 },
  { name: 'hero.exit:threaded', took: (c) => viewDriven(c) > 0 && c.parked === 0 },
  { name: 'hero.exit:threaded-park', took: (c) => viewDriven(c) === 0 && c.parked > 0 },
  { name: 'engine.scroll:unthrottle-park', took: (c) => scrollDriven(c) === 0 && c.utParked > 0 },
  { name: 'hero.accent:offscreen-pause', took: (c) => pauseTook(c, 'accent idle') },
  { name: 'hero.cue:offscreen-pause', took: (c) => pauseTook(c, 'cue float') },
  { name: 'platform.sweep:offscreen-pause', took: sweepTook },
]);
export const active = (id) => [...(HAS[id][0] ? FLAGS.slice(2, 4) : FLAGS.slice(0, 2)), ...(HAS[id][1] ? FLAGS.slice(4) : [])];
export const sideTook = (id, c) => active(id).every((f) => c !== null && f.took(c));
export const edgeTook = (e, rounds) => rounds.every(([ca, cc]) => sideTook(e.arm, ca) && sideTook(e.cmp, cc));
export const missing = (id, c) => active(id).filter((f) => !f.took(c)).map((f) => f.name);
export function effectName(id, c) {
  if (active(id).length === 0) return 'none';
  const m = missing(id, c);
  return m.length === 0 ? 'took' : `missing:${m.join(',')}`;
}
export function stillTicks(c) {
  return [['view-driven', viewDriven(c)], ['scroll-driven', scrollDriven(c)], ...KINDS.map((k) => [`${k} running`, runningOf(c, k)])].filter(([, n]) => n > 0);
}
export const overallEffect = (ns) => overallNames(ns.filter((n) => n !== 'none'));

export const sourceRemains = (c) => stillTicks(c).length > 0;
export const sweepOnly = (c) => viewDriven(c) === 0 && scrollDriven(c) === 0 && ['accent idle', 'cue float', 'other'].every((k) => runningOf(c, k) === 0) && runningOf(c, 'platform sweep') > 0;
export const LAYER_SWEEP = 'platform.sweep:layer-sweep';
export const candidateOf = (c) => (sweepOnly(c) ? LAYER_SWEEP : null);

export const predTierFor = (id, c) => (c && id === 'both' && sourceRemains(c) ? 'two' : PRED_TIER[id]);
export const predEdgeFor = (e, ca, cc) => edgeTier('b', 'b', ARM_SETS[e.arm], ARM_SETS[e.cmp], predTierFor(e.arm, ca), predTierFor(e.cmp, cc));
export const overallPred = (e, rounds) => overallNames(rounds.map(([ca, cc]) => predEdgeFor(e, ca, cc)));
export const gate = (v, took) => (took ? v : 'untested');

const EMPTY = { raf: 0, seen: 0, recalcs: 0, tally: {} };
const win = (r, id, stage) => r.arms[id]?.[stage] ?? EMPTY;
const CENSUS_OF = { end: 'anims', back: 'animsBack', paused: 'animsPaused' };
const SWEEP_OF = { end: 'sweepEnd', back: 'sweepBack' };
const censusOf = (r, id, stage) => (r.arms[id]?.[CENSUS_OF[stage]] ? toCensus(r.arms[id][CENSUS_OF[stage]], r.arms[id][SWEEP_OF[stage]]) : null);
const per = (n, raf) => (raf === 0 ? '-' : (n / raf).toFixed(2));
const PAUSED_ARMS = ['v2p', 'both'];
const stagesOf = (id) => (PAUSED_ARMS.includes(id) ? STAGES : LIVE_STAGES);

/** The rate and tier table: live stages for every arm, the paused stage for v2p and both as a reference. */
export function tableLines(merged) {
  const out = [];
  for (const stage of STAGES) {
    for (const id of ARM_IDS) {
      if (!stagesOf(id).includes(stage)) continue;
      const ws = merged.rounds.map((r) => win(r, id, stage));
      if (ws.every((w) => w.raf === 0)) { out.push(`${stage} ${id}: unread`); continue; }
      const col = (f) => ws.map(f).join(', ');
      const tiers = ws.map(tier);
      out.push(`${stage} ${id}: rate per 100 [${col((w) => rate(w))}]; recalcs/frame [${col((w) => per(w.recalcs, w.raf))}]; schedule/frame [${col((w) => per(w.tally.ScheduleStyleRecalculation ?? 0, w.raf))}]; layout/frame [${col((w) => per(w.tally.Layout ?? 0, w.raf))}]; paint/frame [${col((w) => per(w.tally.Paint ?? 0, w.raf))}]; tier [${tiers.join(', ')}] overall ${overallTier(tiers)}`);
    }
  }
  return out;
}

/** The verdict file: prediction, per-edge verdicts against the named comparator and whether the prediction held, per-arm tiers, the census effect and what still ticks. */
export function verdictLines(merged) {
  const out = [];
  const m = merged.meta ?? {};
  out.push(`sim-end-cut band ${BAND} per 100, min rounds ${MIN_ROUNDS}, rounds ${merged.rounds.length}, builds ${(m.builds ?? []).join(' ') || '-'}`);
  out.push(`runtime ${m.runtime ?? '-'} ua ${m.ua ?? '-'}`);
  out.push('prediction (recorded before the run): v2p two, parks two, pauses two at the live stages; both one only if no source remains in its census, two otherwise (INFERRED: the 2 in-view sweep loops remain, so both two)');
  const build = m.builds?.[0] ?? 'local';
  for (const e of EDGES) {
    const parts = edgeParts(e).join('+');
    for (const stage of e.stages) {
      const vs = [];
      const pairs = merged.rounds.map((r) => [censusOf(r, e.arm, stage), censusOf(r, e.cmp, stage)]);
      const took = edgeTook(e, pairs);
      const pred = overallPred(e, pairs);
      for (const r of merged.rounds) {
        const v = edgeOf(build, e, win(r, e.arm, stage), win(r, e.cmp, stage));
        vs.push(v);
        out.push(`${e.arm} against ${e.cmp} [${parts}] ${stage} ${roundName(r)}: ${rate(win(r, e.arm, stage))} against ${rate(win(r, e.cmp, stage))} per 100 -> ${v}`);
      }
      const ov = overallEdge(vs);
      out.push(`${e.arm} against ${e.cmp} [${parts}] ${stage} overall: ${gate(ov, took)} (rate reading ${ov}); predicted ${pred}; ${heldGated(ov, pred, took)}`);
    }
  }
  for (const stage of STAGES) {
    for (const id of ARM_IDS) {
      if (!stagesOf(id).includes(stage)) continue;
      const ts = merged.rounds.map((r) => tier(win(r, id, stage)));
      const ov = overallTier(ts);
      const live = LIVE_STAGES.includes(stage);
      const took = live && merged.rounds.every((r) => sideTook(id, censusOf(r, id, stage)));
      const preds = merged.rounds.map((r) => predTierFor(id, censusOf(r, id, stage)));
      const pt = preds.every((x) => x === preds[0]) ? preds[0] : 'mixed';
      out.push(`tier ${id} ${stage}: [${ts.join(', ')}] overall ${ov}${live ? `; predicted ${pt}; ${heldGated(ov, pt, took)}` : ' (reference)'}`);
    }
  }
  for (const stage of LIVE_STAGES) {
    for (const id of ARM_IDS) {
      const ns = [];
      for (const r of merged.rounds) {
        const c = censusOf(r, id, stage);
        if (!c) { out.push(`effect ${id} ${stage} ${roundName(r)}: no census`); continue; }
        const n = effectName(id, c);
        ns.push(n);
        const st = stillTicks(c).map(([k, x]) => `${k} ${x}`).join(', ') || 'nothing';
        out.push(`effect ${id} ${stage} ${roundName(r)}: ${n}; still ticks: ${st}; complete ${complete(c)}`);
      }
      out.push(`effect ${id} ${stage} overall: ${overallEffect(ns)}`);
    }
  }
  for (const stage of LIVE_STAGES) {
    for (const id of ARM_IDS) {
      const ts = [];
      for (const r of merged.rounds) {
        ts.push(tier(win(r, id, stage)));
        const c = censusOf(r, id, stage);
        if (!c) continue;
        const cand = candidateOf(c);
        const st = stillTicks(c).map(([k, x]) => `${k} ${x}`).join(', ') || 'nothing';
        out.push(`sources ${id} ${stage} ${roundName(r)}: ${st}; sweep loops running ${runningOf(c, 'platform sweep')}, hidden ${c.sweepHidden ?? '-'}; owners ${ownersText(r.arms[id]?.[CENSUS_OF[stage]])}${cand ? `; candidate ${cand} (spec only, class L)` : ''}`);
      }
      const ov = overallTier(ts);
      out.push(`answer ${id} ${stage}: tiers [${ts.join(', ')}] overall ${ov}; reaches 100 per 100: ${ov === 'one' ? 'yes' : ov === 'two' ? 'no' : 'undecided'}`);
    }
  }
  return out;
}

export function ownersText(raw) {
  const n = {};
  for (const x of raw?.running ?? []) { const k = `${x[1] || '?'} on ${x[2]}`; n[k] = (n[k] ?? 0) + 1; }
  return Object.entries(n).map(([k, v]) => `${k} x${v}`).join('; ') || 'none';
}
