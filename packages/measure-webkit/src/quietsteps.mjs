// TS stand-in of Fw.Measure.Quiet (lean/Fw/Measure/Quiet.lean): the quiet-step rule. Checked against the Lean goldens
// (packages/contracts/golden/measure/measure.quietSteps.jsonl, test/fwcore.test.mjs). Glue only: no decision of its own.
import { classify } from './reduce.mjs';

const shortest = (durs) => (durs.length ? Math.min(...durs.map((d) => d.length)) : 0);

/** Steps k < n (n = the shortest pass) whose duration is <= limit in every pass. Durations are whole ms. */
export function quietSteps(limit, durs) {
  const kept = [];
  for (let k = 0; k < shortest(durs); k++) if (durs.every((d) => d[k] <= limit)) kept.push(k);
  return kept;
}

/** The `measure.quietSteps` reply: kept steps, and per type the class over the kept steps when there are at least minKept. */
export function quietReply({ limit, minKept, tol, durs, series }) {
  const kept = quietSteps(limit, durs);
  const enough = kept.length >= minKept;
  const out = { kept, keptCount: kept.length, total: shortest(durs), enough };
  if (series && enough) out.classes = Object.fromEntries(series.map((s) => [s.type, classify(s.runs.map((r) => kept.map((k) => r[k] ?? 0)), tol).cls]));
  return out;
}

/** Whole-ms step durations (rounded, as the rule takes naturals). */
export const wholeMs = (ds) => ds.map((x) => Math.round(x));
