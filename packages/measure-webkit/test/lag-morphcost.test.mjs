import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { rawPF, normPF, cellRows, outcome, armsOutcome, sumsLine, passJson, passSums } from '../src/lag/morphcost.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/wkcost.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);
const sums = ([frames, paintUs, compUs, bound]) => ({ frames, paintUs, compUs, bound });
const pass = (p) => ({ zones: p.zones.map(([z, s]) => [z, sums(s)]), calm: sums(p.calm) });

test('every morph cost golden kind has lines', () => {
  for (const k of ['morphNorm', 'morphCells', 'morphOutcome']) assert.ok(of(k).length > 0, k);
});

test('raw and normalized per-frame cost of a zone', () => {
  for (const g of of('morphNorm')) {
    assert.deepEqual(rawPF(g.metric, sums(g.w)), g.raw);
    assert.deepEqual(normPF(g.metric, sums(g.w), sums(g.b)), g.norm);
  }
});

test('cells and outcome of two arms', () => {
  for (const g of of('morphCells')) {
    const rows = cellRows(g.base.map(pass), g.flag.map(pass));
    assert.deepEqual(rows, g.cells);
    assert.equal(outcome(rows.map((r) => r[4])), g.outcome);
  }
});

test('outcome of a list of cell verdicts', () => {
  for (const g of of('morphOutcome')) assert.equal(outcome(g.cells), g.outcome, JSON.stringify(g.cells));
});

test('the recorded cost run is unresolved, and a slower runner alone is not a loss', () => {
  const [real, real6, win, loss, confound, mixed] = of('morphCells');
  assert.deepEqual([real.base.length, real6.base.length, real6.flag.length], [2, 6, 6]);
  assert.ok(real6.cells.every((r) => r[4] === 'overlap'), 'six passes per arm: no cell separates the arms');
  assert.equal(real.outcome, 'overlap');
  assert.equal(real6.outcome, 'overlap');
  assert.deepEqual([win.outcome, loss.outcome, confound.outcome, mixed.outcome], ['win', 'loss', 'overlap', 'mixed']);
  assert.ok(confound.cells.every((r) => r[2] === 'higher' && r[3] === 'overlap' && r[4] === 'overlap'), 'raw reads higher, normalized does not');
});

const sumsFile = readFileSync(join(here, '../../contracts/golden/measure/wkcost-sums.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('the committed reduced sums of both recorded runs give overlap in all 8 cells', () => {
  assert.deepEqual(sumsFile.map((l) => l.run), ['39903977820,39903974246', '39915136431,39915146774']);
  assert.deepEqual(sumsFile.map((l) => [l.base.length, l.flag.length]), [[2, 2], [6, 6]]);
  for (const l of sumsFile) {
    assert.equal(l.kind, 'morphRunSums');
    const rows = cellRows(l.base.map(pass), l.flag.map(pass));
    assert.equal(rows.length, 8);
    assert.ok(rows.every((r) => r[4] === 'overlap'), l.run);
    assert.equal(outcome(rows.map((r) => r[4])), 'overlap');
  }
});

test('morph-verdict emits the per-pass sums in the committed shape', () => {
  const costs = (p, c) => [['idle', p, c], ['open', 2 * p, c]];
  const arm = [1, 2].map((k) => ({ cost: { morph: { costs: costs(10 * k, 30) }, scroll: { costs: [['scroll-calm', 5, 7]] } } }));
  const res = armsOutcome(arm, arm);
  assert.deepEqual(res.base, arm.map((p) => passJson(passSums(p.cost))));
  assert.deepEqual(res.base[0].zones[0], ['idle', [1, 10, 30, 1]]);
  assert.deepEqual(res.base[0].calm, [1, 5, 7, 1]);
  assert.deepEqual(JSON.parse(sumsLine('1,2', res)), { kind: 'morphRunSums', run: '1,2', base: res.base, flag: res.flag });
});
