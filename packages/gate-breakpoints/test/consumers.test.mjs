// Other packages import from this one (packages/snapshot-extract). A change here must not drop a name they import: round 2
// removed `mountPanel` from page.mjs and the snapshot-extract workflow failed at import time (CI run 39119690415).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { PKG } from '../src/serve.mjs';

const CONSUMERS = resolve(PKG, '../snapshot-extract/src');

test('every name another package imports from gate-breakpoints/src is exported there', async () => {
  const seen = [];
  for (const f of readdirSync(CONSUMERS).filter((x) => x.endsWith('.mjs'))) {
    const text = readFileSync(resolve(CONSUMERS, f), 'utf8');
    for (const m of text.matchAll(/import\s*\{([^}]*)\}\s*from\s*'(\.\.\/\.\.\/gate-breakpoints\/src\/[A-Za-z.]+)'/g)) {
      const mod = await import(pathToFileURL(resolve(CONSUMERS, m[2])).href);
      for (const name of m[1].split(',').map((x) => x.trim()).filter(Boolean)) {
        seen.push(`${f}: ${name}`);
        assert.ok(name in mod, `${f} imports ${name} from ${m[2]}, which does not export it`);
      }
    }
  }
  assert.ok(seen.length >= 10, `found only ${seen.length} imports`);
});
