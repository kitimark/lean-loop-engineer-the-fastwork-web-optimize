// The cost-counter reductions agree with the Lean golden (Fw.Measure.WkCost, golden/measure/wkcost.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { slotOf, histBin, deltas, cadence, sumsOf, layerSums, morphEnd, early, late, morphZone, scrollZone, TWEEN_US, EARLY_US, LATE_US, HIST_EDGES, nOver, nSkip } from '../src/lag/cost.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/wkcost.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every golden kind has lines', () => {
  for (const k of ['const', 'slot', 'bin', 'frames', 'cost', 'layers', 'post', 'morphZone', 'scrollZone']) assert.ok(of(k).length > 0, k);
});

test('constants come from the golden', () => {
  const [c] = of('const');
  assert.deepEqual([TWEEN_US, EARLY_US, LATE_US, [...HIST_EDGES]], [c.tweenUs, c.earlyUs, c.lateUs, c.histEdges]);
});

test('display slot and histogram bin of an interval', () => {
  for (const g of of('slot')) assert.equal(slotOf(g.d), g.slot, `slot ${g.d}`);
  for (const g of of('bin')) assert.equal(histBin(g.d), g.bin, `bin ${g.d}`);
});

test('deltas, cadence counts and histograms per zone', () => {
  for (const g of of('frames')) {
    assert.deepEqual(deltas(g.frames), g.deltas);
    for (const z of g.zones) assert.deepEqual(cadence(z.zone, g.frames), z, z.zone);
  }
});

test('theorem: an interval over two display slots is a skipped slot (and not the converse)', () => {
  for (const g of of('frames')) for (const z of g.zones) assert.ok(nOver(33333, z.zone, deltas(g.frames)) <= nSkip(z.zone, deltas(g.frames)));
  const c = of('frames').find((g) => g.frames.length === 3 && g.frames[2][0] === 36000);
  assert.ok(nOver(25000, 's', deltas(c.frames)) === 1 && nSkip('s', deltas(c.frames)) === 0, 'a 26 ms interval inside one slot is over 25 ms and no skip');
});

test('Paint against Composite per zone', () => {
  for (const g of of('cost')) assert.deepEqual(sumsOf(g.zone, g.costs), { frames: g.frames, paintUs: g.paintUs, compUs: g.compUs, bound: g.bound });
});

test('new and resized layers between reads', () => {
  for (const g of of('layers')) {
    const snaps = g.snaps;
    for (const z of g.zones) assert.deepEqual(layerSums(z.zone, snaps), { reads: z.reads, fresh: z.fresh, resized: z.resized }, z.zone);
  }
});

test('paints after a morph ends, early and late window', () => {
  for (const g of of('post')) {
    assert.equal(morphEnd(g.push), g.end);
    assert.equal(early(g.end, g.ts), g.early);
    assert.equal(late(g.end, g.ts), g.late);
  }
});

test('morph and scroll zones', () => {
  for (const g of of('morphZone')) assert.equal(morphZone(g.po, g.pc, g.t), g.zone, `t ${g.t}`);
  for (const g of of('scrollZone')) assert.equal(scrollZone(g.vh, g.maxY, g.y), g.zone, `y ${g.y}`);
});
