// The per-zone table of the cost counters, one row per zone and arm (reductions: cost.mjs, Lean Fw.Measure.WkCost; the
// arm verdict is reduce.mjs `verdict`, Fw.Measure.WebKitLag.verdict: a difference is stated only when the per-pass ranges are separated).
import { cadence, sumsOf, layerSums, early, late } from './cost.mjs';
import { frac, verdict, fracLt } from './reduce.mjs';

export const SCROLL_ZONES = Object.freeze(['scroll-A', 'scroll-B', 'scroll-calm']);
export const MORPH_ZONES = Object.freeze(['idle', 'open', 'close', 'rest']);
/** What each zone is called in the table. */
export const ZONE_LABEL = Object.freeze({
  'scroll-A': 'hero exit (scroll A)', 'scroll-B': 'end of page (scroll B)', 'scroll-calm': 'calm scroll (baseline)',
  idle: 'morph idle (baseline)', open: 'morph open (push down)', close: 'morph close (push up)', rest: 'morph rest',
});

const num = ([a, b]) => a / b;
const rangeOf = (qs) => (qs.length ? [qs.reduce((a, b) => (fracLt(b, a) ? b : a)), qs.reduce((a, b) => (fracLt(a, b) ? b : a))] : null);

/** Per-pass metric values (fractions) of one pass: { zone: { metric: Q } }. A metric with no frames or reads is left out. */
export function passMetrics(pass) {
  const out = {};
  const put = (z, name, n, d) => { if (d > 0) (out[z] ??= {})[name] = frac(n, d); };
  const cadenceOf = (z, frames, costs) => {
    const c = cadence(z, frames), s = sumsOf(z, costs);
    if (c.frames > 0) put(z, 'frames', c.frames, 1);
    put(z, 'skipped100', c.skipped * 100, c.frames);
    put(z, 'slots100', c.slots * 100, c.frames);
    put(z, 'over25_100', c.over25 * 100, c.frames);
    put(z, 'over50_100', c.over50 * 100, c.frames);
    put(z, 'paintPF', s.paintUs, s.frames);
    put(z, 'compPF', s.compUs, s.frames);
    put(z, 'bound100', s.bound * 100, s.frames);
  };
  const layersOf = (z, snaps) => {
    const l = layerSums(z, snaps);
    if (l.reads > 0) put(z, 'reads', l.reads, 1);
    put(z, 'fresh100', l.fresh * 100, l.reads);
    put(z, 'resized100', l.resized * 100, l.reads);
  };
  const k = pass.cost;
  if (!k) return out;
  if (k.scroll) for (const z of SCROLL_ZONES) cadenceOf(z, k.scroll.frames, k.scroll.costs);
  if (k.layersScroll) for (const z of SCROLL_ZONES) layersOf(z, k.layersScroll.snaps);
  if (k.morph) {
    for (const z of MORPH_ZONES) cadenceOf(z, k.morph.frames, k.morph.costs);
    for (const w of ['open', 'close']) { put(w, 'early', early(k.morph.ends[w], k.morph.paints), 1); put(w, 'late', late(k.morph.ends[w], k.morph.paints), 1); }
  }
  if (k.layersMorph) for (const z of MORPH_ZONES) layersOf(z, k.layersMorph.snaps);
  return out;
}

/** An arm (the session files of one arm) as per-zone, per-metric lists of per-pass values, plus the passes counted. */
export function collectArm(sessions) {
  const m = {};
  let passes = 0, withCost = 0;
  for (const s of sessions) for (const p of s.passes) {
    passes++;
    if (!p.cost) continue;
    withCost++;
    const pm = passMetrics(p);
    for (const [z, mm] of Object.entries(pm)) for (const [name, q] of Object.entries(mm)) ((m[z] ??= {})[name] ??= []).push(q);
  }
  return { metrics: m, passes, withCost };
}

const fmt = (x, d) => (Math.abs(x) >= 100 ? x.toFixed(0) : x.toFixed(d));
const span = (lo, hi) => (lo === hi ? lo : `${lo}-${hi}`);
const cell = (qs, d = 1) => { const r = rangeOf(qs ?? []); return r ? span(fmt(num(r[0]), d), fmt(num(r[1]), d)) : '-'; };
const vs = (base, other) => (base && other && base.length && other.length ? verdict(base, other) : '-');

const TABLES = Object.freeze([
  ['Frame cadence (rAF intervals; slot = round((t - t0) / 16.67 ms), skipped when it jumps more than one)', [
    ['frames', 'frames', 0], ['skipped100', 'skipped slots events / 100 frames', 1], ['slots100', 'slots lost / 100 frames', 1],
    ['over25_100', '> 25 ms / 100 frames', 1], ['over50_100', '> 50 ms / 100 frames', 1]], 'skipped100'],
  ['Paint against Composite per frame (Timeline durations, microseconds; the Inspector files raster under Composite)', [
    ['paintPF', 'Paint us / frame', 0], ['compPF', 'Composite us / frame', 0], ['bound100', 'Composite > Paint, % of frames', 0]], 'compPF'],
  ['Layers between layer-tree reads (new layer = id not in the previous read; resized = composited width or height changed)', [
    ['reads', 'reads', 0], ['fresh100', 'new layers / 100 reads', 1], ['resized100', 'resized layers / 100 reads', 1]], 'fresh100'],
]);

/** The markdown tables for arms [[name, collectArm(...)]], the first arm the reference of the "vs first arm" column. */
export function costMd(arms) {
  const lines = [];
  const base = arms[0];
  lines.push(`Arms: ${arms.map(([n, a]) => `${n} (${a.withCost}/${a.passes} passes with the cost counters)`).join(', ')}. Cells are per-pass ranges.`, '');
  for (const [title, cols, vcol] of TABLES) {
    lines.push(`#### ${title}`, '', `| zone | arm | ${cols.map((c) => c[1]).join(' | ')} | ${vcol} vs ${base[0]} |`, `|---|---|${cols.map(() => '---:').join('|')}|---|`);
    for (const z of [...SCROLL_ZONES, ...MORPH_ZONES]) {
      if (!arms.some(([, a]) => a.metrics[z]?.[cols[0][0]])) continue;
      for (const [n, a] of arms) {
        const mm = a.metrics[z] ?? {};
        lines.push(`| ${ZONE_LABEL[z]} | ${n} | ${cols.map(([k, , d]) => cell(mm[k], d)).join(' | ')} | ${n === base[0] ? '' : vs(base[1].metrics[z]?.[vcol], mm[vcol])} |`);
      }
    }
    lines.push('');
  }
  lines.push('#### Paint records after a morph ends (early: 0-500 ms after the tween end, late: 500-1000 ms)', '',
    `| morph | arm | early | late | early vs ${base[0]} |`, '|---|---|---:|---:|---|');
  for (const w of ['open', 'close']) {
    for (const [n, a] of arms) {
      const mm = a.metrics[w] ?? {};
      lines.push(`| ${ZONE_LABEL[w]} | ${n} | ${cell(mm.early, 0)} | ${cell(mm.late, 0)} | ${n === base[0] ? '' : vs(base[1].metrics[w]?.early, mm.early)} |`);
    }
  }
  lines.push('');
  return lines.join('\n');
}
