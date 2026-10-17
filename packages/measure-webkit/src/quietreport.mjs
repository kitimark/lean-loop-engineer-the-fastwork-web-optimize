// webkit-quiet report: dose-response tables from one or more `quiet` outputs (fw.webkit.quiet/1). Pure functions over the JSON;
// the cli prints Markdown. Arms are pooled across files (VMs); jitter is always computed between passes of the SAME arm of the
// SAME file (one Simulator session), so a VM-to-VM difference never counts as jitter.
import { COUNT_TYPES } from './reduce.mjs';

const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null);
const median = (a) => { if (!a.length) return null; const s = [...a].sort((x, y) => x - y); return s[s.length >> 1]; };
const r1 = (x) => (x === null ? null : Math.round(x * 10) / 10);
const r2 = (x) => (x === null ? null : Math.round(x * 100) / 100);

/** Step durations in ms from the step marks (the last step ends at endTime). */
export const stepDurations = (scroll) => scroll.marks.map((t, k) => ((k + 1 < scroll.marks.length ? scroll.marks[k + 1] : scroll.endTime) - t) * 1000);

/** Mean top-idle % and mean load over the samples inside the scroll's wall window. */
export function hostOf(pass) {
  const { start, end } = pass.scroll.wall;
  const s = pass.host.top.filter((x) => x.t >= start && x.t <= end + 1000);
  return { samples: s.length, idle: r1(mean(s.map((x) => x.idle))), load1: r1(mean(s.map((x) => x.load1))), minIdle: s.length ? Math.min(...s.map((x) => x.idle)) : null };
}

/** Per-step lag (max over the 250 ms buckets the step covers), from the step durations laid end to end from wall.start. */
export function lagPerStep(pass) {
  const d = stepDurations(pass.scroll), { bucketMs, max } = pass.scroll.lag;
  let t = 0;
  return d.map((ms) => { const a = Math.floor(t / bucketMs), b = Math.floor((t + ms) / bucketMs); t += ms; let m = 0; for (let i = a; i <= Math.min(b, max.length - 1); i++) m = Math.max(m, max[i] ?? 0); return m; });
}

/** Spread (max - min) per step over passes, for one count type column j. */
function stepSpreads(passes, j, n) {
  const out = [];
  for (let k = 0; k < n; k++) { const v = passes.map((p) => p.scroll.reduced.perStep[k][j]); out.push(Math.max(...v) - Math.min(...v)); }
  return out;
}

/** One row per (arm): host and duration summaries, and per type {jitter, bad, totalSpreadRel}. `files` = parsed quiet outputs. */
export function byArm(files) {
  const arms = [...new Set(files.flatMap((f) => f.passes.map((p) => p.arm)))].sort((a, b) => a - b);
  return arms.map((arm) => {
    const groups = files.map((f) => f.passes.filter((p) => p.arm === arm)).filter((g) => g.length >= 2);
    const all = groups.flat();
    const host = all.map(hostOf);
    const dur = all.flatMap((p) => stepDurations(p.scroll));
    const types = {};
    COUNT_TYPES.forEach((t, j) => {
      const spreads = [], bad = [], rel = [];
      for (const g of groups) {
        const n = Math.min(...g.map((p) => p.scroll.ys.length));
        const sp = stepSpreads(g, j, n);
        spreads.push(...sp); bad.push(...sp.map((x) => (x > 1 ? 1 : 0)));
        const tot = g.map((p) => p.scroll.reduced.total[t]); const m = mean(tot);
        rel.push(m ? (Math.max(...tot) - Math.min(...tot)) / m : 0);
      }
      types[t] = { jitter: r2(mean(spreads)), bad: r2(mean(bad)), totalSpreadRel: r2(mean(rel)), mean: r1(mean(all.map((p) => p.scroll.reduced.total[t]))) };
    });
    return {
      arm, passes: all.length, wallMs: r1(mean(all.map((p) => p.scroll.scrollWallMs))), medianStepMs: r1(median(dur)), p90StepMs: r1([...dur].sort((a, b) => a - b)[Math.floor(dur.length * 0.9)]),
      idle: r1(mean(host.map((h) => h.idle).filter((x) => x !== null))), load1: r1(mean(host.map((h) => h.load1).filter((x) => x !== null))), types,
    };
  });
}

export function armsTable(rows, typeNames = COUNT_TYPES) {
  const out = ['| burners | passes | wall ms | median step ms | p90 step ms | top idle % | load1 |', '|---|---|---|---|---|---|---|'];
  for (const r of rows) out.push(`| ${r.arm} | ${r.passes} | ${r.wallMs} | ${r.medianStepMs} | ${r.p90StepMs} | ${r.idle} | ${r.load1} |`);
  out.push('', '| count type | metric | ' + rows.map((r) => `${r.arm} burners`).join(' | ') + ' |', '|---|---|' + rows.map(() => '---').join('|') + '|');
  for (const t of typeNames) {
    out.push(`| ${t} | step jitter (mean spread) | ${rows.map((r) => r.types[t].jitter).join(' | ')} |`);
    out.push(`| ${t} | steps with spread > 1 | ${rows.map((r) => r.types[t].bad).join(' | ')} |`);
    out.push(`| ${t} | total, mean over passes | ${rows.map((r) => r.types[t].mean).join(' | ')} |`);
    out.push(`| ${t} | total spread / mean | ${rows.map((r) => r.types[t].totalSpreadRel).join(' | ')} |`);
  }
  return out.join('\n');
}

/**
 * Within-step deviation correlation: for each (file, arm) group, count and log step duration minus their per-step means over the
 * passes of the group; Pearson over all (pass, step) pairs. Isolates "this pass's step was slower than the same step in the other
 * passes" from "this step is a heavy step".
 */
export function devCorrelation(files, durKey = 'dur') {
  const res = {};
  COUNT_TYPES.forEach((t, j) => {
    const xs = [], ys = [];
    for (const f of files) {
      for (const arm of new Set(f.passes.map((p) => p.arm))) {
        const g = f.passes.filter((p) => p.arm === arm); if (g.length < 2) continue;
        const n = Math.min(...g.map((p) => p.scroll.ys.length));
        const durs = g.map((p) => (durKey === 'lag' ? lagPerStep(p).map((x) => Math.log1p(x)) : stepDurations(p.scroll).map(Math.log)));
        for (let k = 0; k < n; k++) {
          const c = g.map((p) => p.scroll.reduced.perStep[k][j]), d = durs.map((x) => x[k]);
          const mc = mean(c), md = mean(d);
          c.forEach((v, i) => { xs.push(v - mc); ys.push(d[i] - md); });
        }
      }
    }
    res[t] = pearson(xs, ys);
  });
  return res;
}

export function pearson(x, y) {
  const mx = mean(x), my = mean(y); let sxy = 0, sxx = 0, syy = 0;
  for (let i = 0; i < x.length; i++) { sxy += (x[i] - mx) * (y[i] - my); sxx += (x[i] - mx) ** 2; syy += (y[i] - my) ** 2; }
  return sxx && syy ? r2(sxy / Math.sqrt(sxx * syy)) : null;
}
