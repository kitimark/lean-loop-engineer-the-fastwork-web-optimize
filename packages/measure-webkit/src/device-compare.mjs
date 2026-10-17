// Reads phone count files (device-cli `counts --out`) and a Simulator determinism file (webkit-sim `v1-session-N.json`, raw
// passes) and tabulates per 500 px zone and in total: phone original, Simulator original, phone rewrite. Reporting only: the
// counts and zone sums come from reduce.mjs; no verdict is decided here (differences are shown with the run-to-run spread, the
// reading of "noise" is the lane's classify()).
import { zones, COUNT_TYPES } from './reduce.mjs';

const KEY = ['RecalculateStyles', 'Layout', 'Paint', 'Composite', 'FireAnimationFrame', 'TimerFire', 'EventDispatch'];
const idx = (t) => COUNT_TYPES.indexOf(t);
const stats = (xs) => ({ min: Math.min(...xs), max: Math.max(...xs), mean: +(xs.reduce((a, b) => a + b, 0) / xs.length).toFixed(2), n: xs.length });

/** Per-pass { total, zones } from a Simulator determinism file (raw passes). */
export const simPasses = (file) => file.passes.map((p) => ({
  total: p.scroll.reduced.total,
  zones: zones(p.scroll.ys, p.scroll.reduced.perStep, p.scroll.reduced.perStepPaintArea),
  census: p.census.map((c) => ({ requestedY: c.requestedY, layerCount: c.layerCount, memoryBytes: c.memoryBytes })),
}));

/** Per-pass { total, zones } from a phone counts file (reduced part). */
export const phonePasses = (file) => file.reduced.map((p) => ({ total: p.total, zones: p.zones, census: p.census }));

function column(passes, type) {
  const nz = Math.max(...passes.map((p) => p.zones.length));
  const per = Array.from({ length: nz }, (_, z) => stats(passes.map((p) => (type === 'paintArea' ? p.zones[z]?.paintArea ?? 0 : p.zones[z]?.counts[idx(type)] ?? 0))));
  const total = stats(passes.map((p) => (type === 'paintArea' ? p.zones.reduce((a, z) => a + z.paintArea, 0) : p.total[type])));
  return { per, total };
}

/** arms: { name: passes[] }. Returns { types: { type: { total: {arm: stats}, zones: [{y0, arm: stats}] } }, census: {...} }. */
export function compareArms(arms, types = KEY) {
  const out = { arms: Object.fromEntries(Object.entries(arms).map(([k, v]) => [k, v.length])), types: {}, census: {} };
  for (const t of [...types, 'paintArea']) {
    const cols = Object.fromEntries(Object.entries(arms).map(([k, v]) => [k, column(v, t)]));
    const nz = Math.max(...Object.values(cols).map((c) => c.per.length));
    out.types[t] = {
      total: Object.fromEntries(Object.entries(cols).map(([k, c]) => [k, c.total])),
      zones: Array.from({ length: nz }, (_, z) => ({ y0: z * 500, ...Object.fromEntries(Object.entries(cols).map(([k, c]) => [k, c.per[z] ?? null])) })),
    };
  }
  for (const [k, v] of Object.entries(arms)) {
    out.census[k] = v[0].census.map((c, s) => ({ requestedY: c.requestedY, layerCount: stats(v.map((p) => p.census[s].layerCount)), memoryBytes: stats(v.map((p) => p.census[s].memoryBytes)) }));
  }
  return out;
}

/** Counts file without the raw passes (raw timeline records stay local). */
export const stripCounts = ({ raw, ...rest }) => rest;

/** Frames files of one target, pooled: per-round summaries, the pooled summary over all reps, no timestamps. */
export function poolFrames(files, summarize) {
  const runs = files.flatMap((f) => f.runs);
  const { runs: _r, summary: _s, readouts: _o, ...head } = files[0];
  return {
    ...head, rounds: files.length, repsPerRound: files.map((f) => f.runs.length),
    readouts: files.flatMap((f) => f.readouts),
    perRound: files.map((f) => f.summary), summary: summarize(runs),
  };
}

/** Markdown: one table per count type (zone rows, one column per arm as mean [min-max]). */
export function compareMarkdown(cmp, types = KEY) {
  const arms = Object.keys(cmp.arms);
  const cell = (s) => (s ? `${s.mean} [${s.min}-${s.max}]` : '-');
  const lines = [`Arms (passes): ${arms.map((a) => `${a} (${cmp.arms[a]})`).join(', ')}. Cells: mean [min-max] over the passes.`, ''];
  for (const t of [...types, 'paintArea']) {
    lines.push(`### ${t}`, '', `| zone (px) | ${arms.join(' | ')} |`, `|---|${arms.map(() => '---').join('|')}|`);
    for (const z of cmp.types[t].zones) lines.push(`| ${z.y0} | ${arms.map((a) => cell(z[a])).join(' | ')} |`);
    lines.push(`| **total** | ${arms.map((a) => cell(cmp.types[t].total[a])).join(' | ')} |`, '');
  }
  return lines.join('\n');
}
