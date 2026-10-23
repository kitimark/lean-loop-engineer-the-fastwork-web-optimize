// The swap-window schedule agrees with the Lean golden (Fw.Measure.SwapWindow, golden/measure/wkcost.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { REST_US, SWAP_US, PERIOD_US, PERIODS, TOL_US, DEADLINE_US, FRAMES_60, nominal, validAt, phaseOf, countCells, cell } from '../src/lag/swap.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/wkcost.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every swap golden kind has lines', () => {
  for (const k of ['swapConst', 'swapNominal', 'swapPhase', 'swapCount', 'swapCell', 'swapPredict']) assert.ok(of(k).length > 0, k);
});

test('constants come from the golden and add up', () => {
  const [c] = of('swapConst');
  assert.deepEqual([REST_US, SWAP_US, PERIOD_US, PERIODS, TOL_US, DEADLINE_US, FRAMES_60], [c.restUs, c.swapUs, c.periodUs, c.periods, c.tolUs, c.deadlineUs, c.frames60]);
  assert.equal(REST_US + SWAP_US, PERIOD_US);
  assert.equal(DEADLINE_US, PERIODS * PERIOD_US + SWAP_US + PERIOD_US);
});

test('nominal windows and their validity', () => {
  for (const g of of('swapNominal')) {
    const ws = nominal(g.s0, g.n);
    assert.deepEqual(ws, g.wins);
    assert.deepEqual(ws.map((_, k) => validAt(ws, k)), g.valid);
  }
});

test('theorem: a loop that starts within a period ends all windows before the deadline', () => {
  for (const s0 of [0, 1, PERIOD_US / 2, PERIOD_US]) assert.ok(nominal(s0, PERIODS).at(-1)[1] < DEADLINE_US, `s0 ${s0}`);
});

test('phase of a time, and validity of every window and one past the end', () => {
  for (const g of of('swapPhase')) {
    assert.deepEqual(g.ts.map((t) => phaseOf(g.wins, t)), g.phases);
    assert.deepEqual(Array.from({ length: g.wins.length + 1 }, (_, k) => validAt(g.wins, k)), g.valid);
  }
});

test('counts per phase and kind', () => {
  for (const g of of('swapCount')) assert.deepEqual(countCells(g.wins, g.recs, ['Layout', 'Paint', 'Composite']), g.cells);
});

test('theorem: a record on a window start is in the swap and on its stop in the rest', () => {
  const ws = nominal(100, 3);
  assert.equal(phaseOf(ws, 100), 'swap:0');
  assert.equal(phaseOf(ws, 100 + SWAP_US), 'rest:0');
  assert.equal(phaseOf(ws, ws[2][1]), 'outside');
});

test('verdict of one window and one event kind', () => {
  for (const g of of('swapCell')) assert.equal(cell(g.a1, g.a2, g.crop, g.dropped), g.cell, JSON.stringify([g.a1, g.a2, g.crop]));
});

test('the model predicts 13 Layout frames per faithful swap and none for the crop', () => {
  const [p] = of('swapPredict');
  assert.deepEqual([p.faithful, p.crop], [FRAMES_60, 0]);
});
