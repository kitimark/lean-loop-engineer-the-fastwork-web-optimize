import { COUNT_TYPES, TOL, classify as classOf } from '../reduce.mjs';
import { frac, jobVerdicts, tally } from './reduce.mjs';
import { classify as phaseClass, rangesOf, acceptScrollIn, morphMilli } from './phase.mjs';

export const METRICS = Object.freeze(['Layout', 'RecalculateStyles', 'Paint', 'Composite', 'RenderingFrame', 'FireAnimationFrame', 'paintArea']);
export const PHASES = Object.freeze(['idle', 'open', 'close']);
export const ARMS = Object.freeze(['orig', 'rewrite']);
export const DRIVES = Object.freeze(['trusted', 'synthetic', 'scrollin', 'momentum']);
export const BASE_DRIVE = 'synthetic';

export const FLIGHT_HOLD = 2;
export const MIN_WHEELS = 2;

export const inFlight = (scrolls, k) => scrolls.some((s) => s <= k && k <= s + FLIGHT_HOLD);

export function flightFrames(scrolls, p, n) {
  let c = 0;
  for (let i = 0; i < n; i++) if (inFlight(scrolls, p + i)) c++;
  return c;
}

export function splitPush(events) {
  const at = events.findIndex((e) => e.m);
  const before = at < 0 ? events : events.slice(0, at);
  return { scrolls: before.map((e) => e.f), push: at < 0 ? null : events[at].f };
}

export function acceptMomentum(o, startY, pushY, morph, scrolls, push) {
  const a = acceptScrollIn(o, startY, pushY, morph);
  if (a.outcome !== 'ok') return a;
  if (push === null || push === undefined) return { outcome: 'noPush' };
  if (scrolls.length < MIN_WHEELS) return { outcome: 'fewWheels' };
  if (!inFlight(scrolls, push)) return { outcome: 'settled' };
  return a;
}

export const jobLabel = (idx, pos, n) => (typeof idx === 'number' ? `job ${idx}` : n <= 1 ? 'this job' : `job ${pos + 1}`);

const col = (name) => COUNT_TYPES.indexOf(name);

export function judge(r) {
  if (!r.marks || !r.perStep) return { outcome: r.outcome ?? 'marksMissing', ranges: null };
  const c = phaseClass(r.marks, r.down, r.up);
  const at = r.fin?.at ?? [];
  const sp = splitPush(r.fin?.events ?? []);
  const o = r.drive === 'scrollin' ? acceptScrollIn(c, r.startY, r.pushY, morphMilli(at))
    : r.drive === 'momentum' ? acceptMomentum(c, r.startY, r.pushY, morphMilli(at), sp.scrolls, sp.push) : c;
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
    const o = out.get(key) ?? { runs: 0, events: 0, trusted: 0, prevented: 0, cancelable: 0, morphMax: 0, scrolledIn: 0, wheels: 0, scrollEvents: 0, pushSeen: 0, inFlight: 0, gapFrames: [], flightOpen: [] };
    o.runs++;
    const sp = splitPush(r.fin.events);
    o.scrollEvents += sp.scrolls.length;
    if (sp.push !== null) {
      o.pushSeen++;
      if (inFlight(sp.scrolls, sp.push)) o.inFlight++;
      if (sp.scrolls.length) o.gapFrames.push(sp.push - Math.max(...sp.scrolls));
      o.flightOpen.push(flightFrames(sp.scrolls, sp.push, r.open ?? 0));
    }
    for (const e of r.fin.events) { o.events++; o.trusted += e.trusted ? 1 : 0; o.prevented += e.prevented ? 1 : 0; o.cancelable += e.cancelable ? 1 : 0; }
    o.morphMax = Math.max(o.morphMax, morphMilli(r.fin.at) / 1000);
    if (typeof r.pushY === 'number' && r.pushY > r.startY) o.scrolledIn++;
    o.wheels += r.wheels ?? 0;
    out.set(key, o);
  }
  return out;
}

export function analyze(files, { labels } = {}) {
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
    jobs: files.length, labels: labels ?? files.map((f, i) => jobLabel(f.jobIndex, i, files.length)), stat, drive, arm, cls,
    refused: per.map((p) => Object.fromEntries(p.refused)), facts: files.map((f) => Object.fromEntries(pushFacts(f))),
  };
}

const f2 = (x) => (x === null ? 'n/a' : Number.isInteger(x) ? String(x) : x.toFixed(2));
const WORDS = { lower: 'lower', higher: 'higher', overlap: 'overlap' };
const perJob = (vs) => vs.map((v) => WORDS[v]).join(' / ');

