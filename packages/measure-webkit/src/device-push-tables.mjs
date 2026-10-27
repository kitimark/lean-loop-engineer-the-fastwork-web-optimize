// Markdown tables of the phone push summary (formatting only; the labels come from device-push.mjs `pushLabel`).
import { PUSH_METRICS } from './device-push.mjs';

const ms = (cs) => (cs / 100).toFixed(1);
const cell = (m, c) => (c === null ? '-' : m === 'over50' || /^[A-Z]/.test(m) ? `${c.median} [${c.min}-${c.max}]` : `${ms(c.median)} [${ms(c.min)}-${ms(c.max)}]`);

/** Per-arm table: median [min-max] over visits for each metric, n and the label. Times in ms. */
export function pushTables(sum) {
  const out = [];
  out.push('Cells: median [min-max] over the visits of the arm. p95, p99 and max are frame intervals in ms inside the push spans; over50 is frames over 50 ms;',
    'style, layout, paint and rAF are Timeline records between each push and its morph end (RecalculateStyles, Layout, Paint, FireAnimationFrame), summed over the 10 pushes of a visit.',
    'Label: the Lean rule `pushLabel` against the base (better, worse, same, unresolved); unresolved when either side has fewer than 3 visits.', '');
  out.push(`| arm | n | ${PUSH_METRICS.join(' | ')} | label |`, `|---|---|${PUSH_METRICS.map(() => '---').join('|')}|---|`);
  for (const a of sum.arms) out.push(`| ${a.id} | ${a.n} | ${PUSH_METRICS.map((m) => cell(m, a.metrics[m])).join(' | ')} | ${a.label} |`);
  out.push('', '### Visits', '', `| visit | arm | seconds | pushes | nav | max morph (per mille) | ${PUSH_METRICS.join(' | ')} |`, `|---|---|---|---|---|---|${PUSH_METRICS.map(() => '---').join('|')}|`);
  for (const r of sum.visits) out.push(`| ${r.index} | ${r.arm} | ${r.durationS} | ${r.pushes} | ${r.nav ? 'yes' : 'no'} | ${r.maxMorph} | ${r.vals.map((x, i) => (i < 3 ? ms(x) : x)).join(' | ')} |`);
  if (sum.notRun.length) { out.push('', '### Not run', ''); for (const n of sum.notRun) out.push(`- visit ${n.index} (${n.arm}): ${n.status}, ${n.attempts} attempts, faults ${n.faults.join(', ') || 'none'}`); }
  return out.join('\n') + '\n';
}
