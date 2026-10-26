// The toolbar lane table (task toolbar-sim-lane). Every number is a sum or a quotient of counts; the verdict per flag is
// toolbar.mjs `flagVerdict` (twin of Lean Fw.Measure.MorphEndCount.flagVerdict). A pass is {arm, round, vm, rec, drag, cost, job} as toolbar-probe.mjs returns it.
import { ARM_ORDER, FLAG_ARMS, FLAG_OF, LOOK_CHANGE, reasonOf, passOf, facts, columns, flagVerdict, enters, stepsLifted, medianCs, hzOf, foldOf } from './toolbar.mjs';

const table = (head, rows) => [head, '|' + head.split('|').slice(1, -1).map(() => '---').join('|') + '|', ...rows].join('\n');
const sum = (l) => l.reduce((a, b) => a + b, 0);
const per = (num, den, digits = 2) => (den > 0 ? (num / den).toFixed(digits) : '-');
const median = (l) => (l.length ? [...l].sort((a, b) => a - b)[Math.floor(l.length / 2)] : null);
const px = (tenth) => (tenth / 10).toFixed(1);

export const usable = (passes) => passes.filter((p) => reasonOf(p) === null);

function rowFacts(passes) {
  const us = usable(passes);
  const recs = us.map(passOf);
  const fs = us.map(facts);
  const gaps = recs.flatMap((r) => r.gaps);
  const hz = us.map((p) => hzOf(p.rec.hz ?? [])).filter((x) => x > 0);
  return { us, recs, fs, gaps, hz, moved: fs.filter((f) => f.vhMax - f.vhMin >= 20).length };
}

/** The pooled counts of the usable passes of an arm. */
export function armRow(passes) {
  const { us, recs, fs, gaps, hz, moved } = rowFacts(passes);
  const timed = recs.filter((r) => r.frames > 0);
  return {
    total: passes.length, usable: us.length, moved,
    gestures: sum(recs.map((r) => r.gestures)), reversals: sum(recs.map((r) => r.reversals)),
    closes: sum(fs.map((f) => f.closes)), reopens: sum(fs.map((f) => f.reopens)), swaps: sum(recs.map((r) => r.swaps)),
    onsets: sum(recs.map((r) => r.onsets)), onsetGestures: sum(recs.map((r) => r.onsetGestures)),
    steps: sum(fs.map((f) => f.steps)), gaps: gaps.length, medianGapCs: gaps.length ? medianCs(gaps) : null, frameCs: medianCs(recs.map((r) => r.frameCs)), lifted: stepsLifted(medianCs(recs.map((r) => r.frameCs)), gaps),
    vhMin: fs.length ? Math.min(...fs.map((f) => f.vhMin)) : null, vhMax: fs.length ? Math.max(...fs.map((f) => f.vhMax)) : null,
    peaks: recs.map((r) => r.peak), unsettled: recs.filter((r) => !r.settled).length,
    overran: us.filter((p) => p.cost && p.cost.counts === false && p.cost.rows > 0).length, timed: timed.length, frames: sum(timed.map((r) => r.frames)), layout: sum(timed.map((r) => r.layout)), recalc: sum(timed.map((r) => r.recalc)),
    hz: median(hz), recs,
  };
}

/** The verdict row of one flag arm against the default passes of the jobs it ran in. */
export function flagRow(arm, passes) {
  const mine = usable(passes.filter((p) => p.arm === arm));
  const jobs = new Set(mine.map((p) => p.job));
  const base = usable(passes.filter((p) => p.arm === 'default' && jobs.has(p.job)));
  const b = base.map(passOf), c = mine.map(passOf);
  const cols = columns(b, c);
  const verdict = c.length && b.length ? flagVerdict(b, c) : 'no-data';
  return { arm, n: c.length, baseN: b.length, jobs: jobs.size, cols, verdict, enters: enters(LOOK_CHANGE.has(arm), verdict) };
}

