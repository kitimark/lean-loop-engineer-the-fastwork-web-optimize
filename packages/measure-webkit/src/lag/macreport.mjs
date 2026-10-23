// Tables of the Playwright WebKit morph runs (macmorph.mjs): per arm x drive x phase, the mean per-frame record counts over the runs the phase rule
// (phase.mjs) accepts, the trusted-vs-synthetic and original-vs-rewrite verdicts (reduce.mjs `verdict`, Fw.Measure.WebKitLag), and the run-to-run class of
// each count (reduce.mjs `classify`, the policy of Fw/Measure/Classes). Computation only; no I/O.
import { COUNT_TYPES, TOL, classify as classOf } from '../reduce.mjs';
import { frac, verdict } from './reduce.mjs';
import { classify as phaseClass, rangesOf } from './phase.mjs';

export const METRICS = Object.freeze(['Layout', 'RecalculateStyles', 'Paint', 'Composite', 'RenderingFrame', 'FireAnimationFrame', 'paintArea']);
export const PHASES = Object.freeze(['idle', 'open', 'close']);

const col = (name) => COUNT_TYPES.indexOf(name);

/** The phase ranges of a recorded run under the Lean rule, or null when it is refused. */
export function rangesOfRun(r) {
  if (!r.marks || !r.perStep) return null;
  const c = phaseClass(r.marks, r.down, r.up);
  return c.outcome === 'ok' ? rangesOf(c) : null;
}

/** Sum of every metric over the frames [a, b) of a run. */
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

/** Per-run values of every arm x drive x phase: frames, sums, per-frame fractions. */
export function cellRuns(files) {
  const cells = new Map();
  const refused = new Map();
  files.forEach((f, job) => {
    for (const r of f.runs) {
      const key = `${r.arm}|${r.drive}`;
      const rg = rangesOfRun(r);
      if (!rg) { refused.set(key, [...(refused.get(key) ?? []), { job, rep: r.rep, outcome: r.outcome === 'ok' ? 'rule' : r.outcome }]); continue; }
      for (const ph of PHASES) {
        const frames = rg[ph][1] - rg[ph][0];
        const sums = phaseSums(r, rg[ph]);
        const k = `${key}|${ph}`;
        const row = { job, rep: r.rep, frames, sums, perFrame: Object.fromEntries(METRICS.map((m) => [m, frac(sums[m], frames)])) };
        cells.set(k, [...(cells.get(k) ?? []), row]);
      }
    }
  });
  return { cells, refused };
}

/** What the pushes did: the events seen by the page and the largest `--morph` at the boundaries, per arm x drive. */
export function pushFacts(files) {
  const out = new Map();
  for (const f of files) {
    for (const r of f.runs) {
      if (!r.fin) continue;
      const key = `${r.arm}|${r.drive}`;
      const o = out.get(key) ?? { runs: 0, events: 0, trusted: 0, prevented: 0, cancelable: 0, morphMax: 0, scrollMoved: 0 };
      o.runs++;
      for (const e of r.fin.events) { o.events++; o.trusted += e.trusted ? 1 : 0; o.prevented += e.prevented ? 1 : 0; o.cancelable += e.cancelable ? 1 : 0; }
      o.morphMax = Math.max(o.morphMax, ...r.fin.at.map((a) => (typeof a.morph === 'number' ? a.morph : 0)));
      if (r.info && Math.abs(r.fin.y - r.info.maxY) > 2) o.scrollMoved++;
      out.set(key, o);
    }
  }
  return out;
}

