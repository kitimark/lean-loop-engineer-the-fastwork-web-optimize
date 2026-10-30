// sim-floor-attrib: per-arm verdicts of the Simulator end-of-page recalc rate against one named comparator (task sim-floor-attrib).
//
// TS STAND-IN of lean/Fw/Device/SimFloorAttrib.lean: tier, the arm flags, delta, edge, overallEdge and overallTier are checked against
// packages/contracts/golden/device/sim-floor-attrib.jsonl (test/sim-floor-attrib.test.mjs). The report lines only format.
import { BAND, MIN_ROUNDS, STAGES, rate, readable, overallNames } from './sim-end-floor.mjs';

const V2P_FLAGS = [['engine.scroll', 'unthrottle'], ['hero.exit', 'threaded'], ['platform', 'faded-pause']];
export const ARM_FLAGS = Object.freeze({
  base: [],
  v2p: V2P_FLAGS,
  minusT: [['engine.scroll', 'unthrottle'], ['platform', 'faded-pause']],
  minusU: [['hero.exit', 'threaded'], ['platform', 'faded-pause']],
  blank: [['content', 'blank']],
  minusBoth: [['platform', 'faded-pause']],
  v2pCancelScroll: [...V2P_FLAGS, ['scrollAnimations', 'cancelled']],
});

const ALL = ['end', 'back', 'paused'];
/** The named comparisons, in the Lean `edges` order: each arm against the one comparator it is judged by. */
export const EDGES = Object.freeze([
  { arm: 'blank', cmp: 'base', stages: ALL },
  { arm: 'minusBoth', cmp: 'base', stages: ALL },
  { arm: 'minusBoth', cmp: 'v2p', stages: ALL },
  { arm: 'minusBoth', cmp: 'minusT', stages: ALL },
  { arm: 'minusBoth', cmp: 'minusU', stages: ALL },
  { arm: 'v2pCancelScroll', cmp: 'v2p', stages: ['paused'] },
]);

const get = (fs, p) => fs.find((x) => x[0] === p)?.[1];
/** Lean `Attrib.delta`: the parts whose values differ, in first-seen order. */
export function delta(a, b) {
  const parts = [...new Set([...a.map((x) => x[0]), ...b.map((x) => x[0])])];
  return parts.filter((p) => get(a, p) !== get(b, p));
}
export const edgeParts = (e) => delta(ARM_FLAGS[e.cmp], ARM_FLAGS[e.arm]);

export const TIER_RANK = { unreadable: 0, zero: 0, one: 1, two: 2, off: 3 };
export function tier(w) {
  if (!readable(w)) return 'unreadable';
  const r = rate(w);
  if (r <= BAND) return 'zero';
  if (100 - BAND <= r && r <= 100 + BAND) return 'one';
  if (200 - BAND <= r && r <= 200 + BAND) return 'two';
  return 'off';
}

/** Lean `edge` for one pair of windows; the builds are the commits of the two runs. */
export function edge(buildArm, buildCmp, arm, cmp, wa, wc) {
  const ta = tier(wa), tc = tier(wc);
  if (ta === 'unreadable' || tc === 'unreadable') return 'unreadable';
  if (ta === 'off' || tc === 'off') return 'offGrid';
  if (buildArm !== buildCmp) return 'notAttributable';
  const d = delta(ARM_FLAGS[cmp], ARM_FLAGS[arm]);
  if (d.length !== 1) return 'notAttributable';
  if (ta === tc) return `noEffect:${d[0]}`;
  return `${TIER_RANK[ta] < TIER_RANK[tc] ? 'cut' : 'raised'}:${d[0]}`;
}
export const edgeOf = (build, e, wa, wc) => edge(build, build, e.arm, e.cmp, wa, wc);

export const overallEdge = (vs) => overallNames(vs.filter((v) => v !== 'unreadable' && v !== 'offGrid'));
export const overallTier = (ts) => overallNames(ts.filter((t) => t !== 'unreadable' && t !== 'off'));

/** Rounds of several raw files, numbered 1..N in file order (one CI job each); `runs` keeps the file of each round. */
export function mergeRaws(raws) {
  const rounds = [];
  const builds = new Set();
  raws.forEach((raw, i) => {
    if (raw.meta?.build) builds.add(raw.meta.build);
    for (const r of raw.rounds) rounds.push({ ...r, round: rounds.length + 1, file: i + 1 });
  });
  return { meta: { ...(raws[0]?.meta ?? {}), builds: [...builds] }, rounds };
}

const EMPTY = { raf: 0, seen: 0, recalcs: 0, tally: {} };
const win = (r, id, stage) => r.arms[id]?.[stage] ?? EMPTY;
const per = (n, raf) => (raf === 0 ? '-' : (n / raf).toFixed(2));

/** The table: per stage and arm, the rate, recalcs, scheduled recalcs, layouts, paints per frame and the tier, by round and overall. */
export function tableLines(merged) {
  const out = [];
  const ids = Object.keys(ARM_FLAGS);
  for (const stage of STAGES) {
    for (const id of ids) {
      const ws = merged.rounds.map((r) => win(r, id, stage));
      if (ws.every((w) => w.raf === 0)) { out.push(`${stage} ${id}: unread`); continue; }
      const col = (f) => ws.map(f).join(', ');
      const tiers = ws.map(tier);
      out.push(`${stage} ${id}: rate per 100 [${col((w) => rate(w))}]; recalcs/frame [${col((w) => per(w.recalcs, w.raf))}]; schedule/frame [${col((w) => per(w.tally.ScheduleStyleRecalculation ?? 0, w.raf))}]; layout/frame [${col((w) => per(w.tally.Layout ?? 0, w.raf))}]; paint/frame [${col((w) => per(w.tally.Paint ?? 0, w.raf))}]; tier [${tiers.join(', ')}] overall ${overallTier(tiers)}`);
    }
  }
  return out;
}

/** The verdict file: every named edge, per stage and round, then overall; the build of each round is the Attrib commit. */
export function verdictLines(merged) {
  const out = [];
  const m = merged.meta ?? {};
  out.push(`sim-floor-attrib band ${BAND} per 100, min rounds ${MIN_ROUNDS}, rounds ${merged.rounds.length}, builds ${(m.builds ?? []).join(' ') || '-'}`);
  out.push(`runtime ${m.runtime ?? '-'} ua ${m.ua ?? '-'}`);
  for (const e of EDGES) {
    const parts = edgeParts(e).join('+');
    for (const stage of e.stages) {
      const vs = [];
      for (const r of merged.rounds) {
        const v = edgeOf(m.builds?.[0] ?? 'local', e, win(r, e.arm, stage), win(r, e.cmp, stage));
        vs.push(v);
        out.push(`${e.arm} against ${e.cmp} [${parts}] ${stage} round ${r.round}: ${rate(win(r, e.arm, stage))} against ${rate(win(r, e.cmp, stage))} per 100 -> ${v}`);
      }
      out.push(`${e.arm} against ${e.cmp} [${parts}] ${stage} overall: ${overallEdge(vs)}`);
    }
  }
  return out;
}
