// variance.mjs against the Lean golden vectors (Fw.Measure.WktrVariance; packages/contracts/golden/measure/wktr.variance.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { differs, varying, findings, claim, pairDiffs, overlap, rangeOf, tableOfClassesDir, tableOfPremise } from '../fixtures/variance.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(HERE, '..', '..', 'contracts', 'golden', 'measure', 'wktr.variance.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('golden has every kind', () => {
  for (const k of ['diffCase', 'findingsCase', 'pairCase', 'overlapCase', 'rangeCase']) assert.ok(of(k).length > 0, k);
});

test('differs equals Lean', () => {
  for (const c of of('diffCase')) assert.deepEqual(differs(c.a, c.b), c.differs, c.name);
});

test('varying, findings and claim equal Lean', () => {
  for (const c of of('findingsCase')) {
    assert.deepEqual(varying(c.runs), c.varying, c.name);
    assert.deepEqual(findings(c.base, c.cand, c.runs), c.findings, c.name);
    assert.equal(claim(c.base, c.cand, c.runs), c.claim, c.name);
  }
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
