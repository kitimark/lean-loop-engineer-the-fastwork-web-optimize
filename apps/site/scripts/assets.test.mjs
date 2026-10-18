// Run: node --test scripts/assets.test.mjs (from apps/site). One unit: a listed asset is a snapshot file that exists, and
// every /selling/ and /fonts/ URL written in src/ is listed. The land.ts reads derive from the same manifest.
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = path.resolve(root, '../..');
const manifest = JSON.parse(readFileSync(path.join(root, 'assets.manifest.json'), 'utf8'));
const listed = new Set(manifest.files.map((f) => f.url));

const walk = (dir) =>
  readdirSync(dir).flatMap((n) => {
    const p = path.join(dir, n);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });

test('every listed file exists in the snapshot and urls are unique', () => {
  assert.equal(listed.size, manifest.files.length);
  for (const { url, src } of manifest.files) {
    assert.ok(src.startsWith('snapshot/'), `${url}: source outside snapshot/`);
    assert.ok(existsSync(path.join(repo, src)), `${url}: ${src} missing`);
  }
});

test('every /selling/ and /fonts/ URL in src is listed', () => {
  const missing = [];
  for (const f of walk(path.join(root, 'src'))) {
    if (!/\.(tsx?|css|json)$/.test(f) || f.endsWith('.test.ts')) continue;
    const text = readFileSync(f, 'utf8');
    for (const m of text.matchAll(/\/(?:selling|fonts)\/[A-Za-z0-9_./@-]+\.[a-z0-9]+/g)) {
      if (!listed.has(m[0])) missing.push(`${path.relative(root, f)}: ${m[0]}`);
    }
  }
  assert.deepEqual(missing, []);
});