export function analyze(files) {
  const { cells, refused } = cellRuns(files);
  const get = (arm, drive, ph) => cells.get(`${arm}|${drive}|${ph}`) ?? [];
  const stat = {}, drive = {}, arm = {}, cls = {};
  for (const a of ['orig', 'rewrite']) {
    for (const d of ['trusted', 'synthetic']) {
      for (const ph of PHASES) {
        const rows = get(a, d, ph);
        const k = `${a}|${d}|${ph}`;
        stat[k] = { n: rows.length, frames: mean(rows.map((r) => r.frames)), mean: Object.fromEntries(METRICS.map((m) => [m, mean(rows.map((r) => num(r.perFrame[m])))])) };
        cls[k] = rows.length >= 2 ? Object.fromEntries(METRICS.map((m) => [m, classOf(rows.map((r) => [r.sums[m]]), m === 'paintArea' ? TOL.paint : TOL.total).cls])) : null;
      }
    }
  }
  for (const a of ['orig', 'rewrite']) for (const ph of PHASES) {
    drive[`${a}|${ph}`] = Object.fromEntries(METRICS.map((m) => [m, verdict(get(a, 'synthetic', ph).map((r) => r.perFrame[m]), get(a, 'trusted', ph).map((r) => r.perFrame[m]))]));
  }
  for (const d of ['trusted', 'synthetic']) for (const ph of PHASES) {
    arm[`${d}|${ph}`] = Object.fromEntries(METRICS.map((m) => [m, verdict(get('orig', d, ph).map((r) => r.perFrame[m]), get('rewrite', d, ph).map((r) => r.perFrame[m]))]));
  }
  return { jobs: files.length, stat, drive, arm, cls, refused: Object.fromEntries(refused), facts: Object.fromEntries(pushFacts(files)) };
}

const f2 = (x) => (x === null ? 'n/a' : Number.isInteger(x) ? String(x) : x.toFixed(2));
const WORDS = { lower: 'trusted lower', higher: 'trusted higher', overlap: 'overlap' };
const ARM_WORDS = { lower: 'rewrite lower', higher: 'rewrite higher', overlap: 'overlap' };

export function macMd(a) {
  const L = [];
  L.push(`Playwright WebKit, ${a.jobs} job(s). Per-frame record counts averaged over the runs the phase rule accepts (n). Verdicts are stated only when the per-run ranges are separated.`, '');
  L.push('### Pushes seen by the page', '', '| arm | drive | runs | wheel events | isTrusted | cancelable | defaultPrevented | max --morph | scroll moved |', '|---|---|---|---|---|---|---|---|---|');
  for (const [k, o] of Object.entries(a.facts)) L.push(`| ${k.replace('|', ' | ')} | ${o.runs} | ${o.events} | ${o.trusted} | ${o.cancelable} | ${o.prevented} | ${f2(o.morphMax)} | ${o.scrollMoved} |`);
  if (Object.keys(a.refused).length) {
    L.push('', '### Runs the phase rule or the capture refused', '', '| arm | drive | refused | reasons |', '|---|---|---|---|');
    for (const [k, rows] of Object.entries(a.refused)) L.push(`| ${k.replace('|', ' | ')} | ${rows.length} | ${[...new Set(rows.map((r) => r.outcome))].join(', ')} |`);
  }
  for (const ph of PHASES) {
    L.push('', `### ${ph} phase, mean per frame`, '', `| arm | drive | n | frames | ${METRICS.join(' | ')} |`, `|---|---|---|---|${METRICS.map(() => '---').join('|')}|`);
    for (const arm of ['orig', 'rewrite']) for (const d of ['trusted', 'synthetic']) {
      const s = a.stat[`${arm}|${d}|${ph}`];
      L.push(`| ${arm} | ${d} | ${s.n} | ${f2(s.frames)} | ${METRICS.map((m) => f2(s.mean[m])).join(' | ')} |`);
    }
    L.push('', `| ${ph}: verdict | ${METRICS.join(' | ')} |`, `|---|${METRICS.map(() => '---').join('|')}|`);
    for (const arm of ['orig', 'rewrite']) L.push(`| ${arm}: synthetic vs trusted | ${METRICS.map((m) => WORDS[a.drive[`${arm}|${ph}`][m]]).join(' | ')} |`);
    for (const d of ['trusted', 'synthetic']) L.push(`| ${d}: original vs rewrite | ${METRICS.map((m) => ARM_WORDS[a.arm[`${d}|${ph}`][m]]).join(' | ')} |`);
    L.push('', `| ${ph}: class of the phase totals over runs | ${METRICS.join(' | ')} |`, `|---|${METRICS.map(() => '---').join('|')}|`);
    for (const arm of ['orig', 'rewrite']) for (const d of ['trusted', 'synthetic']) {
      const c = a.cls[`${arm}|${d}|${ph}`];
      L.push(`| ${arm} ${d} | ${METRICS.map((m) => c?.[m] ?? 'n/a').join(' | ')} |`);
    }
  }
  return `${L.join('\n')}\n`;
}
