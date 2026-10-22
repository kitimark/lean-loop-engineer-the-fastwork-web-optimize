import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { offsets, mask, rawOf, rawOk, premises, grade, cellS1, accelerated } from '../src/pathpix.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/gate/path-pix.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('golden file holds every kind the twin replays', () => {
  for (const k of ['grade', 'accelerated', 'premises', 'offsets', 'mask', 'raw']) assert.ok(of(k).length > 0, k);
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
