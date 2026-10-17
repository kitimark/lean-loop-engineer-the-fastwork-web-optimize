// A and R of the WebKit lane, compared by scroll position. GLUE ONLY: the pairing of steps and the zone sums are
// Lean's (`Fw.Measure.StepAlign`, fwcore op `measure.webkit.align`); this file builds requests, reads replies and
// prints. Nothing here decides anything.
//
// Why: the original (document 6042 px at 430x775, 107 steps of 50 px) and the rewrite (4378 px, 74 steps) are
// scrolled by the same schedule (y = 0, 50, 100 ... up to the page's own maximum offset), so the steps agree by
// OFFSET but not by index. Two steps are the same piece of trajectory when previous offset, offset and next offset are
// equal; zones (500 px bands) are summed over the paired steps, and a zone is `full` when every step of both runs in
// it is paired.
import { fwcoreCall } from './handoff.mjs';
import { COUNT_TYPES, TOL, classify } from './reduce.mjs';

/** The scroll part of one pass as an align request side. */
export const runOf = (scroll) => ({ ys: scroll.ys, perStep: scroll.reduced.perStep, perStepPaintArea: scroll.reduced.perStepPaintArea });

/** The scrolls of a `determinism` file (passes) or a `perstep` file (entries of `mode`). */
export function scrollsOf(file, mode = 'base') {
  return file.passes ? file.passes.map((p) => p.scroll) : file.entries.filter((e) => e.mode === mode).map((e) => e.scroll);
}

/**
 * fwcore `measure.webkit.align` for pass i of A against pass i of R (the passes pair in order: both arms ran their passes
 * from fresh loads in the same session layout).
 * @returns {Promise<{pairs: object[]}>} pairs[i] = the reply of fwcore
 */
export async function alignPasses(aScrolls, rScrolls, zonePx = 500) {
  const n = Math.min(aScrolls.length, rScrolls.length);
  if (n === 0) throw new Error('align needs at least one scroll pass on each side');
  const replies = await fwcoreCall(Array.from({ length: n }, (_, i) => ({ id: `align-${i}`, op: 'measure.webkit.align', a: runOf(aScrolls[i]), b: runOf(rScrolls[i]), zonePx })));
  const bad = replies.find((r) => r.error);
  if (bad) throw new Error(`fwcore: ${bad.error}`);
  return { passes: n, pairs: replies.map(({ id, ...reply }) => reply) };
}

/**
 * Markdown table of one count type: per zone the A sums and R sums of the paired steps over the passes and the delta
 * per pass. Values are listed as they are (no statistics); `full` zones are comparable as a whole.
 */
export function zoneTable(pairs, type) {
  if (!COUNT_TYPES.includes(type)) throw new Error(`unknown count type ${type}`);
  const zs = pairs[0].zones;
  const list = (z, f) => pairs.map((p) => f(p.zones[z])).join(' / ');
  const lines = [`| zone y0 | steps A / R | paired | full | A ${type} | R ${type} | A - R |`, '|---|---|---|---|---|---|---|'];
  zs.forEach((z, i) => {
    lines.push(`| ${z.y0} | ${z.stepsA} / ${z.stepsB} | ${z.pairedA} | ${z.full ? 'yes' : 'no'} | ${list(i, (q) => q.countsA[type])} | ${list(i, (q) => q.countsB[type])} | ${list(i, (q) => q.delta[type])} |`);
  });
  return lines.join('\n');
}

/** One summary line: how much of each arm took part (paired steps and full zones). */
export function coverageLine(pair, aSteps, rSteps) {
  const zones = pair.zones.length;
  return `zones ${zones}, full ${pair.full.zones}; paired steps ${pair.paired.steps} of A ${aSteps} / R ${rSteps}; steps in full zones ${pair.full.steps}`;
}

/**
 * Classes of the aligned zone sums over many passes (all passes of all VMs and sessions): per count type, the A sums, the R
 * sums and the delta A - R over the zones that are `full` in every pass, classified like the other zone rows (`classify`
 * with TOL.zone, the same function the Lean classifier is checked against). `sameFull` says whether every pass found the
 * same full zones (the structure is a property of the two page heights, so it should).
 */
export function classifyAligned(pairs, tol = TOL.zone) {
  if (pairs.length < 2) throw new Error('need at least two passes');
  const key = (p) => p.zones.map((z) => (z.full ? 1 : 0)).join('');
  const sameFull = pairs.every((p) => key(p) === key(pairs[0]));
  const idx = pairs[0].zones.map((_, i) => i).filter((i) => pairs.every((p) => p.zones[i]?.full));
  const rows = [];
  for (const type of COUNT_TYPES) {
    for (const [arm, f] of [['A', (z) => z.countsA[type]], ['R', (z) => z.countsB[type]], ['A - R', (z) => z.delta[type]]]) {
      rows.push({ type, arm, ...classify(pairs.map((p) => idx.map((i) => f(p.zones[i]))), tol) });
    }
  }
  return { sameFull, fullZones: idx.map((i) => pairs[0].zones[i].y0), rows };
}

/** Markdown table of `classifyAligned` rows for the listed count types. */
export function classTable(res, types) {
  const lines = [`full zones (y0): ${res.fullZones.join(', ')}; same full zones in every pass: ${res.sameFull ? 'yes' : 'NO'}`, '', '| count type | arm | class | cells | differing | max spread |', '|---|---|---|---|---|---|'];
  for (const r of res.rows) if (types.includes(r.type)) lines.push(`| ${r.type} | ${r.arm} | **${r.cls}** | ${r.cells} | ${r.differingCells ?? '-'} | ${r.maxSpread ?? '-'} |`);
  return lines.join('\n');
}
