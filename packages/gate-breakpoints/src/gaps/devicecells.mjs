// The 8 gap cells on the real phone, one row per cell, next to the Simulator's. Shaping and equality only:
//   - what Lean says about the requested environment is Lean's (gate.reach through verdict.mjs `reach`, port webkit-apple);
//   - "the phone realized the request" and "phone equals Simulator" are plain comparisons of reported facts (TS stand-ins,
//     listed in the handoff): fractional cell W: media width === W; cross cell: reported (hover, pointer) pair === requested.
// A cell AGREES when Lean says unreachable, the phone did not realize the request, and the phone reported the same facts as the
// Simulator iPhone for the same request. Anything else is DISAGREE (with the reason).
import { reach } from '../verdict.mjs';
import { probeEnv } from '../spec.mjs';
import { pairOf } from './judge.mjs';

const facts = (r) => (r?.gap ? { mediaWidth: r.gap.mediaWidth, vvWidth: r.gap.vvWidth, innerWidth: r.gap.innerWidth, screenWidth: r.gap.screenWidth, pair: pairOf(r.gap.pointer) } : null);
const sameFacts = (a, b) => a && b && a.mediaWidth === b.mediaWidth && a.vvWidth === b.vvWidth && a.innerWidth === b.innerWidth && a.pair.hover === b.pair.hover && a.pair.pointer === b.pair.pointer;

/**
 * @param {object[]} cells gapCells(gen); @param {object[]} device phone records {req:{variant}|{load}, gap}; @param {object[]} sim Simulator iPhone records
 * @returns {{cells: object[], agree: number, disagree: number}}
 */
export function deviceCells({ cells, device, sim }) {
  const out = cells.map((c) => {
    const env = probeEnv(c.probe);
    const [leanReason] = reach('webkit-apple', [env]);
    const pick = (recs) => (c.kind === 'fractional'
      ? recs.filter((r) => r.req?.aimed === c.probe.width)
      : recs.filter((r) => r.req?.load !== undefined));
    const dev = pick(device), sm = pick(sim);
    const why = [];
    if (leanReason === null) why.push('Lean says the cell is reachable');
    if (dev.length === 0) why.push('no phone record for this cell');
    const realized = dev.map((r) => (c.kind === 'fractional' ? r.gap?.mediaWidth === c.probe.width : (() => { const p = pairOf(r.gap.pointer); return p.hover === env.hover && p.pointer === env.pointer; })()));
    if (realized.some(Boolean)) why.push('the phone realized the requested environment');
    const byKey = (r) => r.req.variant ?? `load-${r.req.load}`;
    const pairs = dev.map((d) => ({ key: byKey(d), device: facts(d), simulator: facts(sm.find((s) => byKey(s) === byKey(d)) ?? null) }));
    for (const p of pairs) if (!sameFacts(p.device, p.simulator)) why.push(`phone and Simulator differ on ${p.key}`);
    return {
      id: c.id, kind: c.kind, lean: leanReason === null ? 'reachable' : `unreachable:${leanReason}`,
      requested: c.kind === 'fractional' ? { width: c.probe.width } : { hover: env.hover, pointer: env.pointer },
      records: pairs, realizedOnPhone: realized.some(Boolean), agree: why.length === 0, why,
    };
  });
  return { cells: out, agree: out.filter((x) => x.agree).length, disagree: out.filter((x) => !x.agree).length };
}
