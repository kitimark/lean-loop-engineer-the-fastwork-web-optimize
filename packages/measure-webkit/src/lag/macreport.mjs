import { COUNT_TYPES, TOL, classify as classOf } from '../reduce.mjs';
import { frac, jobVerdicts, tally } from './reduce.mjs';
import { classify as phaseClass, rangesOf, acceptScrollIn, morphMilli } from './phase.mjs';

export const METRICS = Object.freeze(['Layout', 'RecalculateStyles', 'Paint', 'Composite', 'RenderingFrame', 'FireAnimationFrame', 'paintArea']);
export const PHASES = Object.freeze(['idle', 'open', 'close']);
export const ARMS = Object.freeze(['orig', 'rewrite']);
export const DRIVES = Object.freeze(['trusted', 'synthetic', 'scrollin']);
export const BASE_DRIVE = 'synthetic';

const col = (name) => COUNT_TYPES.indexOf(name);

export function judge(r) {
  if (!r.marks || !r.perStep) return { outcome: r.outcome ?? 'marksMissing', ranges: null };
  const c = phaseClass(r.marks, r.down, r.up);
  const o = r.drive === 'scrollin' ? acceptScrollIn(c, r.startY, r.pushY, morphMilli(r.fin?.at ?? [])) : c;
  return { outcome: o.outcome, ranges: o.outcome === 'ok' ? rangesOf(o) : null };
}

export const rangesOfRun = (r) => judge(r).ranges;

export function phaseSums(r, [a, b]) {
  const out = {};
  for (const m of METRICS) {
    if (m === 'paintArea') out[m] = Math.round(r.paintArea.slice(a, b).reduce((s, x) => s + x, 0));
    else out[m] = r.perStep.slice(a, b).reduce((s, row) => s + row[col(m)], 0);
  }
  return out;
}

const mean = (xs) => (xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : null);
const num = ([n, d]) => n / d;

export function jobCells(file) {
  const cells = new Map();
  const refused = new Map();
  for (const r of file.runs) {
    const key = `${r.arm}|${r.drive}`;
    const { outcome, ranges } = judge(r);
    if (!ranges) { refused.set(key, [...(refused.get(key) ?? []), { rep: r.rep, outcome }]); continue; }
    for (const ph of PHASES) {
      const frames = ranges[ph][1] - ranges[ph][0];
      const sums = phaseSums(r, ranges[ph]);
      const k = `${key}|${ph}`;
      const row = { rep: r.rep, frames, sums, perFrame: Object.fromEntries(METRICS.map((m) => [m, frac(sums[m], frames)])) };
      cells.set(k, [...(cells.get(k) ?? []), row]);
    }
  }
  return { cells, refused };
}

export function pushFacts(file) {
  const out = new Map();
  for (const r of file.runs) {
    if (!r.fin) continue;
    const key = `${r.arm}|${r.drive}`;
    const o = out.get(key) ?? { runs: 0, events: 0, trusted: 0, prevented: 0, cancelable: 0, morphMax: 0, scrolledIn: 0, wheels: 0 };
    o.runs++;
    for (const e of r.fin.events) { o.events++; o.trusted += e.trusted ? 1 : 0; o.prevented += e.prevented ? 1 : 0; o.cancelable += e.cancelable ? 1 : 0; }
    o.morphMax = Math.max(o.morphMax, morphMilli(r.fin.at) / 1000);
    if (typeof r.pushY === 'number' && r.pushY > r.startY) o.scrolledIn++;
    o.wheels += r.wheels ?? 0;
    out.set(key, o);
  }
  return out;
}

export function analyze(files) {
  const per = files.map(jobCells);
  const get = (j, arm, drive, ph) => per[j].cells.get(`${arm}|${drive}|${ph}`) ?? [];
  const jobs = files.map((_, j) => j);
  const stat = {}, drive = {}, arm = {}, cls = {};
  for (const a of ARMS) for (const d of DRIVES) for (const ph of PHASES) {
    const k = `${a}|${d}|${ph}`;
    stat[k] = jobs.map((j) => { const rows = get(j, a, d, ph); return { n: rows.length, frames: mean(rows.map((r) => r.frames)), mean: Object.fromEntries(METRICS.map((m) => [m, mean(rows.map((r) => num(r.perFrame[m])))])) }; });
    cls[k] = jobs.map((j) => { const rows = get(j, a, d, ph); return rows.length >= 2 ? Object.fromEntries(METRICS.map((m) => [m, classOf(rows.map((r) => [r.sums[m]]), m === 'paintArea' ? TOL.paint : TOL.total).cls])) : null; });
  }
  const decide = (pairsOf) => Object.fromEntries(METRICS.map((m) => {
    const verdicts = jobVerdicts(jobs.map((j) => { const [x, y] = pairsOf(j); return { a: x.map((r) => r.perFrame[m]), b: y.map((r) => r.perFrame[m]) }; }));
    return [m, { verdicts, tally: tally(verdicts) }];
  }));
  for (const a of ARMS) for (const d of DRIVES) if (d !== BASE_DRIVE) for (const ph of PHASES) drive[`${a}|${d}|${ph}`] = decide((j) => [get(j, a, BASE_DRIVE, ph), get(j, a, d, ph)]);
  for (const d of DRIVES) for (const ph of PHASES) arm[`${d}|${ph}`] = decide((j) => [get(j, 'orig', d, ph), get(j, 'rewrite', d, ph)]);
  return {
    jobs: files.length, stat, drive, arm, cls,
    refused: per.map((p) => Object.fromEntries(p.refused)), facts: files.map((f) => Object.fromEntries(pushFacts(f))),
  };
}

