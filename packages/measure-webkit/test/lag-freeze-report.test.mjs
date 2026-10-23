import test from 'node:test';
import assert from 'node:assert/strict';
import { nominal, validAt, countCells, KINDS, PERIODS, SWAP_US } from '../src/lag/swap.mjs';
import { freezeAnalysis, freezeMd, windowSamples } from '../src/lag/freezereport.mjs';

function capture(layout, rest) {
  const ws = nominal(0, PERIODS);
  const recs = ws.flatMap(([s], k) => [...Array.from({ length: layout(k) }, (_, i) => ['Layout', s + 1000 * i]), ...Array.from({ length: 6 }, (_, i) => ['Paint', s + 500 + i]),
    ...Array.from({ length: rest(k) }, (_, i) => ['Layout', s + SWAP_US + 1000 * i])]);
  return { ws, valid: ws.map((_, k) => validAt(ws, k)), cells: countCells(ws, recs, KINDS) };
}
const diag = (layout) => ({ layout, paint: layout.map(() => 1), owners: { 'hero-accent:class': [1, 0] }, before: { 'hero-accent|strokeIn|CSSAnimation|running|900|1|stroke-dashoffset': 1, 'nav|x|y': 4 }, after: {} });
const job = (id, p) => ({ jobId: id, pass: p });
const side = (swapLayout, rest, id, p, d) => ({
  schema: 'x', job: job(id, p), diag: d, diagOther: { faithful: d },
  captures: { 'faithful-a': capture(() => 14, rest), 'crop-a': capture(swapLayout, rest), 'faithful-b': capture(() => 14, rest), 'crop-b': capture(swapLayout, rest) },
});
const busyRest = (k) => (k % 3 === 0 ? 40 : 4);
const freeLayout = (k) => (k === 2 || k === 5 ? 4 : 14);
const doc = (id, p, { frozenSwap, zone, frozenRest = () => 4 }) => ({
  passes: [{ cost: {
    swap: side(freeLayout, busyRest, id, p, diag(Array.from({ length: 20 }, (_, i) => (i < 10 ? 6 : 0)))),
    swapFrozen: side(frozenSwap, frozenRest, id, p, diag(Array.from({ length: 20 }, () => 1))),
    zone,
  } }],
});
const z = (layout, paint, align, p) => ({ layout, paint, align, drew: true, accentStart: 'out', accentChanges: 1, job: job('9', p) });

test('a frozen run at the idle level decides every window atIdle, and the zone share comes out of the medians', () => {
  const zone = { free: [z(20, 40, true, 1), z(22, 42, false, 1)], frozen: [z(6, 30, true, 1), z(7, 31, false, 1)] };
  const an = freezeAnalysis([doc('9', 1, { frozenSwap: () => 4, zone }), doc('9', 2, { frozenSwap: () => 4, zone })]);
  assert.deepEqual(an.jobs, ['9']);
  for (const arm of ['crop', 'faithful']) assert.equal(an.arms[arm].windows.length, PERIODS);
  for (const w of an.arms.crop.windows) assert.equal(w.cell, 'atIdle', w.phase);
  assert.equal(an.arms.crop.idleLevel, 4);
  assert.equal(an.arms.crop.windows[0].frozen.length, 4);
  assert.equal(an.arms.crop.windows[0].frozenMedian, 4);
  assert.deepEqual(an.diag.frozen.map((d) => d.longRuns), [0, 0, 0, 0]);
  assert.deepEqual(an.diag.free.map((d) => d.longRuns), [1, 1, 1, 1]);
  assert.equal(an.diag.free[0].animsBefore, 1);
  assert.equal(an.diag.free[0].accentWrites, 1);
  assert.equal(an.zone.groups.all.Layout.verdict, 'lower');
  assert.equal(an.zone.groups.all.Layout.sharePct, 69);
  assert.equal(an.zone.groups['natural (start unaligned)'].Paint.free.n, 2);
});

test('a window above the idle level after the freeze is notAtIdle, one whose background stays busy is busyRemains', () => {
  const zone = { free: [], frozen: [] };
  const an = freezeAnalysis([doc('9', 1, { frozenSwap: () => 14, zone })]);
  assert.ok(an.arms.crop.windows.every((w) => w.cell === 'notAtIdle'), JSON.stringify(an.arms.crop.windows.map((w) => w.cell)));
  const busy = freezeAnalysis([doc('9', 1, { frozenSwap: () => 4, zone, frozenRest: busyRest })]);
  assert.ok(busy.arms.crop.windows.some((w) => w.cell === 'busyRemains'));
});

test('every sample is keyed by job, pass and capture slot, and the table names the slot and the state', () => {
  const zone = { free: [z(20, 40, true, 1)], frozen: [z(6, 30, true, 1)] };
  const d = doc('9', 1, { frozenSwap: () => 4, zone });
  const keys = windowSamples([d.passes[0].cost.swapFrozen], 'crop', 'Layout', 'swap', 0).map((s) => s[2]);
  assert.deepEqual(keys, ['9/p1/a', '9/p1/b']);
  const md = freezeMd(freezeAnalysis([d]), ['run 1']);
  assert.match(md, /\| swap:0 \| 2 \| 4 \|/);
  assert.match(md, /\| frozen \| crop \| 9\/p1\/diag \|/);
  assert.match(md, /\| frozen \| 9\/p1\/aligned \| 6 \| 30 \|/);
});

test('a job saved mid-pass (captures missing, no zone) is analysed from what it kept', () => {
  const d = doc('9', 1, { frozenSwap: () => 4, zone: { free: [], frozen: [] } });
  delete d.passes[0].cost.swapFrozen.captures['crop-b'];
  delete d.passes[0].cost.swapFrozen.captures['faithful-b'];
  d.passes[0].cost.swapFrozen.captures['crop-a'] = null;
  const an = freezeAnalysis([d, { passes: [{ cost: { swap: { job: job('9', 2), captures: {} }, zone: { free: [], frozen: [] } } }] }]);
  assert.equal(an.arms.crop.windows[0].frozen.length, 0);
  assert.equal(an.arms.faithful.windows[0].frozen.length, 1);
  assert.ok(freezeMd(an, ['run 1']).length > 0);
});
