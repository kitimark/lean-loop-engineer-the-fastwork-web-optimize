import { PUSH_METRICS } from './device-push.mjs';

const ms = (cs) => (cs / 100).toFixed(1);
const cell = (m, c) => (c === null ? '-' : m === 'over50' || /^[A-Z]/.test(m) ? `${c.median} [${c.min}-${c.max}]` : `${ms(c.median)} [${ms(c.min)}-${ms(c.max)}]`);

export function pushTables(sum) {
  const out = [];
  out.push('Cells: median [min-max] over the visits of the arm. p95, p99 and max are frame intervals in ms inside the push spans; over50 is frames over 50 ms;',
    'style, layout, paint and rAF are Timeline records between each push and its morph end (RecalculateStyles, Layout, Paint, FireAnimationFrame), summed over the 10 pushes of a visit.',
    'Label: the Lean rule `pushLabel` against the base (better, worse, same, unresolved); unresolved when either side has fewer than 3 visits.', '');
  out.push(`| arm | n | ${PUSH_METRICS.join(' | ')} | label |`, `|---|---|${PUSH_METRICS.map(() => '---').join('|')}|---|`);
  for (const a of sum.arms) out.push(`| ${a.id} | ${a.n} | ${PUSH_METRICS.map((m) => cell(m, a.metrics[m])).join(' | ')} | ${a.label} |`);
  out.push('', '### Lean cell verdicts against the base', '', `| arm | ${PUSH_METRICS.join(' | ')} |`, `|---|${PUSH_METRICS.map(() => '---').join('|')}|`);
  for (const a of sum.arms) if (a.cells) out.push(`| ${a.id} | ${PUSH_METRICS.map((m) => a.cells[m] ?? '-').join(' | ')} |`);
  if (sum.contrasts) {
    out.push('', '### Pair contrasts (arm with the pictures hidden against its reference; beats = hiding lowers the value)', '',
      `| reference | arm | n | label | ${PUSH_METRICS.join(' | ')} |`, `|---|---|---|---|${PUSH_METRICS.map(() => '---').join('|')}|`);
    for (const c of sum.contrasts) {
      out.push(`| ${c.ref} | ${c.arm} | ${c.nRef}/${c.nArm} | ${c.label} | ${PUSH_METRICS.map((m) => (c.cells ? `${c.cells[m]} (${c.causes[m]})` : '-')).join(' | ')} |`);
      if (c.refSpread) out.push(`| ${c.ref} spread | | | | ${PUSH_METRICS.map((m) => (/^[A-Z]/.test(m) || m === 'over50' ? c.refSpread[m] : ms(c.refSpread[m]))).join(' | ')} |`);
    }
  }
  if (sum.takeShare) {
    out.push('', '### Take share (driver trace window.__fwTakeTrace; base arms have no trace)', '',
      '| arm | visits | frames lane: driver pushes | taken | touches | touches with a take | counts lane: driver pushes | taken | touches | touches with a take |', '|---|---|---|---|---|---|---|---|---|---|');
    for (const t of sum.takeShare) out.push(`| ${t.id} | ${t.visits} | ${t.frames.pushes} | ${t.frames.taken} | ${t.frames.touches} | ${t.frames.touchTaken} | ${t.counts.pushes} | ${t.counts.taken} | ${t.counts.touches} | ${t.counts.touchTaken} |`);
  }
  if (sum.positions) {
    for (const [key, name] of [['byPosition', 'position in the round'], ['byRound', 'round']]) {
      out.push('', `### Median over the arms by ${name}`, '', `| ${key === 'byPosition' ? 'position' : 'round'} | n | ${PUSH_METRICS.join(' | ')} |`, `|---|---|${PUSH_METRICS.map(() => '---').join('|')}|`);
      for (const g of sum.positions[key]) out.push(`| ${g.position ?? g.round} | ${g.n} | ${PUSH_METRICS.map((m) => (g.metrics[m] ? cell(m, { median: g.metrics[m].median, min: Math.min(...g.metrics[m].values), max: Math.max(...g.metrics[m].values) }) : '-')).join(' | ')} |`);
    }
  }
  out.push('', '### Visits', '', `| visit | arm | round | position | seconds | pushes | nav | max morph (per mille) | ${PUSH_METRICS.join(' | ')} |`, `|---|---|---|---|---|---|---|---|${PUSH_METRICS.map(() => '---').join('|')}|`);
  for (const r of sum.visits) out.push(`| ${r.index} | ${r.arm} | ${r.round ?? '-'} | ${r.position ?? '-'} | ${r.durationS} | ${r.pushes} | ${r.nav ? 'yes' : 'no'} | ${r.maxMorph} | ${r.vals.map((x, i) => (i < 3 ? ms(x) : x)).join(' | ')} |`);
  if (sum.notRun.length) { out.push('', '### Not run', ''); for (const n of sum.notRun) out.push(`- visit ${n.index} (${n.arm}): ${n.status}, ${n.attempts} attempts, faults ${n.faults.join(', ') || 'none'}`); }
  return out.join('\n') + '\n';
}
