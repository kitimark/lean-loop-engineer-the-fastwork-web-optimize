import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseSync } from 'vite';
import { collectClassTokens } from './part-footprint.mjs';

const golden = new URL('../../../packages/contracts/golden/parts/footprint.classpos.jsonl', import.meta.url);
const rows = readFileSync(fileURLToPath(golden), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

const tokensOf = (src) => {
  const { program } = parseSync('case.js', `const x = ${src};`);
  return collectClassTokens(program.body[0].declarations[0].init, () => null).map((t) => t.name);
};

test('the golden has the cases the Lean module defines', () => {
  assert.ok(rows.length >= 15);
  assert.ok(rows.some((r) => r.src.includes("=== 'exit'")));
});

for (const r of rows) {
  test(`class tokens of ${r.src}`, () => {
    assert.deepEqual(tokensOf(r.src), r.classes);
  });
}
