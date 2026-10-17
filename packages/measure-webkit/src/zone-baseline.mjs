// Per-zone baseline of the original in the WebKit Simulator lane (task zone-baselines-webkit). GLUE ONLY: the zone sums
// are Lean's (fwcore measure.webkit.zones), the cross-run reduction, the class lookup, lo/hi/base and the drift lists
// are Lean's (fwcore measure.zoneBaseline, Fw.Measure.ZoneBaseline). This file reads `determinism --out` session files,
// reshapes zone rows into the zone records the baseline op takes (no decision), and writes the baseline file.
//
//   node src/zone-baseline.mjs --sessions v1-session-1.json,v2-session-1.json,... --out <results dir>
//        [--classes packages/measure-webkit/classes/webkit-sim-v1.json] [--run-id <CI run>] [--check]
//
// Runs = every pass of every session (one fresh page load each). The op is called twice with the same runs: once with
// the zone-level class of each type (zones, detDrift) and once with the whole-run class (totals, detDriftTotals), because
// the WebKit table classes a type per level and the op takes one table per call.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fwcoreCall } from './handoff.mjs';
import { COUNT_TYPES } from './reduce.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const args = process.argv.slice(2);
const arg = (f, d) => { const i = args.indexOf(f); return i < 0 ? d : args[i + 1]; };
const sessionFiles = (arg('--sessions') ?? '').split(',').filter(Boolean);
const out = arg('--out');
if (!sessionFiles.length || !out) { console.error('usage: zone-baseline.mjs --sessions a.json,b.json,... --out <dir> [--classes f] [--run-id id] [--check]'); process.exit(2); }
const classesPath = resolve(arg('--classes', join(ROOT, 'packages/measure-webkit/classes/webkit-sim-v1.json')));
const sha = (b) => createHash('sha256').update(b).digest('hex');
const TYPES = [...COUNT_TYPES, 'paintArea'];

const sessions = sessionFiles.map((f) => { const text = readFileSync(f); return { name: basename(f, '.json'), sha: sha(text), passes: JSON.parse(text).passes }; });
const classesText = readFileSync(classesPath);
const table = JSON.parse(classesText);
if (table.schema !== 'fw.webkit.classes/1') throw new Error(`${classesPath}: not a fw.webkit.classes/1 table`);
const frozen = (level) => Object.fromEntries(TYPES.map((t) => [t, { class: table.byLevel[level][t].class, k: 0, t: 0 }])); // k, t unused by the op

// 1. zone sums per pass (Lean measure.webkit.zones), reshaped to zone records (index ranges and scroll span from ys)
const runs = [];
const reqs = [];
for (const s of sessions) s.passes.forEach((p, i) => reqs.push({ id: reqs.length, op: 'measure.webkit.zones', ys: p.scroll.ys, perStep: p.scroll.reduced.perStep, perStepPaintArea: p.scroll.reduced.perStepPaintArea, zonePx: 500 }));
const zrep = await fwcoreCall(reqs);
let r = 0;
for (const s of sessions) {
  s.passes.forEach((p, i) => {
    const ys = p.scroll.ys;
    let next = 0;
    const zones = zrep[r].zones.map((z) => {
      const first = next; next += z.steps;
      const sums = Object.fromEntries(COUNT_TYPES.map((t, j) => [t, z.counts[j]]).concat([['paintArea', z.paintArea]]));
      return { id: `z${String(z.zone).padStart(2, '0')}`, frames: z.steps, scrolledPx: z.steps ? Math.round(ys[next - 1] - ys[first]) : 0, firstFrame: first, lastFrame: z.steps ? next - 1 : first, sums };
    });
    runs.push({ id: `${s.name}-p${i + 1}`, zones });
    r++;
  });
}

const zonesFile = {
  schema: 'fw.zonebaseline.webkit/1',
  note: 'Per-pass per-500px-zone sums of the WebKit Simulator scroll counts (Lean measure.webkit.zones). Zone ids z00.. by floor(y/500); frames = scroll steps; sums include paintArea.',
  engine: 'webkit-sim', target: 'original', runId: arg('--run-id') ?? null, zonePx: 500,
  sessions: sessions.map((s) => ({ name: s.name, sessionSha256: s.sha, passes: s.passes.length })),
  runs,
};
const zonesText = JSON.stringify(zonesFile, null, 1) + '\n';

// 2. the baseline (Lean measure.zoneBaseline), twice
const [zb, tb] = await fwcoreCall([
  { id: 0, op: 'measure.zoneBaseline', classes: frozen('zone'), runs },
  { id: 1, op: 'measure.zoneBaseline', classes: frozen('total'), runs },
]);
for (const x of [zb, tb]) if (x.error !== undefined) throw new Error(`fwcore: ${x.error}`);
const baseline = {
  schema: 'fw.zonebaseline.webkit.baseline/1',
  note: 'Cross-run baseline per 500px zone and count type (zones, detDrift: zone-level class) and whole-run totals (totals, detDriftTotals: whole-run class), ' +
    'from fwcore measure.zoneBaseline (Lean Fw.Measure.ZoneBaseline). class = the WebKit table class at that level; perRun in run order; base = the observed ' +
    'value at sorted index floor((n-1)/2). Only deterministic and stable zone cells are gateable; quarantined cells are model-check-only and carry a noise band (lo..hi). ' +
    'Counts are work, not milliseconds; nothing here is phone time.',
  source: { zonesSha256: sha(zonesText), runId: zonesFile.runId, sessions: zonesFile.sessions.map((s) => s.name) },
  classTable: { file: relative(ROOT, classesPath), sha256: sha(classesText), sessions: table.sessions, passesPerSession: table.passesPerSession },
  target: 'original', engine: 'webkit-sim',
  runs: zb.runs, zones: zb.zones, zoneTally: zb.tally,
  detDrift: zb.detDrift,
  totals: tb.totals, totalTally: tb.tally, detDriftTotals: tb.detDriftTotals,
  zoneNoiseNote: 'zones[].types[t] = {class, perRun, lo, hi, base} for the zone-level class table; totals[t] uses the whole-run class table.',
};
const baselineText = JSON.stringify(baseline, null, 1) + '\n';

const zp = join(out, 'original.zones.json');
const bp = join(out, 'original.baseline.json');
if (args.includes('--check')) {
  for (const [p, t] of [[zp, zonesText], [bp, baselineText]]) {
    if (!existsSync(p) || readFileSync(p, 'utf8') !== t) { console.error(`DIFFERS: ${p}`); process.exit(1); }
  }
  console.log(`identical: ${zp}, ${bp}`);
} else {
  mkdirSync(out, { recursive: true });
  writeFileSync(zp, zonesText);
  writeFileSync(bp, baselineText);
  console.log(`wrote ${zp} and ${bp}: ${runs.length} runs, ${zb.zones.length} zones, zone tally ${JSON.stringify(zb.tally)}, detDrift ${zb.detDrift.length}, detDriftTotals ${tb.detDriftTotals.length}`);
}
