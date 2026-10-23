import { mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { acrossDecisive, agreeNeeded, armRate, decisive, HITCH_TENTHS, hitches, hitchVerdict, quantile, repOf, repRange, spread, verdict } from './reduce.mjs';

const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const ARMS = ['orig', 'base', 'aa', 'cand'];
/** The pairs judged, each against the A/A pair (base, aa): [first arm, second arm]. */
export const PAIRS = [['orig', 'base'], ['base', 'cand'], ['orig', 'cand']];

/** One cell of one run: width and window, the arms' repeats, rates, descriptive interval quantiles and the verdicts. */
export function cellOf(runId, file, width, window) {
  const rows = file.runs.filter((r) => r.width === width && r.window === window);
  const arms = Object.fromEntries(ARMS.map((a) => [a, rows.filter((r) => r.arm === a).sort((x, y) => x.rep - y.rep).map((r) => repOf(r.ivs))]));
  const pooled = (a) => rows.filter((r) => r.arm === a).flatMap((r) => r.ivs);
  const stat = Object.fromEntries(ARMS.map((a) => {
    const ivs = pooled(a);
    return [a, { reps: arms[a].length, frames: ivs.length, rate: armRate(arms[a]), range: repRange(arms[a]),
      p50: quantile(ivs, 50), p95: quantile(ivs, 95), p99: quantile(ivs, 99), max: ivs.length ? Math.max(...ivs) : null }];
  }));
  const sp = spread(arms.base, arms.aa);
  const verdicts = Object.fromEntries(PAIRS.map(([a, b]) => [`${a}|${b}`, verdict(arms[a], arms[b], arms.base, arms.aa)]));
  const hitchReps = Object.fromEntries(ARMS.map((a) => [a, rows.filter((r) => r.arm === a).sort((x, y) => x.rep - y.rep).map((r) => hitches(r.ivs))]));
  const hitchVerdicts = Object.fromEntries(PAIRS.map(([a, b]) => [`${a}|${b}`, hitchVerdict(hitchReps[a], hitchReps[b], hitchReps.base, hitchReps.aa)]));
  const traces = (file.traces ?? []).filter((t) => t.width === width && t.window === window);
  return { run: runId, width, window, cpuThrottle: file.cpuThrottle ?? 1, search: file.search, hash: file.hash, baseHash: file.baseHash, version: file.version, spread: sp, arms: stat, verdicts, hitchReps, hitchVerdicts, traces, hitches: hitchesOf(rows) };
}

/** A hitch is a gap over 60 ms (Lean `hitchTenths`). Per arm: where it fell (scroll position, frame index), how long, and the long animation frame the browser reported. Descriptive. */
export function hitchesOf(rows) {
  return Object.fromEntries(ARMS.map((a) => [a, rows.filter((r) => r.arm === a).flatMap((r) => r.ivs.flatMap((v, i) => (v > HITCH_TENTHS
    ? [{ rep: r.rep, i, ms: v / 10, y: r.ys?.[i] ?? null, loaf: (r.loaf ?? []).some((l) => l.d >= 50) }] : [])))]));
}

/** Every cell of every run under `dir`. Refused or empty files are listed in `skipped`. */
export function cellsOf(dir) {
  const cells = [];
  const skipped = [];
  for (const id of readdirSync(dir).filter((n) => /^\d+$/.test(n)).sort()) {
    for (const f of walk(join(dir, id)).filter((p) => /cadence-\d+\.json$/.test(p))) {
      const file = JSON.parse(readFileSync(f, 'utf8'));
      const label = `${id}:${f.slice(join(dir, id).length + 1).split('/')[0]}`;
      if (file.refused || file.runs.length === 0) { skipped.push({ run: label, why: file.refused ? 'refused' : 'empty' }); continue; }
      for (const width of [...new Set(file.runs.map((r) => r.width))]) for (const window of ['hero', 'end']) cells.push(cellOf(label, file, width, window));
    }
  }
  return { cells, skipped };
}

/**
 * Across samples (one CI job is one sample), per width, window and pair: how many samples said each verdict (rate rule and hitch rule), the
 * median rate difference (second minus first) and the verdict over the samples (Lean `acrossDecisive`: `across` with `agreeNeeded` of the decisive samples, the TS twin in reduce.mjs).
 */
export function summary(cells) {
  const g = new Map();
  for (const c of cells) for (const [pair, v] of Object.entries(c.verdicts)) {
    const [a, b] = pair.split('|');
    const k = [c.width, c.window, pair].join('|');
    if (!g.has(k)) g.set(k, { width: c.width, window: c.window, first: a, second: b, runs: [], counts: { first: 0, second: 0, same: 0, insufficient: 0 }, hitchCounts: { first: 0, second: 0, same: 0, insufficient: 0 }, verdicts: [], hitchVerdicts: [], diffs: [], spreads: [] });
    const e = g.get(k);
    const hv = c.hitchVerdicts[pair];
    e.runs.push(c.run);
    e.counts[v]++;
    e.hitchCounts[hv]++;
    e.verdicts.push(v);
    e.hitchVerdicts.push(hv);
    e.diffs.push(c.arms[b].rate - c.arms[a].rate);
    e.spreads.push(c.spread);
  }
  return [...g.values()].map((e) => ({ ...e, n: e.runs.length, needRate: agreeNeeded(decisive(e.verdicts)), needHitch: agreeNeeded(decisive(e.hitchVerdicts)),
    medianDiff: quantile(e.diffs, 50), medianSpread: quantile(e.spreads, 50), acrossRate: acrossDecisive(e.verdicts), acrossHitch: acrossDecisive(e.hitchVerdicts) }))
    .sort((x, y) => x.width - y.width || x.window.localeCompare(y.window) || PAIRS.findIndex(([a, b]) => a === x.first && b === x.second) - PAIRS.findIndex(([a, b]) => a === y.first && b === y.second));
}

const pct = (r) => (r / 100).toFixed(2);
const ms = (t) => (t === null ? '-' : (t / 10).toFixed(1));
const WORD = { first: 'first smoother', second: 'second smoother', same: 'not told apart', insufficient: 'insufficient' };

/** Trace totals per width, window and arm over every traced rep that carries the page-sink fields (older files hold unfiltered counts and are left out). */
export function traceTotals(cells) {
  const g = new Map();
  for (const c of cells) for (const t of c.traces) {
    if (!t.trace?.sink) continue;
    const k = [c.width, c.window, t.arm].join('|');
    if (!g.has(k)) g.set(k, { width: c.width, window: c.window, arm: t.arm, runs: new Set(), reps: 0, frames: 0, presented: 0, dropped: 0, droppedAll: 0, noUpdate: 0, presentedP95: [], rafFrames: 0, slow: new Map() });
    const e = g.get(k);
    e.runs.add(c.run);
    e.reps++;
    for (const f of ['frames', 'presented', 'dropped', 'droppedAll', 'noUpdate']) e[f] += t.trace[f];
    e.rafFrames += t.frames;
    if (t.trace.presentedP95 !== null) e.presentedP95.push(t.trace.presentedP95);
    for (const r of t.trace.slow ?? []) {
      const x = e.slow.get(r.name) ?? { n: 0, nLong: 0, max: 0, sum: 0, long: [] };
      e.slow.set(r.name, { n: x.n + r.n, nLong: x.nLong + r.nLong, max: Math.max(x.max, r.max), sum: x.sum + r.sum, long: [...x.long, ...r.long] });
    }
  }
  return [...g.values()].map((e) => ({ ...e, runs: [...e.runs] }))
    .sort((x, y) => x.width - y.width || x.window.localeCompare(y.window) || ARMS.indexOf(x.arm) - ARMS.indexOf(y.arm));
}

/** The tables as markdown. Rates are bad frames (interval over 34 ms) per 10000 frames, shown as percent. */
export function markdown({ cells, skipped }, sum) {
  const out = [];
  out.push('Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.', '');
  out.push('Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page\'s own frame sink and are reported beside them; they never enter a verdict.', '');
  out.push('### Per run', '');
  for (const c of cells) {
    out.push(`**run ${c.run}, ${c.width}px, window ${c.window}** (CPU throttle ${c.cpuThrottle}x, candidate ${c.search || 'default'}, A/A spread ${pct(c.spread)} points)`, '');
    out.push('| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (const a of ARMS) {
      const s = c.arms[a];
      const hr = c.hitchReps[a];
      out.push(`| ${a} | ${s.reps} | ${s.frames} | ${pct(s.rate)} | ${pct(s.range)} | ${hr.filter((x) => x > 0).length} of ${hr.length} | ${hr.join(',')} | ${ms(s.p50)} | ${ms(s.p95)} | ${ms(s.p99)} | ${ms(s.max)} |`);
    }
    out.push('', `Rate verdicts: ${PAIRS.map(([a, b]) => `${a} vs ${b}: ${c.verdicts[`${a}|${b}`]}`).join('; ')}`, `Hitch verdicts: ${PAIRS.map(([a, b]) => `${a} vs ${b}: ${c.hitchVerdicts[`${a}|${b}`]}`).join('; ')}`, '');
  }
  out.push('### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)', '', '| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  for (const e of sum) out.push(`| ${e.width} | ${e.window} | ${e.first} | ${e.second} | ${e.n} | ${e.needRate} / ${e.needHitch} | ${e.counts.first} / ${e.counts.second} / ${e.counts.same} / ${e.counts.insufficient} | ${WORD[e.acrossRate]} | ${e.hitchCounts.first} / ${e.hitchCounts.second} / ${e.hitchCounts.same} / ${e.hitchCounts.insufficient} | ${WORD[e.acrossHitch]} | ${pct(e.medianDiff)} | ${pct(e.medianSpread)} |`);
  out.push('', 'Samples: ' + [...new Set(sum.flatMap((e) => e.runs))].join(', '));
  out.push('', '### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)', '', '| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  for (const c of cells) for (const a of ARMS) {
    const h = c.hitches?.[a] ?? [];
    if (h.length === 0) continue;
    const ys = h.map((x) => x.y).filter((y) => y !== null);
    const loafReps = new Set(h.filter((x) => x.loaf).map((x) => x.rep)).size;
    out.push(`| ${c.run} | ${c.width} | ${c.window} | ${a} | ${c.arms[a].reps} | ${h.length} | ${(quantile(h.map((x) => x.ms * 10), 50) / 10).toFixed(1)} | ${ys.length ? quantile(ys, 50) : '-'} | ${loafReps} |`);
  }
  const totals = traceTotals(cells);
  const legacy = cells.reduce((n, c) => n + c.traces.filter((t) => !t.trace?.sink).length, 0);
  if (totals.length > 0) {
    out.push('', '### Frames of the page\'s compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)', '',
      'A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.', '',
      '| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (const e of totals) out.push(`| ${e.width} | ${e.window} | ${e.arm} | ${e.reps} | ${e.runs.length} | ${e.frames} | ${e.presented} | ${e.dropped} | ${(100 * e.dropped / Math.max(1, e.frames)).toFixed(1)} | ${e.droppedAll} | ${(100 * e.droppedAll / Math.max(1, e.frames)).toFixed(1)} | ${e.rafFrames} | ${ms(quantile(e.presentedP95, 50))} |`);
    out.push('', '### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)', '',
      '| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (const e of totals) for (const [name, x] of e.slow) out.push(`| ${e.width} | ${e.window} | ${e.arm} | ${e.reps} | ${name} | ${x.n} | ${x.nLong} | ${ms(x.max)} | ${ms(x.sum)} | ${x.long.sort((p, q) => p - q).map((d) => (d / 10).toFixed(1)).join(', ') || '-'} |`);
  }
  if (legacy > 0) out.push('', `${legacy} traced windows from runs before the page-sink filter hold counts over every process; they are not shown (see the handoff).`);
  if (skipped.length > 0) out.push('', `Skipped: ${skipped.map((s) => `${s.run} (${s.why})`).join(', ')}`);
  return out.join('\n');
}

export async function cadenceMain(runsDir, outDir) {
  if (!runsDir || !outDir) { console.error('cadence needs --runs <dir> --out <dir>'); process.exit(2); }
  const all = cellsOf(runsDir);
  const throttles = [...new Set(all.cells.map((c) => c.cpuThrottle))];
  if (throttles.length > 1) { console.error(`cadence: runs with different CPU throttles (${throttles.join(', ')}); build one table per throttle`); process.exit(2); }
  const sum = summary(all.cells);
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, 'cadence.table.json'), `${JSON.stringify({ skipped: all.skipped, cells: all.cells, summary: sum, traceTotals: traceTotals(all.cells).map((e) => ({ ...e, slow: [...e.slow.entries()].map(([name, x]) => ({ name, ...x })) })) }, null, 1)}\n`);
  writeFileSync(join(outDir, 'cadence.table.md'), `${markdown(all, sum)}\n`);
  console.log(`cadence: ${all.cells.length} cells from ${new Set(all.cells.map((c) => c.run)).size} runs, ${all.skipped.length} skipped`);
}
