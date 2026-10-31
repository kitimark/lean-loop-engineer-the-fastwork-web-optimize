// sim-layer-sweep: does platform.sweep:layer-sweep remove the last per-frame scheduled style recalc at the end of the page on the iOS Simulator.
//
// TS STAND-IN of lean/Fw/Device/SimLayerSweep.lean: accelerated, shareFull, effectTicks, effectDemand, reasonOf, the layer census (layerRunning, foreignRunning,
// sweepDocLoops, layerOnly, layerSweepTook), layerEvidence, predTierL, the arms and their took-checks, edgeOfL, predEdgeL, edgeTookL and overallPredL are checked against
// packages/contracts/golden/device/sim-layer-sweep.jsonl (test/sim-layer-sweep.test.mjs). The page script and the inspector probe only count; they decide nothing.
// The reductions layerReadOf (raw rows to the Lean LayerRead) and the report lines are TS stand-ins without a Lean golden.
import { STAGES, rate, overallNames, roundName } from './sim-end-floor.mjs';
import { overallEdge, overallTier, tier } from './sim-floor-attrib.mjs';
import { ARM_FLAGS as CUT_FLAGS, FLAGS, LIVE_STAGES, active as cutActive, complete, edgeTier, gate, held, heldGated, kindOf, overallEffect, ownersText, predTierFor, scrollDriven, stillTicks, toCensus, viewDriven } from './sim-end-cut.mjs';

export const LAYER_PREFIX = 'sweep-module_sweepLayerX';
export const SWEEP_ITER_MS = 4000;
export const SWEEP_LOOP_COUNT = 5;
export const WINDOW_MS_MAX = 8000;
export const LARM_IDS = Object.freeze(['both', 'bothL']);
export const LAYER_SWEEP = ['platform.sweep', 'layer-sweep'];

export const accelerated = (p) => p === 'transform' || p === 'opacity';
/** Lean `shareOf props = full`: at least one property and every property is accelerated. */
export const shareFull = (props) => props.length > 0 && props.every(accelerated);

/** Lean `Effect.ticks` (KeyframeEffect.cpp:2724-2745 @862f17d). `rep` is null on the Core Animation path, else true when the representation is missing or a property is disallowed. */
export function effectTicks(e) {
  if (e.props.length === 0) return false;
  if (!e.rendered) return false;
  if (shareFull(e.props) && e.running) return e.rep === null ? false : e.rep;
  return true;
}
export function effectDemand(e, listeners) {
  if (effectTicks(e)) return 'everyFrame';
  return listeners && e.css ? 'perIteration' : 'atEnd';
}

export const iterTicks = (windowMs, iterMs) => Math.floor(windowMs / iterMs) + 1;
export const iterRate = (loops, windowMs, iterMs, frames) => Math.floor((loops * iterTicks(windowMs, iterMs) * 100) / frames);

/** Lean `reasonOf`: all layers carry the animation reason, none does, or no verdict. */
export function reasonOf(layers, anim) {
  if (layers === 0) return null;
  if (anim === layers) return true;
  if (anim === 0) return false;
  return null;
}

export const layerEvidence = (r) => {
  if (r.loops === 0) return 'noLoops';
  if (!shareFull(r.props)) return 'notAccelerated';
  if (r.reason === false) return 'contradicted';
  return r.reason === true ? 'inspector' : 'inferred';
};
export const readEffect = (r, rep) => ({ props: r.props, rendered: true, running: r.reason !== false, rep, css: true });

const hasPrefix = (pre, s) => s.startsWith(pre);
export const layerRunning = (c) => c.running.filter((n) => hasPrefix(LAYER_PREFIX, n)).length;
export const foreignRunning = (c) => c.running.length - layerRunning(c);
export const sweepDocLoops = (c) => [...c.running, ...c.paused].filter((n) => kindOf(n) === 'platform sweep').length;
export const layerOnly = (c) => viewDriven(c) === 0 && scrollDriven(c) === 0 && foreignRunning(c) === 0;
export const layerSweepTook = (c) => complete(c) && layerRunning(c) > 0 && sweepDocLoops(c) === 0;

export function predTierL(r, rep, c) {
  if (r === null) return 'two';
  if (!layerOnly(c)) return 'two';
  return layerRunning(c) > 0 && effectTicks(readEffect(r, rep)) ? 'two' : 'one';
}

/** The still-ticking sources of the census without the layer loops, which the model says add no frame tick. */
export const stillTicksL = (c) => stillTicks(c).map(([k, n]) => [k, k === 'other running' ? n - layerRunning(c) : n]).filter(([, n]) => n > 0);

