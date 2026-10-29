import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const golden = JSON.parse(readFileSync(join(root, 'packages/contracts/golden/preset/reader-files.json'), 'utf8'));

function closure(entry) {
  const seen = new Set();
  const todo = [resolve(root, entry)];
  while (todo.length) {
    const f = todo.pop();
    if (seen.has(f)) continue;
    seen.add(f);
    const src = readFileSync(f, 'utf8');
    for (const m of src.matchAll(/(?:from|import)\s*\(?\s*['"](\.{1,2}\/[^'"]+)['"]/g)) todo.push(resolve(dirname(f), m[1]));
  }
  return [...seen].map((f) => relative(root, f)).sort();
}

test('reader files: the relative import closure of the trajectory cli', () => {
  assert.deepEqual(golden, closure('packages/gate-breakpoints/src/trajectory/cli.mjs'));
});
