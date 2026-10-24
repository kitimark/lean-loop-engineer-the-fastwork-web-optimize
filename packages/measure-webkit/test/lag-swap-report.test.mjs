import test from 'node:test';
import assert from 'node:assert/strict';
import { nominal, validAt, countCells, KINDS, PERIOD_US, PERIODS, SWAP_US } from '../src/lag/swap.mjs';
import { windowCells, swapMd, swapPassesOf, jobKey } from '../src/lag/swapreport.mjs';

function capture(layout, { paint = 1, shift = 0, drift = null, rest = null } = {}) {
  const ws = nominal(shift, PERIODS);
  if (drift !== null) ws[drift] = [ws[drift][0], ws[drift][1] + 200000];
  const recs = ws.flatMap(([s], k) => [...Array.from({ length: layout }, (_, i) => ['Layout', s + 1000 * i]), ...Array.from({ length: paint }, (_, i) => ['Paint', s + 500 + i]),
    ...Array.from({ length: typeof rest === 'function' ? rest(k) : (rest ?? 0) }, (_, i) => ['Layout', s + SWAP_US + 1000 * i])]);
  return { ws, valid: ws.map((_, k) => validAt(ws, k)), cells: countCells(ws, recs, KINDS) };
}
const pass = (fa, ca, fb, cb, job = undefined) => ({ ...(job ? { job } : {}), captures: { 'faithful-a': fa, 'crop-a': ca, 'faithful-b': fb, 'crop-b': cb } });
const cellOf = (cells, phase, kind, bg = 'all') => cells.find((c) => c.phase === phase && c.kind === kind && c.bg === bg);
const times = (n, f) => Array.from({ length: n }, f);

test('a crop with no Layout in the swap windows wins every swap window on Layout and ties on Paint', () => {
  const passes = [pass(capture(13), capture(0), capture(12), capture(0)), pass(capture(13), capture(0), capture(13), capture(0)), pass(capture(12), capture(0), capture(13), capture(0))];
  const cells = windowCells(passes);
  for (let k = 0; k < PERIODS; k++) {
    assert.equal(cellOf(cells, `swap:${k}`, 'Layout').cell, 'win', `swap:${k}`);
    assert.equal(cellOf(cells, `swap:${k}`, 'Paint').cell, 'unresolved:overlap');
  }
  assert.equal(cellOf(cells, 'swap:0', 'Layout').crop.length, 6);
});

test('a drifted window is dropped and decided on its own', () => {
  const passes = times(3, () => pass(capture(13), capture(0, { drift: 3 }), capture(13), capture(0)));
  const cells = windowCells(passes);
  assert.equal(cellOf(cells, 'swap:3', 'Layout').dropped, 3);
  assert.equal(cellOf(cells, 'swap:3', 'Layout').crop.length, 3);
  assert.equal(cellOf(cells, 'swap:3', 'Layout').cell, 'win');
  assert.equal(cellOf(cells, 'swap:2', 'Layout').dropped, 0);
  assert.equal(cellOf(cells, 'swap:4', 'Layout').dropped, 0);
});

test('a broken floor leaves the window unresolved, a failed capture leaves it without samples', () => {
  const broken = windowCells(times(3, () => pass(capture(13), capture(0), capture(30), capture(0))));
  assert.equal(cellOf(broken, 'swap:0', 'Layout').cell, 'unresolved:floorBroken');
  const missing = windowCells(times(3, () => pass(capture(13), null, capture(13), null)));
  assert.equal(cellOf(missing, 'swap:0', 'Layout').cell, 'unresolved:noSamples');
});

test('the rest windows are the control and the last window has no rest', () => {
  const cells = windowCells(times(3, () => pass(capture(13), capture(0), capture(13), capture(0))));
  assert.equal(cellOf(cells, 'rest:0', 'Layout').cell, 'unresolved:overlap');
  assert.equal(cellOf(cells, `rest:${PERIODS - 1}`, 'Layout'), undefined);
  assert.equal(PERIOD_US, 1020000);
});

test('the table names every kind and the passes come out of the lag documents', () => {
  const docs = [{ passes: [...times(3, () => ({ cost: { swap: pass(capture(13), capture(0), capture(13), capture(0)) } })), { cost: {} }, {}] }];
  const passes = swapPassesOf(docs);
  assert.equal(passes.length, 3);
  const md = swapMd(windowCells(passes), ['run 1']);
  for (const k of KINDS) assert.ok(md.includes(`### ${k}`));
  assert.ok(md.includes('| swap:0 | 13 (n=3) | 13 (n=3) | 0 (n=6) | 0 | win |'));
});

