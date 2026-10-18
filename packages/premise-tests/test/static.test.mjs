// Static checks, no browser: the tests the package declares are exactly the page premises the Lean golden registers
// (lane premises are asserted by their own CI workflow, not by a page test).
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { TESTS } from '../src/tests.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(join(here, '..', '..', 'contracts', 'golden', 'ops', 'premise.jsonl'), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l)).filter((r) => r.kind === 'premise' && r.testKind === 'page');

test('test ids are unique and named prem.<premise>', () => {
  assert.equal(new Set(TESTS.map((t) => t.id)).size, TESTS.length);
  for (const t of TESTS) assert.equal(t.id, `prem.${t.premise}`);
});

test('every test has a page, every page has a test', () => {
  for (const t of TESTS) assert.ok(existsSync(join(here, '..', 'pages', t.page)), `missing page ${t.page}`);
  const pages = readdirSync(join(here, '..', 'pages')).filter((f) => f.endsWith('.html')).sort();
  assert.deepEqual(pages, [...new Set(TESTS.map((t) => t.page))].sort());
});

test('the tests are exactly the page premises of the Lean golden', () => {
  assert.deepEqual(TESTS.map((t) => [t.id, t.premise]).sort(), golden.map((p) => [p.testId, p.id]).sort());
});
