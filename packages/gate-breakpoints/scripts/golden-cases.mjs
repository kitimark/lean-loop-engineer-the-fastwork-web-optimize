// Builds packages/contracts/golden/gate/cases.json, the inputs of the gate's golden vectors, from saved gate runs.
// Each case is one fwcore request built from saved raw records (with the same request builders summary.mjs uses), plus
// `saved`: what the saved summary.json of that run (written by the JavaScript rule before it moved to Lean) reported
// for the same states. Lean answers the cases and checks its reply agrees with `saved`
// (lean/Fw/Wire/GateGolden.lean; `cd lean && lake env lean --run scripts/GateGolden.lean`).
// Run once by hand when the request shape changes; the saved runs are local (out/ is not committed):
//   node scripts/golden-cases.mjs <run dir> <run dir with failures> <run dir with failures, later>
// e.g. out/run-a (all pass), a run where a part's anchors were absent (count missing, style differ).
// Cases are narrowed to a few parts where the saved verdict rows are per part (they are: a part's row and compared
// count depend on that part only; the matchMedia rows on no part), which keeps the file small.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadAnchors, loadGen, expectFor } from '../src/spec.mjs';
import { context, stateRequest, staleRequest } from '../src/verdict.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const OUT = join(ROOT, 'packages/contracts/golden/gate/cases.json');
const [dirA, dirB, dirC] = process.argv.slice(2);
if (!dirC) throw new Error('usage: node scripts/golden-cases.mjs <run dir> <run dir> <run dir>');

const anchors = loadAnchors();
const { gen } = loadGen();
const deviceEdges = gen.edgePairs.deviceWidth;
const ALL = Object.keys(anchors.parts);
const SMALL = ['engine.scroll', 'nav.hitTest', 'hero.exit'];
const TRUTH_ROWS = ['matchMedia orig=rewrite', 'matchMedia =Lean', 'matchMedia legacy text'];

const load = (dir, engine) => ({
  run: JSON.parse(readFileSync(join(dir, `${engine}.json`), 'utf8')),
  sum: JSON.parse(readFileSync(join(dir, 'summary.json'), 'utf8')).engines[engine],
});
const ctxOf = (run, parts) => context({
  anchors: { style: anchors.style, parts: Object.fromEntries(parts.map((p) => [p, anchors.parts[p]])) }, parts, deviceEdges,
  props: Object.fromEntries(parts.map((p) => [p, run.header.props[p]])),
});
const rowsOf = (verdicts, parts) => [...TRUTH_ROWS, ...parts].map((r) => [r, verdicts[r]]);

/** A gate.state case over saved probes: saved = what summary.json reported for them. */
function probeCase(name, { run, sum }, ids, parts) {
  const recs = ids.map((id) => run.probes.find((p) => p.id === id));
  const states = recs.map((rec) => {
    const g = gen.matrix.probes.find((p) => p.id === rec.id);
    return { requested: rec.env, orig: rec.orig, rewrite: rec.rewrite, expect: g.expect, expectNeutral: g.expectNeutral };
  });
  const saved = ids.map((id) => {
    const row = sum.probes.find((p) => p.id === id);
    return { achieved: row.achieved, dev: row.deviations, rows: rowsOf(row.verdicts, parts), truthCounts: row.truthCounts, compared: parts.map((p) => [p, row.compared[p]]) };
  });
  return { name, request: stateRequest(ctxOf(run, parts), states), saved: { states: saved } };
}

/** A gate.state case over the stops of a saved sweep. */
function sweepCase(name, { run, sum }, j, stops, parts) {
  const sw = run.sweeps[j], row = sum.sweeps[j];
  const states = stops.map((i) => {
    const v = expectFor(gen, sw.stops[i]);
    return { requested: sw.stops[i], orig: sw.orig[i], rewrite: sw.rewrite[i], expect: v?.expect, expectNeutral: v?.expectNeutral };
  });
  const saved = stops.map((i) => ({ achieved: row.stops[i].achieved, rows: rowsOf(row.stops[i].verdicts, parts) }));
  return { name, request: stateRequest(ctxOf(run, parts), states), saved: { states: saved } };
}

/** A gate.stale case: a sweep's final state against the fresh load, per arm. The saved counts sum over every part,
 *  so a narrowed case has no `saved` (the full counts agree in the byte-identical summaries). */
function staleCase(name, { run }, j, parts) {
  const sw = run.sweeps[j], last = sw.stops.length - 1;
  const pairs = ['orig', 'rewrite'].map((site) => ({ after: sw[site][last], fresh: sw.freshFinal[site] }));
  return { name, request: staleRequest(ctxOf(run, parts), pairs) };
}

/** A gate.tally case: the saved table cells of some rows, from the saved per-probe and per-stop verdicts. */
function tallyCase(name, { run, sum }, rows) {
  const blocks = gen.matrix.blocks.map((b) => b.id);
  const cells = [], saved = [];
  for (const row of rows) {
    for (const b of blocks) {
      cells.push({ verdicts: sum.probes.filter((p) => p.block === b).map((p) => p.verdicts[row]), block: true });
      saved.push(sum.table[row][b]);
    }
    for (const s of sum.sweeps) {
      cells.push({ verdicts: s.stops.map((x) => x.verdicts[row]), block: false });
      saved.push(sum.table[row][`sweep:${s.id}`]);
    }
  }
  return { name, request: { op: 'gate.tally', cells }, saved: { cells: saved } };
}

const a = load(dirA, 'chromium'), aw = load(dirA, 'playwright-webkit');
const b = load(dirB, 'chromium'), c = load(dirC, 'playwright-webkit');
const notAchievedW = aw.sum.probes.find((p) => !p.achieved).id;
const cases = [
  probeCase('chromium, every part: a narrow desktop probe where every row passes', a, ['desk-319'], ALL),
  probeCase('chromium: a fractional width the engine does not deliver (env not achieved: the Lean row is not comparable)', a, ['fractional-gaps-600.5'], SMALL),
  probeCase(`webkit: env not achieved (${notAchievedW})`, aw, [notAchievedW], SMALL),
  sweepCase('webkit: the second stop of a live-resize sweep', aw, 0, [1], SMALL),
  probeCase('chromium, an earlier rewrite: anchors absent on one arm (count missing) and a style that differs', b, ['desk-319', 'desk-400'], SMALL),
  probeCase('webkit, a later rewrite: anchors absent on one arm', c, ['desk-400'], SMALL),
  staleCase('chromium, an earlier rewrite: sweep hysteresis counts (anchors absent after the sweep)', b, 1, SMALL),
  tallyCase('chromium: table cells of three rows (blocks and sweeps)', a, ['matchMedia =Lean', 'nav.hitTest', 'hero.countdown']),
  tallyCase('chromium, an earlier rewrite: table cells with failing probes', b, ['engine.scroll', 'hero.exit']),
];
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(cases) + '\n');
for (const x of cases) console.log(JSON.stringify(x).length, x.name);
console.log(`golden-cases: ${cases.length} cases, ${JSON.stringify(cases).length} bytes -> ${OUT}`);
