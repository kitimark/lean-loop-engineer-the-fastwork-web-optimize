import { excludeReason } from './finish-report.mjs';
import { ARM_ORDER, armRow, passCounts, verdicts, hasMorphReads } from './morph-end.mjs';

export function reasonOf(p) {
  return excludeReason(p) ?? (hasMorphReads(p.rec) ? null : 'record has no morph reads');
}

const rowOf = (passes) => armRow(passes.filter((p) => reasonOf(p) === null).map((p) => passCounts(p.rec)));
const dirCell = (x) => `${x.down} / ${x.up} / ${x.none}`;
const lateCell = (late) => (late.length ? late.map((n) => (n === null ? '-' : String(n))).join(' ') : '-');

export function reportMd(vms) {
  const arms = ARM_ORDER.filter((a) => vms.some((v) => v.passes.some((p) => p.arm === a)));
  const head1 = '| job | arm | passes (usable) | frames | median gap ms | closes (finger down / up / none) | re-opens (down / up / none) | open starts | open stretches counted | reversals while open | spring-back fights | displaced frames | fights per pass |';
  const head2 = '| job | arm | runs of 5-6 frames | runs of 1-9 per 1000 frames | passes at the end | passes opened | open lateness (frames) | first-open reversals | touch moves | direction flips in a touch | Lean verdict band | verdict on 1-9 (exploratory) |';
  const t1 = [head1, '|' + head1.split('|').slice(1, -1).map(() => '---').join('|') + '|'];
  const t2 = [head2, '|' + head2.split('|').slice(1, -1).map(() => '---').join('|') + '|'];
  const all = vms.flatMap((v) => v.passes);
  const emit = (name, passes) => {
    const base = rowOf(passes.filter((p) => p.arm === 'rewrite'));
    for (const a of arms) {
      const mine = passes.filter((p) => p.arm === a);
      const r = rowOf(mine);
      const v = verdicts(base, r);
      t1.push(`| ${name} | ${a} | ${mine.length} (${r.usable}) | ${r.frames} | ${r.gap?.toFixed(1) ?? '-'} | ${dirCell(r.closes)} | ${dirCell(r.reopens)} | ${r.opens} | ${r.stretches} | ${r.reversals} | ${r.fights} | ${r.displaced} | ${r.fightsPerPass.join(' ') || '-'} |`);
      t2.push(`| ${name} | ${a} | ${r.band} | ${r.shortPer1000 ?? '-'} | ${r.reached} | ${r.opened} | ${lateCell(r.late)} | ${r.firstOpenReversals} | ${r.moves} | ${r.wobble} | ${a === 'rewrite' ? 'base' : v.band} | ${a === 'rewrite' ? 'base' : v.short} |`);
    }
  };
  for (const { vm, passes } of vms) emit(vm, passes);
  emit('all jobs', all);
  const out = [t1.join('\n'), '', t2.join('\n')];
  const why = [...new Set(all.map(reasonOf).filter(Boolean))];
  if (why.length) out.push('', `Excluded passes: ${why.join('; ')}.`);
  return out.join('\n') + '\n';
}
