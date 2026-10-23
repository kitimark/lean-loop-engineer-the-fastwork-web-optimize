// The swap-window report decides every window and kind on its own (Lean `cell`) from synthetic captures.
import test from 'node:test';
import assert from 'node:assert/strict';
import { nominal, validAt, countCells, KINDS, PERIOD_US, PERIODS } from '../src/lag/swap.mjs';
import { windowCells, swapMd, swapPassesOf } from '../src/lag/swapreport.mjs';

/** A capture whose windows each hold `layout` Layout records and `paint` Paint records. */
function capture(layout, { paint = 1, shift = 0, drift = null } = {}) {
  const ws = nominal(shift, PERIODS);
  if (drift !== null) ws[drift] = [ws[drift][0], ws[drift][1] + 200000];
  const recs = ws.flatMap(([s]) => [...Array.from({ length: layout }, (_, i) => ['Layout', s + 1000 * i]), ...Array.from({ length: paint }, (_, i) => ['Paint', s + 500 + i])]);
  return { ws, valid: ws.map((_, k) => validAt(ws, k)), cells: countCells(ws, recs, KINDS) };
}
const pass = (fa, ca, fb, cb) => ({ captures: { 'faithful-a': fa, 'crop-a': ca, 'faithful-b': fb, 'crop-b': cb } });
const cellOf = (cells, phase, kind) => cells.find((c) => c.phase === phase && c.kind === kind);

test('a crop with no Layout in the swap windows wins every swap window on Layout and ties on Paint', () => {
  const passes = [pass(capture(13), capture(0), capture(12), capture(0)), pass(capture(13), capture(0), capture(13), capture(0))];
  const cells = windowCells(passes);
  for (let k = 0; k < PERIODS; k++) {
    assert.equal(cellOf(cells, `swap:${k}`, 'Layout').cell, 'win', `swap:${k}`);
    assert.equal(cellOf(cells, `swap:${k}`, 'Paint').cell, 'unresolved:overlap');
  }
  assert.equal(cellOf(cells, 'swap:0', 'Layout').crop.length, 4);
});

test('a drifted window is dropped and decided on its own', () => {
  const passes = [pass(capture(13), capture(0, { drift: 3 }), capture(13), capture(0))];
  const cells = windowCells(passes);
  assert.equal(cellOf(cells, 'swap:3', 'Layout').dropped, 1);
  assert.equal(cellOf(cells, 'swap:3', 'Layout').crop.length, 1);
  assert.equal(cellOf(cells, 'swap:3', 'Layout').cell, 'win');
  assert.equal(cellOf(cells, 'swap:2', 'Layout').dropped, 0);
  assert.equal(cellOf(cells, 'swap:4', 'Layout').dropped, 0);
});

test('a broken floor leaves the window unresolved, a failed capture leaves it without samples', () => {
  const broken = windowCells([pass(capture(13), capture(0), capture(30), capture(0))]);
  assert.equal(cellOf(broken, 'swap:0', 'Layout').cell, 'unresolved:floorBroken');
  const missing = windowCells([pass(capture(13), null, capture(13), null)]);
  assert.equal(cellOf(missing, 'swap:0', 'Layout').cell, 'unresolved:noSamples');
});

test('the rest windows are the control and the last window has no rest', () => {
  const cells = windowCells([pass(capture(13), capture(0), capture(13), capture(0))]);
  assert.equal(cellOf(cells, 'rest:0', 'Layout').cell, 'unresolved:overlap');
  assert.equal(cellOf(cells, `rest:${PERIODS - 1}`, 'Layout'), undefined);
  assert.equal(PERIOD_US, 1020000);
});

test('the table names every kind and the passes come out of the lag documents', () => {
  const docs = [{ passes: [{ cost: { swap: pass(capture(13), capture(0), capture(13), capture(0)) } }, { cost: {} }, {}] }];
  const passes = swapPassesOf(docs);
  assert.equal(passes.length, 1);
  const md = swapMd(windowCells(passes), ['run 1']);
  for (const k of KINDS) assert.ok(md.includes(`### ${k}`));
  assert.ok(md.includes('| swap:0 | 13 (n=1) | 13 (n=1) | 0 (n=2) | 0 | win |'));
});
