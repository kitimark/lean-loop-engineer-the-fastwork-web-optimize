// The gaps lane's judging: shaping and moving data only. Every decision is Lean's, through fwcore (verdict.mjs):
//   cell on an engine   gate.state with the engine's port: pass / fail / not-comparable from the rows, or unreachable:<reason>
//                       when the requested environment is one the port cannot build (Fw.Gate.Reach; the proofs say which)
//   model check         the facts a WebKit page reported (media width, primary pair) are turned into environments and given to
//                       gate.reach; a fact the model calls unreachable would falsify it. The statuses go through gate.cell
//                       (equal = consistent with the model, missing = unreadable record, differ = contradicts it):
//                       pass = the model holds on every record, fail = a record contradicts it, not-comparable = no record
// What stays here: pairOf (the page's matchMedia answers -> hover / pointer keywords), the record -> environment mapping,
// and the grouping into the report. No rollup, no status rule, no reach rule.
import { context, evaluate, reach, cellVerdicts, tallies } from '../verdict.mjs';
import { HOW } from './cells.mjs';

/** The (hover, pointer) pair of a page from its pointer facts (null parts when neither query matched). */
export function pairOf(pointer) {
  const hover = pointer.hover === true ? 'hover' : pointer.hoverNone === true ? 'none' : null;
  const ptr = pointer.pointerFine === true ? 'fine' : pointer.pointerCoarse === true ? 'coarse' : pointer.pointerNone === true ? 'none' : null;
  return { hover, pointer: ptr };
}

/** The environment a page reported, in Lean's request form; null when a fact is missing (an unreadable record). */
export function observedEnv(gap) {
  if (!gap || typeof gap.mediaWidth !== 'number' || !gap.pointer) return null;
  const p = pairOf(gap.pointer);
  if (p.hover === null || p.pointer === null) return null;
  return {
    width: gap.mediaWidth, height: gap.innerHeight ?? 0, deviceWidth: gap.screenWidth ?? gap.mediaWidth, dpr: gap.dpr ?? 1,
    hover: p.hover, pointer: p.pointer, reducedMotion: 'no-preference', colorScheme: 'light',
  };
}

/**
 * Does the model (Fw.Gate.Reach) hold on these records? records: { gap, req, ... }. Returns { verdict, records, contradicted,
 * unreadable } where verdict is Lean's cell rule over the per-record statuses.
 */
export function modelCheck(port, records) {
  const envs = records.map((r) => observedEnv(r.gap));
  const readable = envs.filter((e) => e !== null);
  const reasons = reach(port, readable);
  let k = 0;
  const statuses = envs.map((e) => (e === null ? 'missing' : reasons[k++] === null ? 'equal' : 'differ'));
  const [verdict] = cellVerdicts([statuses]);
  const contradicted = records.filter((_, i) => statuses[i] === 'differ').map((r) => ({ req: r.req, mediaWidth: r.gap.mediaWidth, pair: pairOf(r.gap.pointer) }));
  return { verdict, records: records.length, contradicted, unreadable: statuses.filter((s) => s === 'missing').length };
}

const armFacts = (raw) => ({
  mediaWidth: raw.gap?.mediaWidth ?? null, vvWidth: raw.gap?.vvWidth ?? null, innerWidth: raw.gap?.innerWidth ?? null,
  dpr: raw.gap?.dpr ?? null, pair: raw.gap ? pairOf(raw.gap.pointer) : null,
});

/**
 * Judge the 8 cells on one engine's run file. Returns { port, cells: [{ id, kind, engine, port, how, verdict, reach, achieved,
 * deviations, rows, measured, realized }], blocks: { [block]: Lean tally } }.
 */
export function judgeRun({ cells, engine, run, anchors, deviceEdges, parts }) {
  const port = run.header.port ?? null;
  const ctx = context({ anchors, parts, props: run.header.props, deviceEdges, port });
  const mine = cells.filter((c) => run.probes.some((p) => p.id === c.id));
  const recs = mine.map((c) => run.probes.find((p) => p.id === c.id));
  const { states } = evaluate(ctx, mine.map((c, i) => ({ requested: recs[i].env, orig: recs[i].orig, rewrite: recs[i].rewrite, expect: c.probe.expect, expectNeutral: c.probe.expectNeutral })));
  const out = mine.map((c, i) => ({
    id: c.id, kind: c.kind, engine, port, how: HOW[`${c.kind}/${engine}`],
    verdict: states[i].verdict, reach: states[i].reach, achieved: states[i].achieved, deviations: states[i].dev,
    rows: states[i].rows, fails: states[i].fails,
    measured: { orig: armFacts(recs[i].orig.raw), rewrite: armFacts(recs[i].rewrite.raw) },
    env: recs[i].env, realized: recs[i].realized ?? null,
  }));
  const blocks = [...new Set(mine.map((c) => c.block))];
  const tallied = tallies(blocks.map((b) => ({ verdicts: out.filter((_, i) => mine[i].block === b).map((x) => x.verdict), block: true })));
  return { port, cells: out, blocks: Object.fromEntries(blocks.map((b, i) => [b, tallied[i]])) };
}
