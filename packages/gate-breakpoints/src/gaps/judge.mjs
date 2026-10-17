// Decisions of the gaps lane. Pure: no I/O, no page, no clock. It reuses the gate's rule (verdict.mjs: cellVerdict, rollup,
// truthItems, envDeviations, via summary.mjs evaluateState) for every cell whose environment the engine reached, and adds
// ONE new state, `unreachable`, for cells no mechanism can build. That state, the two evidence checks and the gap check
// below are TS STAND-INS: Lean first says they are to be specified and proved in Fw/Site (a `webkitPrimaryPairs` set, a
// whole-number media width for WebKit, and the verdict rule extended with `unreachable`) before this file is final.
//
// Statements (math), for a run's records R:
//   gapCheck(w = N + 1/2):    media width = w  and  not (width <= N)  and  not (width >= N + 1)           (Lean gap_iff)
//   fractionalEvidence(R):    forall r in R, forall N in edges: r.mediaWidth in N  and  (r.le(N) or r.ge1(N))   (Lean no_gap_ofNat)
//   crossEvidence(R):         forall r in R, (hover(r), pointer(r)) in WEBKIT_PRIMARY_PAIRS
//   state(cell, engine) = pass/fail (rollup of the compared rows)      if the environment is achieved on both arms
//                       = unreachable                                   if not achieved, the mechanism table says unreachable
//                                                                       and the evidence check holds on every record
//                       = not-comparable                                otherwise
import { rollup } from '../verdict.mjs';
import { evaluateState, rowVerdicts } from '../summary.mjs';
import { MECHANISMS, WEBKIT_PRIMARY_PAIRS } from './cells.mjs';

export const isWhole = (x) => typeof x === 'number' && Number.isInteger(x);

/** The (hover, pointer) pair of a page from its 15 pointer facts (null parts when neither query matched). */
export function pairOf(pointer) {
  const hover = pointer.hover === true ? 'hover' : pointer.hoverNone === true ? 'none' : null;
  const ptr = pointer.pointerFine === true ? 'fine' : pointer.pointerCoarse === true ? 'coarse' : pointer.pointerNone === true ? 'none' : null;
  return { hover, pointer: ptr };
}

/** Lean's gap fact at a cell: width w = N + 1/2 is in the open gap (N, N+1). */
export function gapCheck(gap, probeWidth) {
  const n = Math.floor(probeWidth);
  const e = gap?.edges?.[n];
  if (!e) return { ok: false, why: `no gap facts for edge ${n}` };
  const neither = e.le === false && e.ge1 === false && e.maxWidth === false && e.minWidth1 === false;
  const widthOk = gap.mediaWidth === probeWidth;
  return { ok: neither && widthOk, neither, widthOk, mediaWidth: gap.mediaWidth, n };
}

/** Every record of a WebKit environment has a whole media width and, for every edge, one side of the gap matches. */
export function fractionalEvidence(records) {
  const bad = [];
  for (const r of records) {
    const g = r.gap;
    if (!g || !isWhole(g.mediaWidth)) { bad.push({ at: r.req, mediaWidth: g?.mediaWidth ?? null }); continue; }
    for (const [n, e] of Object.entries(g.edges)) {
      if (e.le === false && e.ge1 === false) bad.push({ at: r.req, edge: Number(n), mediaWidth: g.mediaWidth });
    }
  }
  return { ok: records.length > 0 && bad.length === 0, records: records.length, bad };
}

/** Every record of a WebKit environment shows a primary (hover, pointer) pair that Apple WebKit can have. */
export function crossEvidence(records, pairs = WEBKIT_PRIMARY_PAIRS) {
  const bad = [];
  for (const r of records) {
    const p = r.gap ? pairOf(r.gap.pointer) : { hover: null, pointer: null };
    if (!pairs.some(([h, q]) => h === p.hover && q === p.pointer)) bad.push({ at: r.req, pair: p });
  }
  return { ok: records.length > 0 && bad.length === 0, records: records.length, bad };
}

const armFacts = (raw) => ({
  mediaWidth: raw.gap?.mediaWidth ?? null, vvWidth: raw.gap?.vvWidth ?? null, innerWidth: raw.gap?.innerWidth ?? null,
  dpr: raw.gap?.dpr ?? null, pair: raw.gap ? pairOf(raw.gap.pointer) : null,
});

/**
 * One cell on one engine.
 *   cell: { id, kind, probe }; rec: the run's probe record for the cell; ctx: { header, anchors, deviceEdges, parts }
 *   evidence: records for this kind of unreachable cell on this engine (see evidence.mjs), or null
 */
export function judgeCell({ cell, engine, rec, ctx, evidence }) {
  const mech = MECHANISMS[`${cell.kind}/${engine}`];
  const ev = evaluateState({ requested: rec.env, orig: rec.orig, rewrite: rec.rewrite, expect: cell.probe.expect, expectNeutral: cell.probe.expectNeutral, header: ctx.header, anchors: ctx.anchors, deviceEdges: ctx.deviceEdges, parts: ctx.parts });
  const rows = rowVerdicts(ev, ctx.parts);
  const measured = { orig: armFacts(rec.orig.raw), rewrite: armFacts(rec.rewrite.raw) };
  const out = { cell: cell.id, kind: cell.kind, engine, mechanism: mech.how, reach: mech.reach, achieved: ev.achieved, deviations: ev.dev, measured, rows };
  if (cell.kind === 'fractional') {
    const g = { orig: gapCheck(rec.orig.raw.gap, cell.probe.width), rewrite: gapCheck(rec.rewrite.raw.gap, cell.probe.width) };
    out.gap = g;
    rows['gap (Lean gap_iff)'] = g.orig.ok && g.rewrite.ok ? 'pass' : 'fail';
  }
  if (ev.achieved) {
    const rowIds = ['matchMedia orig=rewrite', 'matchMedia =Lean', 'matchMedia legacy text', ...(cell.kind === 'fractional' ? ['gap (Lean gap_iff)'] : [])];
    out.state = rollup(rowIds.map((k) => rows[k]));
    out.stateFrom = rowIds;
    return out;
  }
  if (mech.reach === 'unreachable' && evidence) {
    const chk = cell.kind === 'fractional' ? fractionalEvidence(evidence) : crossEvidence(evidence);
    out.evidence = chk;
    out.state = chk.ok ? 'unreachable' : 'not-comparable';
    return out;
  }
  out.state = 'not-comparable';
  return out;
}

/**
 * Judge every cell on every engine. runs: { [engine]: parsed run file }, evidence: { fractional: records, cross: records } for
 * the WebKit side. Returns { cells: [{ id, kind, engines: { [engine]: judged } }], counts }.
 */
export function judgeAll({ cells, runs, evidence, anchors, deviceEdges, parts }) {
  const out = [];
  for (const cell of cells) {
    const engines = {};
    for (const [engine, run] of Object.entries(runs)) {
      const rec = run.probes.find((p) => p.id === cell.id);
      if (!rec) continue;
      engines[engine] = judgeCell({ cell, engine, rec, ctx: { header: run.header, anchors, deviceEdges, parts }, evidence: engine === 'chromium' ? null : evidence[cell.kind] });
    }
    out.push({ id: cell.id, kind: cell.kind, engines });
  }
  const counts = {};
  for (const c of out) for (const [e, j] of Object.entries(c.engines)) { const k = `${e}:${j.state}`; counts[k] = (counts[k] ?? 0) + 1; }
  return { cells: out, counts };
}
