// This package imports from @fw/gate-breakpoints. A change there must not drop a name imported here: gate-shard-balance
// round 2 removed `mountPanel` from page.mjs and the snapshot-extract workflow failed at import time (CI run 39119690415).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const SRC = resolve(import.meta.dirname, '../src');

test('every name this package imports from gate-breakpoints/src is exported there', async () => {
  const seen = [];
  for (const f of readdirSync(SRC).filter((x) => x.endsWith('.mjs'))) {
    const text = readFileSync(resolve(SRC, f), 'utf8');
    for (const m of text.matchAll(/import\s*\{([^}]*)\}\s*from\s*'(\.\.\/\.\.\/gate-breakpoints\/src\/[A-Za-z.]+)'/g)) {
      const mod = await import(pathToFileURL(resolve(SRC, m[2])).href);
      for (const name of m[1].split(',').map((x) => x.trim()).filter(Boolean)) {
        seen.push(`${f}: ${name}`);
        assert.ok(name in mod, `${f} imports ${name} from ${m[2]}, which does not export it`);
      }
    }
  }
  assert.ok(seen.length >= 10, `found only ${seen.length} imports`);
});
