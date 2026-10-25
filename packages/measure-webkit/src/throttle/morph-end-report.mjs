import { excludeReason } from './finish-report.mjs';
import { ARM_ORDER, armRow, passCounts, verdicts, hasMorphReads, verdictOf, rates, dirTotal } from './morph-end.mjs';
import { cmp } from '../touchlock.mjs';

export function reasonOf(p) {
  return excludeReason(p) ?? (hasMorphReads(p.rec) ? null : 'record has no morph reads');
}

const usable = (passes) => passes.filter((p) => reasonOf(p) === null);
const rowOf = (passes) => armRow(usable(passes).map((p) => passCounts(p.rec)));
const dirCell = (x) => `${x.down} / ${x.up} / ${x.none}`;
const lateCell = (late) => (late.length ? late.map((n) => (n === null ? '-' : String(n))).join(' ') : '-');
const perOpen = (n, opens) => (opens ? (n / opens).toFixed(2) : '-');
const table = (head, rows) => [head, '|' + head.split('|').slice(1, -1).map(() => '---').join('|') + '|', ...rows].join('\n');

/** The brick verdict of one composition against the faithful passes of the jobs in which it has a usable pass (Lean Fw.Measure.MorphEndCount.verdictOf). */
export function brickRow(arm, passes) {
  const mine = usable(passes.filter((p) => p.arm === arm));
  const jobs = new Set(mine.map((p) => p.job));
  const base = usable(passes.filter((p) => p.arm === 'rewrite' && jobs.has(p.job)));
  const c = armRow(mine.map((p) => passCounts(p.rec)));
  const b = armRow(base.map((p) => passCounts(p.rec)));
  const still = verdicts(b, c).short === 'lifted';
  return {
    arm, n: c.usable, jobs: jobs.size, baseN: b.usable, c, b, still,
    rev: cmp(rates(b.revRates), rates(c.revRates)), fight: cmp(rates(b.fightRates), rates(c.fightRates)),
    verdict: c.usable && b.usable ? verdictOf(b.revRates, c.revRates, b.fightRates, c.fightRates, still) : 'no-data',
  };
}

export function reportMd(vms) {
  const all = vms.flatMap((v) => v.passes.map((p) => ({ ...p, job: v.vm })));
  const arms = ARM_ORDER.filter((a) => all.some((p) => p.arm === a));
  const head1 = '| job | arm | passes (usable) | finish-zone frames | median gap ms | closes (finger down / up / none) | re-opens (down / up / none) | open starts | open stretches counted | reversals while open | spring-back fights (writes against the finger: down / up / none) | pin turns (TouchLock fights) | displaced frames | pin turns per pass |';
  const head2 = '| job | arm | runs of 5-6 frames | runs of 1-9 frames per 1000 finish-zone frames | passes at the end | passes opened | open lateness (frames) | first-open reversals | touch moves | direction flips in a touch | Lean verdict band | verdict on 1-9 (exploratory) |';
  const t1 = [], t2 = [];
  const emit = (name, passes) => {
    const base = rowOf(passes.filter((p) => p.arm === 'rewrite'));
    for (const a of arms) {
      const mine = passes.filter((p) => p.arm === a);
      const r = rowOf(mine);
      const v = verdicts(base, r);
      t1.push(`| ${name} | ${a} | ${mine.length} (${r.usable}) | ${r.frames} | ${r.gap?.toFixed(1) ?? '-'} | ${dirCell(r.closes)} | ${dirCell(r.reopens)} | ${r.opens} | ${r.stretches} | ${r.reversals} | ${dirCell(r.springBack)} | ${r.fights} | ${r.displaced} | ${r.fightsPerPass.join(' ') || '-'} |`);
      t2.push(`| ${name} | ${a} | ${r.band} | ${r.shortPer1000 ?? '-'} | ${r.reached} | ${r.opened} | ${lateCell(r.late)} | ${r.firstOpenReversals} | ${r.moves} | ${r.wobble} | ${a === 'rewrite' ? 'base' : v.band} | ${a === 'rewrite' ? 'base' : v.short} |`);
    }
  };
  for (const { vm, passes } of vms) emit(vm, passes);
  emit('all jobs', all);
  const head3 = '| arm | usable passes | jobs | faithful passes in those jobs | reversals per open start | faithful reversals per open start | fights per open start (writes against the finger) | faithful fights per open start | reversals vs faithful | fights vs faithful | 1-9 runs lifted | verdict |';
  const t3 = arms.filter((a) => a !== 'rewrite').map((a) => {
    const k = brickRow(a, all);
    return `| ${a} | ${k.n} | ${k.jobs} | ${k.baseN} | ${perOpen(k.c.reversals, k.c.opens)} | ${perOpen(k.b.reversals, k.b.opens)} | ${perOpen(dirTotal(k.c.springBack), k.c.opens)} | ${perOpen(dirTotal(k.b.springBack), k.b.opens)} | ${k.rev} | ${k.fight} | ${k.still ? 'yes' : 'no'} | ${k.verdict} |`;
  });
  const out = [table(head1, t1), '', table(head2, t2), '',
    'Verdict per composition against the faithful passes of the same jobs (Lean `Fw.Measure.MorphEndCount.verdictOf`; lower or higher needs every brick pass beyond every faithful pass):', '', table(head3, t3)];
  const why = [...new Set(all.map(reasonOf).filter(Boolean))];
  if (why.length) out.push('', `Excluded passes: ${why.join('; ')}.`);
  return out.join('\n') + '\n';
}
