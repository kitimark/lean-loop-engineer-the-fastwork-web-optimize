import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { normalize, normalizeStyle, normalizeParts, splitList } from '../src/transition-list.mjs';

const golden = join(dirname(fileURLToPath(import.meta.url)), '../../contracts/golden/gate/transition-list.jsonl');
const rows = readFileSync(golden, 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('golden: at least 8 cases, unique names', () => {
  assert.ok(rows.length >= 8);
  assert.equal(new Set(rows.map((r) => r.name)).size, rows.length);
});

for (const { name, request, response } of rows) {
  test(`golden ${name}`, () => {
    assert.deepEqual(normalize(request), response);
    assert.deepEqual(normalize(response), response, 'idempotent (Lean normalize_idem)');
  });
}

test('faithful and logical earn lists normalize equal (Lean earn_equal)', () => {
  const by = Object.fromEntries(rows.map((r) => [r.name, r]));
  assert.notDeepEqual(by['earn-faithful'].request, by['earn-logical'].request);
  assert.deepEqual(normalize(by['earn-faithful'].request), normalize(by['earn-logical'].request));
});

const style = (p, d, t, y, b) => ({ 'transition-property': p, 'transition-duration': d, 'transition-timing-function': t, 'transition-delay': y, 'transition-behavior': b, color: 'red' });

test('splitList keeps commas inside parentheses', () => {
  assert.deepEqual(splitList('cubic-bezier(0.33, 0, 0.2, 1), ease'), ['cubic-bezier(0.33, 0, 0.2, 1)', 'ease']);
  assert.deepEqual(splitList('all'), ['all']);
});

test('normalizeStyle: shorthand arm equals longhand arm, other keys kept, no-shorthand style is the same object', () => {
  const cb = 'cubic-bezier(0.33, 0, 0.2, 1)';
  const a = style('max-width, opacity, padding-inline', '0.68s, 0.32s, 0.68s', `${cb}, ${cb}, ${cb}`, '0s, 0.12s, 0s', 'normal, normal, normal');
  const b = style('max-width, opacity, padding-inline-start, padding-inline-end', '0.68s, 0.32s, 0.68s, 0.68s', `${cb}, ${cb}, ${cb}, ${cb}`, '0s, 0.12s, 0s, 0s', 'normal, normal, normal, normal');
  assert.notDeepEqual(a, b);
  assert.deepEqual(normalizeStyle(a), b);
  assert.equal(normalizeStyle(b), b);
  const c = style('opacity', '1s', 'ease', '0s', 'normal');
  assert.equal(normalizeStyle(c), c);
  assert.equal(normalizeStyle({ color: 'red' }).color, 'red');
});

test('normalizeParts leaves a differing longhand duration visible', () => {
  const mk = (d) => ({ n: { earn: { items: [{ style: style('padding-inline', d, 'ease', '0s', 'normal') }] } } });
  const a = normalizeParts(mk('1s')), b = normalizeParts(mk('2s'));
  assert.notDeepEqual(a, b);
});
