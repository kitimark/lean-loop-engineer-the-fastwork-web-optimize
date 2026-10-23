import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { offsets, mask, rawOf, rawOk, premises, grade, cellS1, accelerated } from '../src/pathpix.mjs';
import { gradeRel, whyL, region, exitOffsets, exitClaim, armPin, shownAccent, pinMasks } from '../src/pathpix-exit.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/gate/path-pix.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('golden file holds every kind the twin replays', () => {
  for (const k of ['grade', 'accelerated', 'premises', 'offsets', 'mask', 'raw', 'rel', 'region', 'exitOffsets', 'exitClaim', 'accentPin', 'pinRegion']) assert.ok(of(k).length > 0, k);
});

test('grade, S1 and premises per cell equal the Lean golden', () => {
  for (const g of of('grade')) {
    assert.equal(grade(g.cell), g.grade, g.name);
    assert.equal(cellS1(g.cell), g.s1, g.name);
    assert.deepEqual(premises(g.cell.engine, g.cell.claim), g.premises, g.name);
  }
});

test('premises equal the Lean golden', () => {
  for (const p of of('premises')) assert.deepEqual(premises(p.engine, p.claim), p.premises, p.name);
});

test('accelerated equals the Lean golden', () => {
  for (const a of of('accelerated')) assert.equal(accelerated(a.props), a.accelerated, a.props.join());
});

test('offsets equal the Lean golden and span the range', () => {
  for (const o of of('offsets')) {
    assert.deepEqual(offsets(o.maxY), o.offsets, `maxY ${o.maxY}`);
    assert.equal(o.offsets.length, 9);
    assert.equal(o.offsets[0], 0);
    assert.equal(o.offsets[8], o.maxY);
  }
});

test('masks equal the Lean golden', () => {
  for (const m of of('mask')) assert.deepEqual(mask(m.dpr, m.fw, m.fh, m.box), m.mask, m.name);
});

test('count reduction equals the Lean golden', () => {
  for (const r of of('raw')) {
    assert.deepEqual(rawOf(r.pixels), r.raw);
    assert.equal(rawOk(r.raw), r.ok);
  }
});

test('the cell decision against the floor equals the Lean golden', () => {
  for (const r of of('rel')) {
    assert.equal(gradeRel(r.cell, r.floor, r.live), r.grade, r.name);
    assert.equal(whyL(r.cell, r.floor, r.live), r.why, r.name);
    assert.equal(gradeRel({ ...r.cell, stripsAccepted: true }, r.floor, r.live), r.ifAccepted, r.name);
  }
});

test('regions of a pixel equal the Lean golden', () => {
  for (const g of of('region')) assert.equal(region(g.masks, g.masks[g.mine] ?? [0, 0, 0, 0], g.x, g.y), g.region, JSON.stringify(g));
});

test('exit offsets and claims equal the Lean golden', () => {
  for (const o of of('exitOffsets')) assert.deepEqual(exitOffsets(o.T, o.n), o.offsets, `T ${o.T} n ${o.n}`);
  for (const c of of('exitClaim')) assert.deepEqual(exitClaim(c.layer, c.le600), c.claim, `${c.layer} ${c.le600}`);
});

test('the accent pin is the same in every arm and shows the served word, as the Lean golden says', () => {
  const rows = of('accentPin');
  assert.deepEqual([...new Set(rows.map((r) => r.arm))], ['A', 'A2', 'P']);
  for (const r of rows) {
    assert.equal(armPin(r.arm), r.pin, r.arm);
    assert.deepEqual(shownAccent(armPin(r.arm), { cursor: r.live.cursor, phase: r.live.phase }), r.shown, JSON.stringify(r));
  }
  assert.deepEqual(shownAccent('none', { cursor: 3, phase: 'draw-in' }), { cursor: 3, phase: 'draw-in' });
});

test('the pin changes no mask: regions under the pin equal the Lean golden', () => {
  for (const g of of('pinRegion')) {
    const ms = pinMasks(g.pin, g.masks);
    assert.deepEqual(ms, g.masks);
    assert.equal(region(ms, ms[g.mine] ?? [0, 0, 0, 0], g.x, g.y), g.region, JSON.stringify(g));
  }
});
