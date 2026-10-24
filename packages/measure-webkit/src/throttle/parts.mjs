import { readFileSync } from 'node:fs';
import { countC, exitFramesC, throttleK, verdict, MIN_BASE, BAND_LO, BAND_HI } from './stillruns.mjs';
import { classes, maxStep, stalls, partSeries } from '../device-session.mjs';
import { SERIES } from './parts-recorder.mjs';
import { framesOf } from './finish-report.mjs';
import { reduce as finishReduce } from './finish.mjs';

const GOLDEN = readFileSync(new URL('../../../contracts/golden/device/throttle-parts.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
const of = (kind) => GOLDEN.filter((l) => l.kind === kind);

export const CONSTS = Object.freeze(of('consts')[0]);
export const PARTS = Object.freeze(of('part'));
export const PART_BY_ID = new Map(PARTS.map((p) => [p.id, p]));
export const KEYS = new Map(of('key').map((k) => [k.key, k]));
export const EXAMPLES = Object.freeze(of('example'));

export const ARMS = Object.freeze(['original', 'rewrite', 'lift', 'unthrottle']);
export const MODE_OF_ARM = Object.freeze({ original: 'throttled', rewrite: 'throttled', lift: 'lifted', unthrottle: 'lifted' });
export const modeOfArm = (arm) => MODE_OF_ARM[arm];

export function reach(source, shape) {
  if (source !== 'main-thread') return 'not-hit';
  switch (shape) {
    case 'curve': case 'chase': case 'capture': case 'step-look': return 'hit';
    case 'step-idle': case 'constant': return 'harmless';
    case 'no-read': return 'not-hit';
    default: throw new Error(`unknown shape ${shape}`);
  }
}

export function predicted(mode, source, shape) {
  if (mode === 'throttled' && source === 'main-thread' && shape === 'curve') return { pattern: 'stills', runFrames: throttleK(CONSTS.d60) };
  if (mode === 'throttled' && source === 'main-thread' && shape === 'chase') return { pattern: 'pulses' };
  return { pattern: 'no-stills' };
}

export const rowsOf = (vs) => vs.map((v) => [v, v]);


const MIN_FRAMES = 60;
const MIN_TRAVEL_TENTHS = 1000;
const DEFAULT_GAP = 1667;

export function medianGap(ts) {
  const g = [];
  for (let i = 1; i < ts.length; i++) g.push(Math.round((ts[i] - ts[i - 1]) * 100));
  if (g.length === 0) return DEFAULT_GAP;
  g.sort((a, b) => a - b);
  const d = g[Math.floor(g.length / 2)];
  return d > 0 ? d : DEFAULT_GAP;
}

export function bandFor(d) {
  const k = throttleK(d);
  return [k, k + 1];
}

export function excludeReason(p) {
  if (p.skipped) return p.skipped;
  const r = p.rec?.parts;
  if (!p.drag || p.drag.code !== 0) return p.drag?.timedOut ? 'touch driver timed out' : 'touch driver failed';
  if (!r) return 'no parts record';
  if (r.frames < MIN_FRAMES) return `fewer than ${MIN_FRAMES} frames`;
  if (Math.max(...r.y) - Math.min(...r.y) < MIN_TRAVEL_TENTHS) return 'page moved less than 100 px';
  if (Math.abs((r.start?.scale ?? 1) - 1) > 0.001) return 'page was zoomed';
  return null;
}

export function seriesCounts(parts, key) {
  const vs = parts.v?.[key] ?? [];
  const found = parts.found?.[key] === true && vs.length > 0;
  const d = medianGap(parts.t ?? []);
  const [lo, hi] = bandFor(d);
  const empty = { found, d, lo, hi, frames: vs.length, moving: 0, mid: 0, midMoving: 0, band: 0, band56: 0, short: 0, maxStep: 0, stalls: 0, pairs: 0 };
  if (!found) return empty;
  const cs = classes(parts.vh);
  const rows = vs.map((v, i) => [v, v, cs[i]]);
  return { ...empty,
    moving: cs.filter((c) => c === 'moving').length,
    mid: vs.filter((v) => v > 0 && v < 1000).length,
    midMoving: exitFramesC('moving', rows),
    band: countC('moving', lo, hi, rows),
    band56: countC('moving', BAND_LO, BAND_HI, rows),
    short: countC('moving', 1, 9, rows),
    maxStep: maxStep(rows), stalls: stalls(partSeries(parts.y, vs)), pairs: Math.max(0, vs.length - 1) };
}


const sum = (l) => l.reduce((a, b) => a + b, 0);

export function armSeries(passes, key) {
  const usable = passes.filter((p) => excludeReason(p) === null);
  const per = usable.map((p) => seriesCounts(p.rec.parts, key));
  const have = per.filter((c) => c.found);
  const t = (f) => sum(have.map(f));
  const row = { passes: passes.length, usable: usable.length, found: have.length, exercised: have.filter((c) => c.midMoving > 0).length,
    frames: t((c) => c.frames), moving: t((c) => c.moving), mid: t((c) => c.mid), midMoving: t((c) => c.midMoving),
    band: t((c) => c.band), band56: t((c) => c.band56), short: t((c) => c.short), stalls: t((c) => c.stalls), pairs: t((c) => c.pairs), maxStep: have.reduce((m, c) => Math.max(m, c.maxStep), 0),
    gaps: have.map((c) => c.d) };
  return { ...row,
    per1000Moving: row.moving ? Math.round((row.band * 10000) / row.moving) / 10 : null,
    stallsPer1000: row.pairs ? Math.round((row.stalls * 10000) / row.pairs) / 10 : null,
    per1000Mid: row.midMoving ? Math.round((row.band * 10000) / row.midMoving) / 10 : null };
}

export function judge(pred, mode, base, arm) {
  if (arm.frames === 0) return 'no-data';
  if (pred.pattern === 'stills') {
    if (mode === 'throttled') return arm.runs >= MIN_BASE ? 'agree' : 'disagree';
    const v = verdict([], base, arm);
    return v === 'lifted' ? 'agree' : v === 'no-data' ? 'no-data' : 'disagree';
  }
  return arm.runs < MIN_BASE ? 'agree' : 'disagree';
}

export function partVerdict(matches) {
  if (matches.includes('disagree')) return 'disagree';
  if (matches.includes('agree')) return matches.includes('no-data') ? 'agree (partial)' : 'agree';
  return 'no-data';
}

export const partOf = (seriesOfPart) => partVerdict(seriesOfPart.flatMap((s) => Object.values(s.match).map((m) => m.match)));

export function judgeArm(pred, arm, row, base) {
  const mode = modeOfArm(arm);
  const b = { runs: base.band, frames: base.midMoving };
  const a = { runs: row.band, frames: row.midMoving };
  const match = judge(pred, mode, b, a);
  let why;
  if (match === 'no-data') why = a.frames === 0 ? (row.found === 0 ? 'series never found' : 'value never strictly between 0 and 1000 while the toolbar moved') : `the rewrite had ${base.band} band runs, fewer than ${MIN_BASE}, or no frames`;
  else if (pred.pattern === 'stills' && mode === 'lifted') why = match === 'agree' ? 'rate at most a fifth of the rewrite' : `rate above a fifth of the rewrite (${row.band} runs in ${row.midMoving} frames)`;
  else if (pred.pattern === 'stills') why = match === 'agree' ? `${row.band} band runs` : `${row.band} band runs, fewer than ${MIN_BASE}`;
  else why = match === 'agree' ? `${row.band} band runs, fewer than ${MIN_BASE}` : `${row.band} band runs, at least ${MIN_BASE}`;
  return { match, why };
}


export function seriesModel(s) {
  const part = PART_BY_ID.get(s.part);
  if (!part) throw new Error(`series ${s.key}: part ${s.part} is not in the golden`);
  const gk = s.golden ? KEYS.get(s.golden) : null;
  const pat = (mode) => (gk ? gk.predicted[mode].pattern === 'stills' ? { pattern: 'stills', runFrames: gk.predicted[mode].runFrames }
    : { pattern: gk.predicted[mode].pattern } : predicted(mode, part.source, part.shape));
  return { part, source: gk ? gk.source : part.source, shape: gk ? gk.shape : part.shape, throttled: pat('throttled'), lifted: pat('lifted') };
}

export function reduceMode(passes) {
  const out = [];
  for (const s of SERIES) {
    const m = seriesModel(s);
    const rows = {};
    for (const a of ARMS) rows[a] = armSeries(passes.filter((p) => p.arm === a), s.key);
    const base = rows.rewrite;
    const verdicts = {};
    for (const a of ['lift', 'unthrottle']) verdicts[a] = verdict([], { runs: base.band, frames: base.midMoving }, { runs: rows[a].band, frames: rows[a].midMoving });
    const match = {};
    for (const a of ARMS) match[a] = judgeArm(m.throttled, a, rows[a], base);
    const perJob = [...new Set(passes.map((p) => p.vm))].map((vm) => ({
      vm, rows: Object.fromEntries(ARMS.map((a) => [a, armSeries(passes.filter((p) => p.arm === a && p.vm === vm), s.key)])) }));
    out.push({ ...s, part: s.part, zone: m.part.zone, reach: m.part.reach, source: m.source, shape: m.shape, predicted: { throttled: m.throttled, lifted: m.lifted },
      rows, verdicts, match, perJob });
  }
  return out;
}


export function noDataReason(part) {
  if (part.id === 'hero.exit:threaded') return 'not in the default build (flag hero.exit:threaded); the recorder arms do not include it';
  switch (part.shape) {
    case 'step-look': return 'a class or colour flip at a threshold; the recorder stores no flip times, and a flip has no still run';
    case 'step-idle': return 'starts or pauses a time-based animation; there is no per-frame value to record';
    case 'capture': return 'captures scrollY once and restores it; its observable is the reversal count while the morph is open (finish mode), not a still run';
    case 'no-read': return 'reads no scroll while moving; nothing to record';
    case 'constant': return 'constant on the moving range';
    default: return part.source === 'threaded' ? 'runs on the compositor; the page cannot read its value' : 'no recorded series';
  }
}

export const recordedParts = () => new Set(SERIES.map((s) => s.part));

export const noDataParts = () => PARTS.filter((p) => !recordedParts().has(p.id)).map((p) => ({ id: p.id, zone: p.zone, reach: p.reach, shape: p.shape, source: p.source, reason: noDataReason(p) }));


export function captureRow(passes) {
  const usable = passes.filter((p) => p.rec?.nav && !p.skipped && p.drag?.code === 0 && p.rec.frames >= MIN_FRAMES);
  const rs = usable.map((p) => finishReduce(framesOf(p.rec)));
  return { passes: passes.length, usable: usable.length, reversals: sum(rs.map((r) => r.reversals)), perPass: rs.map((r) => r.reversals),
    late: rs.map((r) => r.late) };
}


const med = (l) => (l.length === 0 ? null : [...l].sort((a, b) => a - b)[Math.floor(l.length / 2)]);
const fmt = (x) => (x === null || x === undefined ? 'n/a' : String(x));

const slim = (r) => { const { gaps, ...rest } = r; return { ...rest, medianGapMs: med(gaps) === null ? null : med(gaps) / 100 }; };

export function summarize(mode, jobs, runId = null) {
  const passes = jobs.flatMap((j) => j.passes.map((p) => ({ ...p, vm: p.vm ?? j.vm })));
  const reduced = reduceMode(passes);
  const series = reduced.map((s) => ({
    key: s.key, part: s.part, prop: s.prop, zone: s.zone, reach: s.reach, source: s.source, shape: s.shape, predicted: s.predicted,
    arms: Object.fromEntries(ARMS.map((a) => [a, slim(s.rows[a])])), verdicts: s.verdicts, match: s.match,
    jobs: s.perJob.map((j) => ({ vm: j.vm, arms: Object.fromEntries(ARMS.map((a) => [a, { band: j.rows[a].band, midMoving: j.rows[a].midMoving, usable: j.rows[a].usable }])) })) }));
  const parts = [...new Set(series.map((s) => s.part))].map((id) => ({ id, verdict: partOf(series.filter((s) => s.part === id)) }));
  const captures = Object.fromEntries(ARMS.map((a) => [a, captureRow(passes.filter((p) => p.arm === a))]));
  const lost = ARMS.map((a) => ({ arm: a, passes: passes.filter((p) => p.arm === a).length,
    usable: passes.filter((p) => p.arm === a && excludeReason(p) === null).length,
    reasons: passes.filter((p) => p.arm === a).map(excludeReason).filter(Boolean) }));
  return { mode, runId, jobs: jobs.length, series, parts, captures, lost, failed: jobs.flatMap((j) => j.failed ?? []) };
}

export function summaryMd(sm) {
  const L = [`### ${sm.mode} (run ${sm.runId ?? 'n/a'}, ${sm.jobs} jobs)`, '',
    'Band runs / frames of the series strictly between 0 and 1000 while the toolbar moved (per 1000 of those), verdict against the rewrite (lifted arms), match with the Lean prediction of the arm mode.', '',
    '| series (part) | arm | passes usable/run | band runs / mid-moving frames | per 1000 | band 5-6 | short 1-9 | stalls per 1000 | max step | verdict | predicted | match |',
    '|---|---|---|---|---|---|---|---|---|---|---|---|'];
  for (const s of sm.series) {
    for (const a of ARMS) {
      const r = s.arms[a];
      const m = s.match[a];
      L.push(`| ${s.key} (${s.part}) | ${a} | ${r.usable}/${r.passes} | ${r.band} / ${r.midMoving} | ${fmt(r.per1000Mid)} | ${r.band56} | ${r.short} | ${fmt(r.stallsPer1000)} | ${r.maxStep} | ${s.verdicts[a] ?? 'reference'} | ${s.predicted[modeOfArm(a)].pattern} | ${m.match}: ${m.why} |`);
    }
  }
  L.push('', '| part | verdict |', '|---|---|', ...sm.parts.map((p) => `| ${p.id} | ${p.verdict} |`), '',
    '| arm | passes | usable | lost reasons |', '|---|---|---|---|', ...sm.lost.map((l) => `| ${l.arm} | ${l.passes} | ${l.usable} | ${[...new Set(l.reasons)].join('; ') || 'none'} |`));
  if (sm.failed.length) L.push('', `Failed passes: ${sm.failed.length} (${sm.failed.slice(0, 6).join('; ')})`);
  if (sm.mode === 'finish') {
    L.push('', 'Capture parts (morph.mount, morph.tween): scrollY reversals while the morph is open, summed over usable passes.', '',
      '| arm | usable | reversals | per pass |', '|---|---|---|---|', ...ARMS.map((a) => `| ${a} | ${sm.captures[a].usable} | ${sm.captures[a].reversals} | ${sm.captures[a].perPass.join(' ')} |`));
  }
  return `${L.join('\n')}\n`;
}