const f2 = (x) => (x === null ? 'n/a' : Number.isInteger(x) ? String(x) : x.toFixed(2));
const WORDS = { lower: 'lower', higher: 'higher', overlap: 'overlap' };
const perJob = (vs) => vs.map((v) => WORDS[v]).join(' / ');

export function macMd(a) {
  const L = [];
  const J = Array.from({ length: a.jobs }, (_, j) => j);
  L.push(`Playwright WebKit, ${a.jobs} job(s). Per-frame record counts averaged over the runs the phase rule accepts (n). Every verdict is decided inside one job from that job's own runs and is stated only when its per-run ranges are separated; the jobs are listed in order and never pooled. Drive verdicts compare the drive against synthetic (lower: the drive is below synthetic); arm verdicts compare rewrite against original (lower: rewrite is below original).`, '');
  L.push('### Pushes seen by the page', '', '| job | arm | drive | runs | wheel events | isTrusted | cancelable | defaultPrevented | max --morph | scrolled before the push | scroll wheels |', '|---|---|---|---|---|---|---|---|---|---|---|');
  for (const j of J) for (const [k, o] of Object.entries(a.facts[j])) L.push(`| ${j + 1} | ${k.replace('|', ' | ')} | ${o.runs} | ${o.events} | ${o.trusted} | ${o.cancelable} | ${o.prevented} | ${f2(o.morphMax)} | ${o.scrolledIn} | ${o.wheels} |`);
  if (a.refused.some((r) => Object.keys(r).length)) {
    L.push('', '### Runs the phase rule or the capture refused', '', '| job | arm | drive | refused | reasons |', '|---|---|---|---|---|');
    for (const j of J) for (const [k, rows] of Object.entries(a.refused[j])) L.push(`| ${j + 1} | ${k.replace('|', ' | ')} | ${rows.length} | ${[...new Set(rows.map((r) => r.outcome))].join(', ')} |`);
  }
  for (const ph of PHASES) {
    L.push('', `### ${ph} phase, mean per frame`, '', `| job | arm | drive | n | frames | ${METRICS.join(' | ')} |`, `|---|---|---|---|---|${METRICS.map(() => '---').join('|')}|`);
    for (const j of J) for (const arm of ARMS) for (const d of DRIVES) {
      const s = a.stat[`${arm}|${d}|${ph}`][j];
      L.push(`| ${j + 1} | ${arm} | ${d} | ${s.n} | ${f2(s.frames)} | ${METRICS.map((m) => f2(s.mean[m])).join(' | ')} |`);
    }
    L.push('', `| ${ph}: verdict per job | ${METRICS.join(' | ')} |`, `|---|${METRICS.map(() => '---').join('|')}|`);
    for (const arm of ARMS) for (const d of DRIVES) if (d !== BASE_DRIVE) L.push(`| ${arm}: ${d} vs ${BASE_DRIVE} | ${METRICS.map((m) => perJob(a.drive[`${arm}|${d}|${ph}`][m].verdicts)).join(' | ')} |`);
    for (const d of DRIVES) L.push(`| ${d}: original vs rewrite | ${METRICS.map((m) => perJob(a.arm[`${d}|${ph}`][m].verdicts)).join(' | ')} |`);
    L.push('', `| ${ph}: class of the phase totals over runs, per job | ${METRICS.join(' | ')} |`, `|---|${METRICS.map(() => '---').join('|')}|`);
    for (const arm of ARMS) for (const d of DRIVES) for (const j of J) {
      const c = a.cls[`${arm}|${d}|${ph}`][j];
      L.push(`| ${arm} ${d} job ${j + 1} | ${METRICS.map((m) => c?.[m] ?? 'n/a').join(' | ')} |`);
    }
  }
  return `${L.join('\n')}\n`;
}
