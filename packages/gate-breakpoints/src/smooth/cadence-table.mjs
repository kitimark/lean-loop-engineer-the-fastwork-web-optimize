// Per-window, per-arm cadence tables from the downloaded cadence runs (task smoothness-probe, part B). Reads only.
// Layout read: <runs>/<runId>/<artifact>/cadence-<width>.json (the file src/smooth/cli.mjs `run` writes); each file is one job, one sample.
// Every decision (bad frame, rate, spread, verdict) is reduce.mjs, the TS twin of lean/Fw/Gate/Smooth.lean; this file only groups.
import { mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { armRate, quantile, repOf, repRange, spread, verdict } from './reduce.mjs';

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
  const traces = (file.traces ?? []).filter((t) => t.width === width && t.window === window);
  return { run: runId, width, window, search: file.search, hash: file.hash, baseHash: file.baseHash, version: file.version, spread: sp, arms: stat, verdicts, traces, hitches: hitchesOf(rows) };
}

/** A hitch is a gap of 60 ms or more. Per arm: where it fell (scroll position, frame index), how long, and the long animation frame the browser reported. Descriptive. */
export const HITCH_TENTHS = 600;
export function hitchesOf(rows) {
  return Object.fromEntries(ARMS.map((a) => [a, rows.filter((r) => r.arm === a).flatMap((r) => r.ivs.flatMap((v, i) => (v >= HITCH_TENTHS
    ? [{ rep: r.rep, i, ms: v / 10, y: r.ys?.[i] ?? null, loaf: (r.loaf ?? []).some((l) => l.d >= 50) }] : [])))]));
}

/** Every cell of every run under `dir`. Refused or empty files are listed in `skipped`. */
export function cellsOf(dir) {
  const cells = [];
  const skipped = [];
  for (const id of readdirSync(dir).filter((n) => /^\d+$/.test(n)).sort()) {
    for (const f of walk(join(dir, id)).filter((p) => /cadence-\d+\.json$/.test(p))) {
      const file = JSON.parse(readFileSync(f, 'utf8'));
      // One job is one sample: the label is the run id and the artifact of the job (`smoothness-<width>-<set>`).
      const label = `${id}:${f.slice(join(dir, id).length + 1).split('/')[0]}`;
      if (file.refused || file.runs.length === 0) { skipped.push({ run: label, why: file.refused ? 'refused' : 'empty' }); continue; }
      for (const width of [...new Set(file.runs.map((r) => r.width))]) for (const window of ['hero', 'end']) cells.push(cellOf(label, file, width, window));
    }
  }
  return { cells, skipped };
}

/** Across runs, per width, window and pair: how many runs said each verdict, and the median rate difference (second minus first). */
export function summary(cells) {
  const g = new Map();
  for (const c of cells) for (const [pair, v] of Object.entries(c.verdicts)) {
    const [a, b] = pair.split('|');
    const k = [c.width, c.window, pair].join('|');
    if (!g.has(k)) g.set(k, { width: c.width, window: c.window, first: a, second: b, runs: [], counts: { first: 0, second: 0, same: 0, insufficient: 0 }, diffs: [], spreads: [] });
    const e = g.get(k);
    e.runs.push(c.run);
    e.counts[v]++;
    e.diffs.push(c.arms[b].rate - c.arms[a].rate);
    e.spreads.push(c.spread);
  }
  return [...g.values()].map((e) => ({ ...e, medianDiff: quantile(e.diffs, 50), medianSpread: quantile(e.spreads, 50) }))
    .sort((x, y) => x.width - y.width || x.window.localeCompare(y.window) || PAIRS.findIndex(([a, b]) => a === x.first && b === x.second) - PAIRS.findIndex(([a, b]) => a === y.first && b === y.second));
}

const pct = (r) => (r / 100).toFixed(2);
const ms = (t) => (t === null ? '-' : (t / 10).toFixed(1));

