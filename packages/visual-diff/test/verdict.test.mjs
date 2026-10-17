// The TS verdict must answer every Lean golden case as Lean does (lean/Fw/Gate/Pixel.lean, goldenLines).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_TOL, verdict } from '../src/verdict.mjs';

const GOLDEN = resolve(dirname(fileURLToPath(import.meta.url)), '../../contracts/golden/gate/pixel.jsonl');
const cases = readFileSync(GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('golden: every Lean case', () => {
  assert.ok(cases.length >= 20);
  for (const c of cases) assert.equal(verdict(c.tol, c.stats), c.verdict, c.name);
});

test('golden: all three outcomes occur', () => {
  assert.deepEqual([...new Set(cases.map((c) => c.verdict))].sort(), ['fail', 'pass', 'unsettled']);
});

test('the default tolerance is the Lean default', () => {
  const c = cases.find((x) => x.name === 'identical');
  assert.deepEqual(c.tol, DEFAULT_TOL);
});