test('fewer than three samples in a faithful slot leave a cell unresolved, even when the crop is far below', () => {
  for (const n of [1, 2]) {
    const cells = windowCells(times(n, () => pass(capture(13), capture(0), capture(13), capture(0))));
    for (let k = 0; k < PERIODS; k++) assert.equal(cellOf(cells, `swap:${k}`, 'Layout').cell, 'unresolved:fewSamples', `${n} passes swap:${k}`);
  }
  const three = windowCells(times(3, () => pass(capture(13), capture(0), capture(13), capture(0))));
  assert.equal(cellOf(three, 'swap:0', 'Layout').cell, 'win');
});

test('every sample carries the job and pass that took it, parallel to its value', () => {
  const j = (vm, p) => ({ run: '77', attempt: '1', vm, pass: p });
  const passes = [pass(capture(13), capture(0), capture(13), capture(0), j('r1', 1)), pass(capture(13), capture(0), capture(13), capture(0), j('r2', 1)), pass(capture(13), capture(0), capture(13), capture(0), { ...j('r3', 2), jobId: '555' })];
  const c = cellOf(windowCells(passes), 'swap:0', 'Layout');
  assert.deepEqual(c.a1Job, ['77.1/r1/p1/a', '77.1/r2/p1/a', '555/p2/a']);
  assert.deepEqual(c.a2Job, ['77.1/r1/p1/b', '77.1/r2/p1/b', '555/p2/b']);
  assert.deepEqual(c.cropJob, ['77.1/r1/p1/a', '77.1/r1/p1/b', '77.1/r2/p1/a', '77.1/r2/p1/b', '555/p2/a', '555/p2/b']);
  assert.equal(c.crop.length, c.cropJob.length);
  assert.equal(new Set(c.cropJob).size, c.cropJob.length, 'no two samples share a key');
  assert.equal(jobKey({}, 'a'), 'unknown/p?/a');
});

test('the background of a swap window comes from its rest windows, and the idle and busy cells keep only matching samples', () => {
  const busy = (k) => (k === 1 || k === 2 ? 48 : 5);
  const mk = () => pass(capture(13, { rest: busy }), capture(3, { rest: busy }), capture(13, { rest: busy }), capture(3, { rest: busy }));
  const passes = times(3, mk);
  const all = windowCells(passes);
  const swap1 = cellOf(all, 'swap:1', 'Layout');
  assert.deepEqual([...new Set(swap1.cropBg)], ['mixed'], 'rest 0 is idle, rest 1 is busy');
  assert.deepEqual([...new Set(cellOf(all, 'swap:2', 'Layout').cropBg)], ['busy']);
  assert.deepEqual([...new Set(cellOf(all, 'swap:5', 'Layout').cropBg)], ['idle']);
  assert.equal(cellOf(all, 'swap:5', 'Layout', 'idle').crop.length, 6);
  assert.equal(cellOf(all, 'swap:2', 'Layout', 'idle').crop.length, 0);
  assert.equal(cellOf(all, 'swap:2', 'Layout', 'busy').crop.length, 6);
  assert.equal(cellOf(all, 'rest:0', 'Layout', 'idle'), undefined);
  assert.equal(cellOf(all, 'swap:5', 'Composite', 'idle'), undefined);
});

test('the report prints the measured crop minimum next to the model line', () => {
  const md = swapMd(windowCells(times(3, () => pass(capture(13), capture(3), capture(13), capture(3)))), ['run 1']);
  assert.ok(md.includes('the crop none.'));
  assert.ok(md.includes('Measured (the crop, Layout rows in a swap window, 48 samples): minimum 3, median 3'));
  assert.ok(md.includes('Cells need at least 3 samples'));
});

test('a diagnostic capture is a row of the report list and prints its series', () => {
  const diag = { arm: 'crop', bucketMs: 100, buckets: 4, layout: [0, 6, 6, 0], paint: [1, 1, 1, 1], owners: { 'pain:style': [0, 3, 3, 0] }, before: { 'x|y|CSSAnimation|running|600|Infinity|opacity': 1 }, after: {} };
  const p = { ...pass(capture(13), capture(3), capture(13), capture(3)), diag };
  const cells = windowCells(times(3, () => p));
  assert.equal(cells.filter((c) => c.kind === 'Diag').length, 3);
  const md = swapMd(cells, ['run 1']);
  assert.ok(md.includes('.99.  pain:style') || md.includes('.99.'));
  assert.ok(md.includes('CSSAnimation'));
});
