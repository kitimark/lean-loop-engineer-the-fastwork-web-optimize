import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseToc, countRows, errorLines, verdictOf } from '../src/xctrace/parse.mjs';

const TOC = '<trace-toc><run number="1"><data><table schema="hitches"/><table schema="metal-gpu-intervals"/><table schema="hitches"/></data></run></trace-toc>';

test('parseToc: a run with tables is finalized and the schemas are unique', () => {
  const t = parseToc(TOC);
  assert.equal(t.finalized, true);
  assert.deepEqual(t.schemas, ['hitches', 'metal-gpu-intervals']);
});

test('parseToc: a malformed trace is not finalized', () => {
  assert.equal(parseToc('').finalized, false);
  assert.equal(parseToc('<trace-toc></trace-toc>').finalized, false);
});

test('countRows counts row elements', () => {
  assert.equal(countRows('<node><row a="1"/><row b="2"></row></node>'), 2);
  assert.equal(countRows(''), 0);
});

test('errorLines keeps the refusal text and strips directories', () => {
  const l = errorLines('Starting recording\n[Error] Hitches is not supported on this platform.\nwrote /Users/x/tmp/a.trace failed to open\n');
  assert.equal(l.length, 2);
  assert.match(l[0], /not supported on this platform/);
  assert.ok(!l[1].includes('/Users'));
});

test('verdictOf follows Lean hitchesRecorded: finalized and at least one row', () => {
  assert.equal(verdictOf({ toc: parseToc(TOC), rows: 3 }).recorded, true);
  assert.equal(verdictOf({ toc: parseToc(TOC), rows: 0 }).recorded, false);
  assert.equal(verdictOf({ toc: parseToc(''), rows: 5 }).recorded, false);
});
