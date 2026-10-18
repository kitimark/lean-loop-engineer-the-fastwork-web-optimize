// variance.mjs against the Lean golden vectors (Fw.Measure.WktrVariance; packages/contracts/golden/measure/wktr.variance.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { differs, varying, findings, claim, rivals, nBaselines, typeOf, pairDiffs, overlap, rangeOf, tableOfClassesDir, tableOfPremise, idOf } from '../fixtures/variance.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(HERE, '..', '..', 'contracts', 'golden', 'measure', 'wktr.variance.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('golden has every kind', () => {
  for (const k of ['diffCase', 'findingsCase', 'typeOfCase', 'pairCase', 'overlapCase', 'rangeCase']) assert.ok(of(k).length > 0, k);
});

test('differs equals Lean', () => {
  for (const c of of('diffCase')) assert.deepEqual(differs(c.a, c.b), c.differs, c.name);
});

const run = (r) => ({ id: String(r.id), t: r.table });

test('rivals, varying, findings and claim equal Lean', () => {
  for (const c of of('findingsCase')) {
    const rs = c.runs.map(run), b = run(c.base), cd = run(c.cand);
    const rv = rivals(b, cd, rs);
    assert.deepEqual(rv.map((r) => Number(r.id)), c.rivals, c.name);
    assert.equal(nBaselines(rv), c.nBaselines, c.name);
    assert.deepEqual(varying(rv.map((r) => r.t)), c.varying, c.name);
    assert.deepEqual(findings(b.t, cd.t, rv.map((r) => r.t)), c.findings, c.name);
    assert.equal(claim(b, cd, rs), c.claim, c.name);
  }
});

test('one run listed twice is one baseline; the pair is never its own baseline', () => {
  const t = { a: 'deterministic' };
  const x = { id: '1', t }, b = { id: '2', t }, c = { id: '3', t };
  assert.equal(claim(b, c, [x, x]), 'noBaseline');
  assert.equal(claim(b, c, [x, { id: '4', t }]), 'measured');
  assert.equal(claim(b, c, [b, c, x]), 'noBaseline');
  assert.throws(() => claim(b, c, [x, { id: '1', t: { a: 'stable' } }]));
});

test('typeOf equals Lean (descriptive label)', () => {
  assert.ok(of('typeOfCase').length > 0);
  for (const c of of('typeOfCase')) assert.equal(typeOf(c.key), c.type, c.key);
});

test('pairDiffs equals Lean', () => {
  for (const c of of('pairCase')) assert.deepEqual(pairDiffs(c.runs), c.pairDiffs);
});

test('overlap and rangeOf equal Lean', () => {
  for (const c of of('overlapCase')) assert.equal(overlap(c.a, c.b), c.overlap);
  for (const c of of('rangeCase')) assert.deepEqual(rangeOf(c.xs), c.range);
});

test('tableOfClassesDir reads the fwcore classify text', () => {
  const d = mkdtempSync(join(tmpdir(), 'var-'));
  writeFileSync(join(d, 'classes-control-f1-live-trace.txt'), 'type class k t   (9 runs)\nlayoutUpdates   quarantined    20     9\nstyleRecalcs deterministic 0 0\n');
  writeFileSync(join(d, 'run.txt'), 'x');
  assert.deepEqual(tableOfClassesDir(d), { 'control-f1/live-trace/layoutUpdates': 'quarantined', 'control-f1/live-trace/styleRecalcs': 'deterministic' });
});

test('tableOfPremise reads premise.json classes of a tag', () => {
  const d = mkdtempSync(join(tmpdir(), 'var-'));
  const p = join(d, 'premise.json');
  writeFileSync(p, JSON.stringify({ classes: { auto: { 'control-f1': { live: { styleRecalcs: { class: 'deterministic', k: 0, t: 0 } } } } } }));
  assert.deepEqual(tableOfPremise(p, 'auto'), { 'control-f1/live/styleRecalcs': 'deterministic' });
  assert.throws(() => tableOfPremise(p, 'k1'));
});

test('idOf reads the workflow run id from run.txt', () => {
  const d = mkdtempSync(join(tmpdir(), 'var-'));
  assert.throws(() => idOf(d));
  writeFileSync(join(d, 'run.txt'), 'workflow run 123, sha abc\n');
  assert.equal(idOf(d), '123');
  assert.equal(idOf(`${d}/premise.json:auto`), '123');
});
