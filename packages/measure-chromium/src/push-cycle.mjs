import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { cmp, MIN_RUNS } from './offscreen.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const GOLDEN = join(here, '../../contracts/golden/measure/push-cycle.jsonl');
export const DWELLS = Object.freeze([300, 1000]);

export const SUM_KEYS = Object.freeze([
  'metric.RecalcStyleCount', 'metric.LayoutCount', 'trace.UpdateLayoutTree', 'trace.Layout', 'trace.Paint', 'trace.Layerize', 'trace.Commit',
  'trace.UpdateLayer', 'trace.RasterTask', 'trace.cc.Draw', 'trace.cc.Commit', 'trace.cc.Activate', 'trace.FireAnimationFrame',
  'trace.Layer.created', 'trace.Layer.deleted', 'raster.invalidationAreaPx', 'raster.invalidatedLayers',
]);
export const MAX_KEYS = Object.freeze(['census.layers', 'census.drawingLayers', 'census.drawingAreaPx', 'census.tiles', 'census.tilings']);

export const readGolden = (path = GOLDEN) => readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
export const planOf = (golden, dwellMs) => {
  const p = golden.find((g) => g.op === 'plan' && g.dwellMs === dwellMs);
  if (!p) throw new Error(`no plan for dwell ${dwellMs} ms in the golden`);
  return p;
};

export function profileOf(plan) {
  return {
    id: `push-cycle-d${plan.dwellMs}`,
    about: `${plan.n} pull-in/pull-out cycles at the page end, each its own touch: ${plan.dwellFrames} frames of dwell at the top and again at the bottom, ${plan.cycleLen} frames per cycle. Generated from the Lean plan (packages/contracts/golden/measure/push-cycle.jsonl); do not edit by hand.`,
    hz: 60,
    viewport: { width: 430, height: 775, dpr: 3, mobile: true, touch: true },
    pinnedDate: '2026-10-01T00:00:00+07:00',
    timezone: 'Asia/Bangkok',
    locale: 'en-US',
    seed: 4025,
    load: { quietFrames: 30, maxFrames: 900, prerollFrames: 60 },
    zoneHeightPx: 500,
    input: { mode: 'replay', unit: 'css-px', start: 'end', maxFrames: plan.endFrame, strokes: plan.strokes },
    segments: [{ name: 'rest', dyPerFrame: 0, frames: 10 }, { name: 'replay', until: 'script' }, { name: 'tail', dyPerFrame: 0, frames: 30 }],
  };
}
export const profileText = (plan) => `${JSON.stringify(profileOf(plan))}\n`;

const num = (x) => (typeof x === 'number' ? x : 0);

export function windowSums(frames, plan) {
  const replay = frames.filter((f) => f.phase === 'replay');
  const half = 24 + plan.dwellFrames;
  const cut = (lo, hi) => {
    const fs = replay.slice(lo, hi);
    const sum = {}, max = {};
    for (const k of SUM_KEYS) sum[k] = fs.reduce((a, f) => a + num(f.counts?.[k]), 0);
    for (const k of MAX_KEYS) max[k] = fs.reduce((a, f) => Math.max(a, num(f.counts?.[k])), 0);
    return { frames: fs.length, ...sum, ...max };
  };
  return plan.windows.map(([a, b], k) => ({ k, open: cut(a, a + half), close: cut(a + half, b), all: cut(a, b) }));
}

export const perRun = (runs, plan) => runs.map((r) => windowSums(r.counts.frames, plan));

const spread = (xs) => [Math.min(...xs), Math.max(...xs)];
const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; };

export function armTable(windowsPerRun, half = 'open') {
  const keys = [...SUM_KEYS, ...MAX_KEYS];
  const n = windowsPerRun[0]?.length ?? 0;
  const enough = windowsPerRun.length >= MIN_RUNS;
  return keys.map((key) => {
    const col = (k) => windowsPerRun.map((w) => w[k][half][key]);
    const first = n > 0 ? spread(col(0)) : [0, 0];
    return {
      key,
      cycles: Array.from({ length: n }, (_, k) => ({ k, median: median(col(k)), spread: spread(col(k)), vs0: k === 0 ? 'base' : enough ? cmp(0, first, spread(col(k))) : 'n/a' })),
    };
  });
}

export function armOf(dirName) {
  const m = /^chromium-counts-(.+)-r?(\d+)$/.exec(dirName);
  return m ? { arm: m[1], run: Number(m[2]) } : null;
}

export function readRuns(dir) {
  const arms = new Map();
  for (const d of readdirSync(dir).sort()) {
    const a = armOf(d);
    const f = join(dir, d, 'counts.json');
    if (!a || !existsSync(f)) continue;
    if (!arms.has(a.arm)) arms.set(a.arm, []);
    arms.get(a.arm).push({ label: `${a.arm}-${a.run}`, counts: JSON.parse(readFileSync(f, 'utf8')) });
  }
  return arms;
}

export function reportMd(arms, plan, half = 'open') {
  const out = [`# Push cycles in Chromium (counts, virtual time), dwell ${plan.dwellMs} ms, ${plan.n} cycles, ${half} half of each window`, '',
    `Cycle k against cycle 0 by the spread rule of Fw.Measure.Offscreen (\`more\`: the whole spread of k lies above the spread of cycle 0; \`n/a\`: fewer than ${MIN_RUNS} runs).`, ''];
  const json = {};
  for (const [arm, runs] of arms) {
    const t = armTable(perRun(runs, plan), half);
    json[arm] = t;
    out.push(`## ${arm} (${runs.length} runs)`, '', `| Counter | ${Array.from({ length: plan.n }, (_, k) => `k=${k}`).join(' | ')} |`, `|---|${'---|'.repeat(plan.n)}`);
    for (const r of t) {
      if (r.cycles.every((c) => c.median === 0 && c.vs0 !== 'more')) continue;
      out.push(`| ${r.key} | ${r.cycles.map((c) => `${c.median}${c.vs0 === 'more' || c.vs0 === 'less' ? ` (${c.vs0})` : ''}`).join(' | ')} |`);
    }
    out.push('');
  }
  return { md: out.join('\n'), json };
}

function main(argv) {
  const [cmd, ...rest] = argv;
  const opt = (name, d) => { const i = rest.indexOf(name); return i >= 0 ? rest[i + 1] : d; };
  if (cmd === 'profiles') {
    const dir = opt('--dir', join(here, '../profiles'));
    const g = readGolden();
    for (const d of DWELLS) { const p = profileOf(planOf(g, d)); writeFileSync(join(dir, `${p.id}.json`), `${JSON.stringify(p)}\n`); console.log(`wrote ${p.id}`); }
  } else if (cmd === 'report') {
    const dwell = Number(opt('--dwell', '300'));
    const half = opt('--half', 'open');
    const { md, json } = reportMd(readRuns(rest[0]), planOf(readGolden(), dwell), half);
    if (opt('--md')) writeFileSync(opt('--md'), md); else console.log(md);
    if (opt('--json')) writeFileSync(opt('--json'), `${JSON.stringify(json)}\n`);
  } else {
    console.error('usage: push-cycle.mjs profiles [--dir d] | report <dir> [--dwell 300] [--half open|close|all] [--md f] [--json f]');
    process.exitCode = 2;
  }
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main(process.argv.slice(2));