/** The tables as markdown. Rates are bad frames (interval over 34 ms) per 10000 frames, shown as percent. */
export function markdown({ cells, skipped }, sum) {
  const out = [];
  out.push('Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent).', '');
  out.push('### Per run', '');
  for (const c of cells) {
    out.push(`**run ${c.run}, ${c.width}px, window ${c.window}** (candidate ${c.search || 'default'}, A/A spread ${pct(c.spread)} points)`, '');
    out.push('| arm | reps | frames | bad-frame rate % | range of reps (points) | p50 ms | p95 ms | p99 ms | max ms |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (const a of ARMS) {
      const s = c.arms[a];
      out.push(`| ${a} | ${s.reps} | ${s.frames} | ${pct(s.rate)} | ${pct(s.range)} | ${ms(s.p50)} | ${ms(s.p95)} | ${ms(s.p99)} | ${ms(s.max)} |`);
    }
    out.push('', `Verdicts: ${PAIRS.map(([a, b]) => `${a} vs ${b}: ${c.verdicts[`${a}|${b}`]}`).join('; ')}`, '');
  }
  out.push('### Across runs', '', '| width | window | first | second | runs | first smoother | second smoother | same | insufficient | median rate difference second-first (points) | median A/A spread (points) |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  for (const e of sum) out.push(`| ${e.width} | ${e.window} | ${e.first} | ${e.second} | ${e.runs.join(', ')} | ${e.counts.first} | ${e.counts.second} | ${e.counts.same} | ${e.counts.insufficient} | ${pct(e.medianDiff)} | ${pct(e.medianSpread)} |`);
  out.push('', '### Hitches (gaps of 60 ms or more, descriptive, never in the verdict)', '', '| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  for (const c of cells) for (const a of ARMS) {
    const h = c.hitches?.[a] ?? [];
    if (h.length === 0) continue;
    const ys = h.map((x) => x.y).filter((y) => y !== null);
    const loafReps = new Set(h.filter((x) => x.loaf).map((x) => x.rep)).size;
    out.push(`| ${c.run} | ${c.width} | ${c.window} | ${a} | ${c.arms[a].reps} | ${h.length} | ${(quantile(h.map((x) => x.ms * 10), 50) / 10).toFixed(1)} | ${ys.length ? quantile(ys, 50) : '-'} | ${loafReps} |`);
  }
  const traced = cells.filter((c) => c.traces.length > 0);
  if (traced.length > 0) {
    out.push('', '### Chromium frame trace (traced reps, reported apart, never in the verdict)', '', '| run | width | window | arm | traced reps | frames begun | frames drawn | dropped (reporter) | dropped (event) | presented | presented p95 ms |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (const c of traced) for (const a of ARMS) {
      const ts = c.traces.filter((t) => t.arm === a).map((t) => t.trace);
      if (ts.length === 0) continue;
      const sum2 = (f) => ts.reduce((x, t) => x + (t[f] ?? 0), 0);
      out.push(`| ${c.run} | ${c.width} | ${c.window} | ${a} | ${ts.length} | ${sum2('BeginFrame')} | ${sum2('DrawFrame')} | ${sum2('dropped')} | ${sum2('DroppedFrame')} | ${sum2('presented')} | ${ms(quantile(ts.map((t) => t.presentedP95).filter((x) => x !== null), 50))} |`);
    }
  }
  const slowCells = traced.filter((c) => c.traces.some((t) => (t.trace.slow ?? []).length > 0));
  if (slowCells.length > 0) {
    out.push('', '### Longest trace events of the traced reps (events of 15 ms or more; per arm the longest, summed over the traced reps)', '', '| run | width | window | arm | event | count | longest ms | total ms |', '| --- | --- | --- | --- | --- | --- | --- | --- |');
    for (const c of slowCells) for (const a of ARMS) {
      const by = new Map();
      for (const t of c.traces.filter((x) => x.arm === a)) for (const s of t.trace.slow ?? []) {
        const e = by.get(s.name) ?? { n: 0, max: 0, sum: 0 };
        by.set(s.name, { n: e.n + s.n, max: Math.max(e.max, s.max), sum: e.sum + s.sum });
      }
      for (const [name, e] of [...by.entries()].sort((x, y) => y[1].max - x[1].max).slice(0, 5)) out.push(`| ${c.run} | ${c.width} | ${c.window} | ${a} | ${name} | ${e.n} | ${ms(e.max)} | ${ms(e.sum)} |`);
    }
  }
  if (skipped.length > 0) out.push('', `Skipped: ${skipped.map((s) => `${s.run} (${s.why})`).join(', ')}`);
  return out.join('\n');
}

export async function cadenceMain(runsDir, outDir) {
  if (!runsDir || !outDir) { console.error('cadence needs --runs <dir> --out <dir>'); process.exit(2); }
  const all = cellsOf(runsDir);
  const sum = summary(all.cells);
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, 'cadence.table.json'), `${JSON.stringify({ skipped: all.skipped, cells: all.cells, summary: sum }, null, 1)}\n`);
  writeFileSync(join(outDir, 'cadence.table.md'), `${markdown(all, sum)}\n`);
  console.log(`cadence: ${all.cells.length} cells from ${new Set(all.cells.map((c) => c.run)).size} runs, ${all.skipped.length} skipped`);
}
