// node --test .github/scripts/gate-search.test.mjs   (run from the repo root)
// gate-search.mjs against the Lean vectors of Fw.Gate.Search, in process and as the workflow runs it.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { pick } from './gate-search.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const golden = readFileSync(join(root, 'packages/contracts/golden/gate/search.jsonl'), 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((l) => JSON.parse(l));

test('golden: pick equals the Lean decision for every vector', () => {
  assert.ok(golden.length >= 12);
  for (const g of golden) {
    const r = pick(g.fw, g.preset);
    assert.equal(r.ok, g.ok, JSON.stringify(g));
    if (g.ok) assert.equal(r.search, g.search, JSON.stringify(g));
    else assert.equal(r.refusal, g.refusal, JSON.stringify(g));
  }
});

test('golden: the command prints the search of an accepted pair and exits 1 on a refused one', () => {
  for (const g of golden) {
    const p = spawnSync(process.execPath, [join(root, '.github/scripts/gate-search.mjs'), '--fw', g.fw, '--preset', g.preset], { encoding: 'utf8' });
    assert.equal(p.status, g.ok ? 0 : 1, JSON.stringify(g));
    if (g.ok) assert.equal(p.stdout, g.search);
  }
});

test('the proved preset maps to the key enumerateSearches writes', () => {
  assert.deepEqual(pick('', 'v2-proved'), { ok: true, search: '?preset=v2-proved' });
});