export const LARM_FLAGS = Object.freeze({
  both: CUT_FLAGS.both,
  bothL: [['engine.scroll', 'unthrottle-park'], ['hero.exit', 'threaded-park'], ['hero.accent', 'offscreen-pause'], ['hero.cue', 'offscreen-pause'], LAYER_SWEEP],
});
const base = (name) => FLAGS.find((f) => f.name === name);
const LAYER_FLAG = { name: 'platform.sweep:layer-sweep', took: layerSweepTook };
export const larmActive = (id) => (id === 'both' ? cutActive('both') : [base('hero.exit:threaded-park'), base('engine.scroll:unthrottle-park'), base('hero.accent:offscreen-pause'), base('hero.cue:offscreen-pause'), LAYER_FLAG]);
export const sideTookL = (id, c) => larmActive(id).every((f) => c !== null && f.took(c));
export const missingL = (id, c) => larmActive(id).filter((f) => !f.took(c)).map((f) => f.name);
export function effectNameL(id, c) {
  if (larmActive(id).length === 0) return 'none';
  const m = missingL(id, c);
  return m.length === 0 ? 'took' : `missing:${m.join(',')}`;
}
/** A stage: [census of bothL, LayerRead of bothL or null, census of both]. */
export const edgeTookL = (stages) => stages.every(([ca, , cc]) => sideTookL('bothL', ca) && sideTookL('both', cc));

export const edgeOfL = (build, wa, wc) => edgeTier(build, build, LARM_FLAGS.bothL, LARM_FLAGS.both, tier(wa), tier(wc));

export const predTierArm = (rep, id, c, r) => (id === 'both' ? predTierFor('both', c) : c === null ? 'two' : predTierL(r, rep, c));
export const predEdgeL = (rep, [ca, r, cc]) => edgeTier('b', 'b', LARM_FLAGS.bothL, LARM_FLAGS.both, predTierArm(rep, 'bothL', ca, r), predTierArm(rep, 'both', cc, null));
export const overallPredL = (rep, stages) => overallNames(stages.map((s) => predEdgeL(rep, s)));

/** The Lean LayerRead of a stage from the raw rows: loops running, the properties they animate, and the inspector verdict (null when not read or on error). */
export function layerReadOf(arm, stage) {
  const rows = stage === 'end' ? arm?.layerEnd : arm?.layerBack;
  if (!Array.isArray(rows)) return null;
  const running = rows.filter((x) => x[1] === 'running');
  const props = [...new Set(rows.flatMap((x) => x[5] ?? []))];
  const p = arm.layerProbe;
  const reason = p && !p.error ? reasonOf(p.layers ?? 0, p.animation ?? 0) : null;
  return { loops: running.length, props, reason };
}

const CENSUS_OF = { end: 'anims', back: 'animsBack', paused: 'animsPaused' };
const SWEEP_OF = { end: 'sweepEnd', back: 'sweepBack' };
const EMPTY = { raf: 0, seen: 0, recalcs: 0, tally: {} };
const win = (r, id, stage) => r.arms[id]?.[stage] ?? EMPTY;
const censusOf = (r, id, stage) => (r.arms[id]?.[CENSUS_OF[stage]] ? toCensus(r.arms[id][CENSUS_OF[stage]], r.arms[id][SWEEP_OF[stage]]) : null);
const per = (n, raf) => (raf === 0 ? '-' : (n / raf).toFixed(2));

/** The rate and tier table, every live stage and the paused stage as a reference. */
export function tableLines(merged) {
  const out = [];
  for (const stage of STAGES) {
    for (const id of LARM_IDS) {
      const ws = merged.rounds.map((r) => win(r, id, stage));
      if (ws.every((w) => w.raf === 0)) { out.push(`${stage} ${id}: unread`); continue; }
      const col = (f) => ws.map(f).join(', ');
      const tiers = ws.map(tier);
      out.push(`${stage} ${id}: rate per 100 [${col((w) => rate(w))}]; recalcs/frame [${col((w) => per(w.recalcs, w.raf))}]; schedule/frame [${col((w) => per(w.tally.ScheduleStyleRecalculation ?? 0, w.raf))}]; layout/frame [${col((w) => per(w.tally.Layout ?? 0, w.raf))}]; paint/frame [${col((w) => per(w.tally.Paint ?? 0, w.raf))}]; composite/frame [${col((w) => per(w.tally.Composite ?? 0, w.raf))}]; tier [${tiers.join(', ')}] overall ${overallTier(tiers)}`);
    }
  }
  return out;
}

const stageOf = (r, stage) => [censusOf(r, 'bothL', stage), layerReadOf(r.arms.bothL, stage), censusOf(r, 'both', stage)];

const layerRowText = (rows) => (Array.isArray(rows) ? `${rows.length} loops, ${rows.filter((x) => x[1] === 'running').length} running, ${rows.filter((x) => x[1] === 'running' && x[4]).length} in view, properties ${JSON.stringify([...new Set(rows.flatMap((x) => x[5] ?? []))])}, pending ${rows.filter((x) => x[2]).length}` : 'not read');

