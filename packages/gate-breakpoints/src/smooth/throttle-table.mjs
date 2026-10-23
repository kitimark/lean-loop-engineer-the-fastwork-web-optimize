// The 1x against 6x table of task smoothness-cpu-throttle. TS stand-in (no Lean rule): it only lines up the cadence tables that cadence-table.mjs
// built per throttle (cadence.table.json of a 1x run directory and of a 6x one) and takes medians over the job samples. The pair verdicts in it
// are the Lean rules' (reduce.mjs), copied from those tables. A PROXY of the lag felt on WebKit (iPhone), never WebKit evidence.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ARMS = ['orig', 'base', 'aa', 'cand'];
const med = (a) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.floor(s.length / 2)] : null; };
const pct = (r) => (r / 100).toFixed(1);
const load = (dir) => JSON.parse(readFileSync(join(dir, 'cadence.table.json'), 'utf8'));

/** Per width, window and arm: rate (percent, median and range over the job samples), hitches per rep (median over all reps), p50 and p95 ms (median over jobs). */
export function armRows(table) {
  const rows = [];
  for (const width of [...new Set(table.cells.map((c) => c.width))].sort((a, b) => a - b)) for (const window of ['hero', 'end']) {
    const cs = table.cells.filter((c) => c.width === width && c.window === window);
    if (cs.length === 0) continue;
    for (const arm of ARMS) {
      const rate = cs.map((c) => c.arms[arm].rate);
      rows.push({ width, window, arm, jobs: cs.length, rate: med(rate), rateMin: Math.min(...rate), rateMax: Math.max(...rate),
        hitches: med(cs.flatMap((c) => c.hitchReps[arm])), p50: med(cs.map((c) => c.arms[arm].p50)), p95: med(cs.map((c) => c.arms[arm].p95)) });
    }
  }
  return rows;
}

/** The markdown: one table of arms (1x beside 6x), one of the Lean pair verdicts over the job samples. */
export function compareMarkdown(a, b) {
  const ra = armRows(a);
  const rb = armRows(b);
  const out = ['Rate = bad frames (gap above 34 ms between rAF callbacks) per frame, percent, median over the job samples (range in brackets). Hitches = frames over 60 ms per repeat (median over all repeats). p50 and p95 are interval quantiles in ms (median over jobs).', '',
    '| width | window | arm | jobs | rate % 1x | rate % 6x | hitches/rep 1x | hitches/rep 6x | p50 ms 1x / 6x | p95 ms 1x / 6x |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'];
  for (const x of ra) {
    const y = rb.find((r) => r.width === x.width && r.window === x.window && r.arm === x.arm);
    const ms = (v) => (v / 10).toFixed(1);
    out.push(`| ${x.width} | ${x.window} | ${x.arm} | ${x.jobs} / ${y.jobs} | ${pct(x.rate)} (${pct(x.rateMin)}-${pct(x.rateMax)}) | ${pct(y.rate)} (${pct(y.rateMin)}-${pct(y.rateMax)}) | ${x.hitches} | ${y.hitches} | ${ms(x.p50)} / ${ms(y.p50)} | ${ms(x.p95)} / ${ms(y.p95)} |`);
  }
  const WORD = { first: 'first smoother', second: 'second smoother', same: 'not told apart', insufficient: 'insufficient' };
  out.push('', 'Pair verdicts over the job samples (Lean `acrossDecisive`; rate rule and hitch rule; the A/A spread is the larger of base against aa and the spread inside either, in points):', '',
    '| width | window | pair | 1x rate rule | 1x hitch rule | 1x A/A spread | 6x rate rule | 6x hitch rule | 6x A/A spread |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  for (const s of a.summary) {
    const t = b.summary.find((e) => e.width === s.width && e.window === s.window && e.first === s.first && e.second === s.second);
    out.push(`| ${s.width} | ${s.window} | ${s.first} vs ${s.second} | ${WORD[s.acrossRate]} (${s.counts.first}/${s.counts.second}/${s.counts.same}/${s.counts.insufficient}) | ${WORD[s.acrossHitch]} (${s.hitchCounts.first}/${s.hitchCounts.second}/${s.hitchCounts.same}/${s.hitchCounts.insufficient}) | ${pct(s.medianSpread)} | ${WORD[t.acrossRate]} (${t.counts.first}/${t.counts.second}/${t.counts.same}/${t.counts.insufficient}) | ${WORD[t.acrossHitch]} (${t.hitchCounts.first}/${t.hitchCounts.second}/${t.hitchCounts.same}/${t.hitchCounts.insufficient}) | ${pct(t.medianSpread)} |`);
  }
  out.push('', 'Counts in brackets: samples saying first / second / same / insufficient.');
  return out.join('\n');
}

export function throttleMain(dirA, dirB) {
  if (!dirA || !dirB) { console.error('throttle needs --a <1x table dir> --b <6x table dir>'); process.exit(2); }
  const a = load(dirA);
  const b = load(dirB);
  if (new Set(a.cells.map((c) => c.cpuThrottle)).size !== 1 || a.cells[0].cpuThrottle !== 1) { console.error('throttle: --a must hold only 1x cells'); process.exit(2); }
  if (new Set(b.cells.map((c) => c.cpuThrottle)).size !== 1 || b.cells[0].cpuThrottle !== 6) { console.error('throttle: --b must hold only 6x cells'); process.exit(2); }
  return compareMarkdown(a, b);
}
