import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ARMS, C, CELL, METRICS, READING, cellOf, contrast, countsArmsToken, crLabelOf, fate, fates, flagsOf, flipValid, hi, lo, pushLabel, reading, refOf, searchOf, wkArmOf } from '../src/cols-verdict.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/cols-probe.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('constants and metric names equal the Lean lines', () => {
  const k = of('consts')[0];
  assert.equal(C.minJobs, k.minJobs);
  assert.equal(C.flipShareMin, k.flipShareMin);
  const m = of('metrics')[0];
  assert.deepEqual(METRICS.chromium.map((x) => x.name), m.chromium);
  assert.deepEqual(METRICS.webkit.map((x) => x.name), m.webkit);
});

test('arm rows replay the Lean golden', () => {
  assert.equal(of('arm').length, ARMS.length);
  for (const g of of('arm')) {
    const a = ARMS.find((x) => x.id === g.id);
    assert.ok(a, g.id);
    assert.equal(a.off, g.off);
    assert.equal(a.flip, g.flip);
    assert.equal(refOf(a), g.ref);
    assert.equal(searchOf(a), g.search);
    assert.equal(wkArmOf(a), g.wkArm);
    assert.equal(crLabelOf(a), g.crLabel);
    assert.deepEqual(flagsOf(a), g.flags);
  }
});

test('the counts arms token carries the f1..f3 flag sets of the Lean rows', () => {
  const tok = countsArmsToken().split('|');
  const byLabel = Object.fromEntries(of('arm').map((g) => [g.crLabel, g.flags.join(',')]));
  tok.forEach((t, i) => assert.equal(t, byLabel[`f${i + 1}`]));
  assert.equal(tok.length, 3);
});

test('cells replay the Lean golden', () => {
  for (const g of of('cell')) {
    assert.equal(lo(g.ref), g.lo, g.name);
    assert.equal(hi(g.ref), g.hi, g.name);
    assert.equal(cellOf(g.ref, g.off), g.cell, g.name);
  }
  assert.deepEqual(new Set(of('cell').map((g) => g.cell)), new Set(Object.values(CELL)));
});

test('readings replay the Lean golden', () => {
  for (const g of of('reading')) assert.equal(reading(g.valid, g.cells), g.reading, g.name);
  assert.deepEqual(new Set(of('reading').map((g) => g.reading)), new Set(Object.values(READING)));
});

test('push labels and flip share replay the Lean golden', () => {
  for (const g of of('push')) assert.equal(pushLabel(g), g.label, g.name);
  for (const g of of('share')) assert.equal(flipValid(g.took, g.pushes), g.valid, `${g.took}/${g.pushes}`);
});

test('fate replays the Lean golden for every reading pair', () => {
  assert.equal(of('fate').length, 16);
  for (const g of of('fate')) {
    assert.equal(fate('p5', g.bc, g.bw, g.fc, g.fw), g.p5);
    assert.equal(fate('p6', g.bc, g.bw, g.fc, g.fw), g.p6);
  }
  assert.equal(fate('p3', READING.cost, READING.cost, READING.cost, READING.cost), 'independent of picture cost');
});

test('contrast: a flip arm with no take gives undecided; a clear cost gives pictures cost', () => {
  const jobs = {
    base: [{ RasterTask: 100 }, { RasterTask: 104 }, { RasterTask: 102 }],
    'base+off': [{ RasterTask: 10 }, { RasterTask: 12 }, { RasterTask: 9 }],
    'timed-fixed': [{ RasterTask: 50 }, { RasterTask: 52 }, { RasterTask: 51 }],
    'timed-fixed+off': [{ RasterTask: 10 }, { RasterTask: 12 }, { RasterTask: 9 }],
  };
  const b = contrast('webkit', { base: jobs.base.map((j) => ({ ...j, layerCount: 5, backingBytes: 5, Paint: 5 })), 'base+off': jobs['base+off'].map((j) => ({ ...j, layerCount: 5, backingBytes: 5, Paint: 5 })) }, 'base+off');
  assert.equal(b.valid, true);
  assert.equal(b.reading, READING.noCost);
  const f = contrast('chromium', jobs, 'timed-fixed+off', { 'timed-fixed': { took: 0, pushes: 6 }, 'timed-fixed+off': { took: 6, pushes: 6 } });
  assert.equal(f.valid, false);
  assert.equal(f.reading, READING.few);
  const g = contrast('chromium', jobs, 'timed-fixed+off', { 'timed-fixed': { took: 6, pushes: 6 }, 'timed-fixed+off': { took: 6, pushes: 6 } });
  assert.equal(g.cells[0].cell, CELL.cost);
  assert.equal(g.reading, READING.cost);
  assert.deepEqual(Object.keys(fates({ bc: g.reading, bw: g.reading, fc: g.reading, fw: g.reading })), ['p2', 'p3', 'p4', 'p5', 'p6']);
});

test('reducer: job sums, take stats and the four-arm tree', async () => {
  const { jobOf, takeStats, reduceDir } = await import('../src/cols-reduce.mjs');
  const counts = { frames: [{ counts: { 'trace.RasterTask': 2, 'trace.PaintImage': 1 } }, { counts: { 'trace.RasterTask': 3, 'trace.cc.Draw': 4 } }] };
  assert.deepEqual(jobOf(counts), { RasterTask: 5, DisplayItemListRaster: 0, PaintImage: 1, 'cc.Draw': 4 });
  const t = takeStats([{ kind: 'push', dark: true }, { kind: 'take' }, { kind: 'push', dark: true }, { kind: 'push', dark: false }, { kind: 'take' }]);
  assert.deepEqual([t.pushes, t.took, t.dark], [3, 2, 2]);
  assert.deepEqual(t.labels, ['flip', 'dark-no-take', 'flip']);
  const { mkdtempSync, mkdirSync, writeFileSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const dir = mkdtempSync(join(tmpdir(), 'cols-'));
  const put = (label, run, raster, log) => {
    mkdirSync(join(dir, `chromium-counts-${label}-r${run}`));
    writeFileSync(join(dir, `chromium-counts-${label}-r${run}`, 'counts.json'), JSON.stringify({ frames: [{ counts: { 'trace.RasterTask': raster } }], ...(log ? { takeLog: log } : {}) }));
  };
  const flip = [{ kind: 'push', dark: true }, { kind: 'take' }];
  for (const r of [1, 2, 3]) { put('rewrite', r, 100 + r); put('f1', r, 10 + r); put('f2', r, 50 + r, flip); put('f3', r, 10 + r, flip); }
  const out = reduceDir(dir);
  assert.equal(out.files.length, 12);
  assert.equal(out.contrasts.base.cells[0].cell, CELL.cost);
  assert.equal(out.contrasts.flip.valid, true);
  assert.equal(out.contrasts.base.reading, READING.cost);
});