export function macMd(a) {
  const L = [];
  const J = Array.from({ length: a.jobs }, (_, j) => j);
  L.push(`Playwright WebKit, ${a.jobs} job(s). Per-frame record counts averaged over the runs the phase rule accepts (n). Every verdict is decided inside one job from that job's own runs and is stated only when its per-run ranges are separated; the jobs are listed in order and never pooled. Drive verdicts compare the drive against synthetic (lower: the drive is below synthetic); arm verdicts compare rewrite against original (lower: rewrite is below original). A verdict cell lists ${J.map((j) => a.labels[j]).join(' / ')} in that order.`, '');
  L.push('### Pushes seen by the page', '', '| job | arm | drive | runs | wheel events | isTrusted | cancelable | defaultPrevented | max --morph | scrolled before the push | scroll wheels |', '|---|---|---|---|---|---|---|---|---|---|---|');
  for (const j of J) for (const [k, o] of Object.entries(a.facts[j])) L.push(`| ${a.labels[j]} | ${k.replace('|', ' | ')} | ${o.runs} | ${o.events} | ${o.trusted} | ${o.cancelable} | ${o.prevented} | ${f2(o.morphMax)} | ${o.scrolledIn} | ${o.wheels} |`);
  L.push('', `### Scroll in flight at the push (a scroll wheel at frame s is in flight for frames s to s + ${FLIGHT_HOLD}; Lean inFlight, flightFrames)`, '', '| job | arm | drive | runs | push seen | scroll wheels before the push (mean) | push with a scroll in flight | last scroll to push, frames (mean) | open-phase frames in flight (mean) |', '|---|---|---|---|---|---|---|---|---|');
  for (const j of J) for (const [k, o] of Object.entries(a.facts[j])) if (o.scrollEvents > 0) L.push(`| ${a.labels[j]} | ${k.replace('|', ' | ')} | ${o.runs} | ${o.pushSeen} | ${f2(o.scrollEvents / o.runs)} | ${o.inFlight} | ${f2(mean(o.gapFrames))} | ${f2(mean(o.flightOpen))} |`);
  if (a.refused.some((r) => Object.keys(r).length)) {
    L.push('', '### Runs the phase rule or the capture refused', '', '| job | arm | drive | refused | reasons |', '|---|---|---|---|---|');
    for (const j of J) for (const [k, rows] of Object.entries(a.refused[j])) L.push(`| ${a.labels[j]} | ${k.replace('|', ' | ')} | ${rows.length} | ${[...new Set(rows.map((r) => r.outcome))].join(', ')} |`);
  }
  for (const ph of PHASES) {
    L.push('', `### ${ph} phase, mean per frame`, '', `| job | arm | drive | n | frames | ${METRICS.join(' | ')} |`, `|---|---|---|---|---|${METRICS.map(() => '---').join('|')}|`);
    for (const j of J) for (const arm of ARMS) for (const d of DRIVES) {
      const s = a.stat[`${arm}|${d}|${ph}`][j];
      L.push(`| ${a.labels[j]} | ${arm} | ${d} | ${s.n} | ${f2(s.frames)} | ${METRICS.map((m) => f2(s.mean[m])).join(' | ')} |`);
    }
    L.push('', `| ${ph}: verdict per job | ${METRICS.join(' | ')} |`, `|---|${METRICS.map(() => '---').join('|')}|`);
    for (const arm of ARMS) for (const d of DRIVES) if (d !== BASE_DRIVE) L.push(`| ${arm}: ${d} vs ${BASE_DRIVE} | ${METRICS.map((m) => perJob(a.drive[`${arm}|${d}|${ph}`][m].verdicts)).join(' | ')} |`);
    for (const d of DRIVES) L.push(`| ${d}: original vs rewrite | ${METRICS.map((m) => perJob(a.arm[`${d}|${ph}`][m].verdicts)).join(' | ')} |`);
    L.push('', `| ${ph}: class of the phase totals over runs, per job | ${METRICS.join(' | ')} |`, `|---|${METRICS.map(() => '---').join('|')}|`);
    for (const arm of ARMS) for (const d of DRIVES) for (const j of J) {
      const c = a.cls[`${arm}|${d}|${ph}`][j];
      L.push(`| ${arm} ${d} ${a.labels[j]} | ${METRICS.map((m) => c?.[m] ?? 'n/a').join(' | ')} |`);
    }
  }
  return `${L.join('\n')}\n`;
}