export function reportMd(vms) {
  const all = vms.flatMap((v) => v.passes.map((p) => ({ ...p, job: v.vm })));
  const arms = ARM_ORDER.filter((a) => all.some((p) => p.arm === a));
  const rows = Object.fromEntries(arms.map((a) => [a, armRow(all.filter((p) => p.arm === a))]));
  const h1 = '| arm | passes (usable) | passes with a toolbar move | vh steps | steps per pass | median step gap ms | median frame gap ms | step cadence | vh range px |';
  const t1 = arms.map((a) => {
    const r = rows[a];
    return `| ${a} | ${r.total} (${r.usable}) | ${r.moved} | ${r.steps} | ${per(r.steps, r.usable, 1)} | ${r.medianGapCs === null ? '-' : (r.medianGapCs / 100).toFixed(1)} | ${r.frameCs ? (r.frameCs / 100).toFixed(1) : '-'} | ${r.gaps === 0 ? '-' : r.lifted ? 'per frame' : 'throttled'} | ${r.vhMin === null ? '-' : `${px(r.vhMin)} to ${px(r.vhMax)}`} |`;
  });
  const h2 = '| arm | gestures | reversals per gesture | closes per gesture | re-opens per gesture | fade onsets per gesture | gestures with an onset | lowest peak (of 1000) | passes open at the end |';
  const t2 = arms.map((a) => {
    const r = rows[a];
    return `| ${a} | ${r.gestures} | ${per(r.reversals, r.gestures)} | ${per(r.closes, r.gestures)} | ${per(r.reopens, r.gestures)} | ${per(r.onsets, r.gestures)} | ${r.onsetGestures} / ${r.gestures} | ${r.peaks.length ? Math.min(...r.peaks) : '-'} | ${r.unsettled} |`;
  });
  const h3 = '| arm | passes with a whole gesture-4 window | windows without both gesture stamps (left out) | frames in the windows | Layout per frame | RecalcStyle per frame | Simulator refresh Hz (median of passes) | unthrottle cost model (fold of the throttle) |';
  const t3 = arms.map((a) => {
    const r = rows[a];
    return `| ${a} | ${r.timed} | ${r.overran} | ${r.frames} | ${per(r.layout, r.frames, 3)} | ${per(r.recalc, r.frames, 3)} | ${r.hz ?? '-'} | ${r.hz ? `${foldOf(r.hz)}x` : '-'} |`;
  });
  const h4 = '| flag | class | usable passes | default passes beside them | jobs | reversals | re-opens | onsets | Layout | RecalcStyle | step cadence lifted | same look | verdict | enters a preset |';
  const t4 = FLAG_ARMS.filter((a) => arms.includes(a)).map((a) => {
    const k = flagRow(a, all);
    return `| ${FLAG_OF[a]} | ${LOOK_CHANGE.has(a) ? 'look-change (L)' : 'plain'} | ${k.n} | ${k.baseN} | ${k.jobs} | ${k.cols.reversals} | ${k.cols.swaps} | ${k.cols.onsets} | ${k.cols.layout} | ${k.cols.recalc} | ${k.cols.lifted ? 'yes' : 'no'} | ${k.cols.look ? 'yes' : 'no'} | ${k.verdict} | ${k.enters ? 'yes' : 'no'} |`;
  });
  const out = [table(h1, t1), '', table(h2, t2), '', table(h3, t3), '',
    'Verdict per flag against the default passes of the same jobs (Lean `Fw.Measure.MorphEndCount.flagVerdict`; lower or higher needs every flag pass beyond every default pass, rates per gesture and per frame):', '', table(h4, t4)];
  const why = [...new Set(all.map(reasonOf).filter(Boolean))];
  if (why.length) out.push('', `Excluded passes: ${why.join('; ')}.`);
  const lost = vms.filter((v) => v.passes.length === 0).map((v) => v.vm);
  if (lost.length) out.push('', `Jobs with no pass: ${lost.join(', ')}.`);
  return out.join('\n') + '\n';
}