/** The verdict file for the pinned unit: per arm and stage the took-check, the layer census, the rates, the Lean-gated verdict against the prediction. */
export function verdictLines(merged) {
  const out = [];
  const m = merged.meta ?? {};
  out.push(`sim-layer-sweep jobs ${merged.rounds.length}, builds ${(m.builds ?? []).join(' ') || '-'}`);
  out.push(`runtime ${m.runtime ?? '-'} ua ${m.ua ?? '-'}`);
  out.push('prediction (recorded before the run): bothL reads tier one at end and back if only layer loops run and they are completely accelerated; both stays tier two while its 2 in-view sweepDoc loops run (INFERRED from WebKit KeyframeEffect.cpp:2724-2745 @862f17d)');
  const build = m.builds?.[0] ?? 'local';
  for (const stage of LIVE_STAGES) {
    const stages = merged.rounds.map((r) => stageOf(r, stage));
    const took = edgeTookL(stages);
    const vs = [];
    for (const r of merged.rounds) {
      const v = edgeOfL(build, win(r, 'bothL', stage), win(r, 'both', stage));
      vs.push(v);
      out.push(`bothL against both [platform.sweep] ${stage} ${roundName(r)}: ${rate(win(r, 'bothL', stage))} against ${rate(win(r, 'both', stage))} per 100 -> ${v}`);
    }
    const ov = overallEdge(vs);
    const pred = overallPredL(null, stages);
    out.push(`bothL against both [platform.sweep] ${stage} overall: ${gate(ov, took)} (rate reading ${ov}); predicted ${pred}; ${heldGated(ov, pred, took)}`);
  }
  for (const stage of STAGES) {
    for (const id of LARM_IDS) {
      const ts = merged.rounds.map((r) => tier(win(r, id, stage)));
      const ov = overallTier(ts);
      const live = LIVE_STAGES.includes(stage);
      if (!live) { out.push(`tier ${id} ${stage}: [${ts.join(', ')}] overall ${ov} (reference)`); continue; }
      const took = merged.rounds.every((r) => sideTookL(id, censusOf(r, id, stage)));
      const preds = merged.rounds.map((r) => predTierArm(null, id, censusOf(r, id, stage), layerReadOf(r.arms[id], stage)));
      const pt = preds.every((x) => x === preds[0]) ? preds[0] : 'mixed';
      out.push(`tier ${id} ${stage}: [${ts.join(', ')}] overall ${ov}; predicted ${pt}; ${gate(held(ov, pt), took)}`);
    }
  }
  for (const stage of LIVE_STAGES) {
    for (const id of LARM_IDS) {
      const ns = [];
      for (const r of merged.rounds) {
        const c = censusOf(r, id, stage);
        if (!c) { out.push(`effect ${id} ${stage} ${roundName(r)}: no census`); continue; }
        const n = effectNameL(id, c);
        ns.push(n);
        const st = stillTicksL(c).map(([k, x]) => `${k} ${x}`).join(', ') || 'nothing';
        out.push(`effect ${id} ${stage} ${roundName(r)}: ${n}; layer loops running ${layerRunning(c)}, sweepDoc loops ${sweepDocLoops(c)}, non-layer running ${foreignRunning(c)}; still ticks: ${st}; complete ${complete(c)}`);
      }
      out.push(`effect ${id} ${stage} overall: ${overallEffect(ns)}`);
    }
  }
  for (const stage of LIVE_STAGES) {
    for (const r of merged.rounds) {
      const arm = r.arms.bothL;
      const rd = layerReadOf(arm, stage);
      const p = arm?.layerProbe;
      const w = win(r, 'bothL', stage);
      out.push(`layer census ${stage} ${roundName(r)}: ${layerRowText(stage === 'end' ? arm?.layerEnd : arm?.layerBack)}; evidence ${rd ? layerEvidence(rd) : 'not read'}${rd ? ` (${rd.reason === null ? 'inspector not read or mixed; accelerated state INFERRED from the property list' : `inspector ${rd.reason}`})` : ''}; layer tree ${p ? JSON.stringify(p) : 'not read'}; window y ${w.y ?? '-'} of ${w.maxY ?? '-'}`);
      const sources = `owners ${ownersText(arm?.[CENSUS_OF[stage]])}`;
      out.push(`sources bothL ${stage} ${roundName(r)}: ${sources}`);
    }
  }
  const pins = [];
  for (const r of merged.rounds) for (const id of LARM_IDS) { const w = win(r, id, 'end'); pins.push(w.y !== undefined && w.y === w.maxY); }
  out.push(`pinned windows: ${pins.filter(Boolean).length} of ${pins.length} end windows read at the end of the page (y equals maxY)`);
  for (const stage of LIVE_STAGES) {
    for (const id of LARM_IDS) {
      const ts = merged.rounds.map((r) => tier(win(r, id, stage)));
      const ov = overallTier(ts);
      out.push(`answer ${id} ${stage}: tiers [${ts.join(', ')}] overall ${ov}; reaches 100 per 100: ${ov === 'one' ? 'yes' : ov === 'two' ? 'no' : 'undecided'}`);
    }
  }
  return out;
}

