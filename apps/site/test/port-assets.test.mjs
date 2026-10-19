// Run: node --test test/port-assets.test.mjs (from apps/site). Check 3 of the port completeness gate
// (Fw.Site.Assets): scripts/port/digest.mjs replays every Lean case of packages/contracts/golden/port/assets.jsonl;
// with FW_SITE_DIST set to a built dist/aot, every asset the snapshot page references is served by the rewrite.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { assetsMissing, digest, ext, isAsset, origUrl, rename, scanRefs, verdict } from '../../../scripts/port/digest.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const cases = readFileSync(path.join(repo, 'packages/contracts/golden/port/assets.jsonl'), 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((l) => JSON.parse(l));
const dist = process.env.FW_SITE_DIST;

test('ext, isAsset, origUrl and rename equal Lean', () => {
  for (const c of cases.filter((c) => c.fn === 'ext')) {
    assert.equal(ext(c.in), c.out, c.in);
    assert.equal(isAsset(c.in), c.isAsset, c.in);
  }
  for (const c of cases.filter((c) => c.fn === 'origUrl')) assert.equal(origUrl(c.in), c.out, c.in);
  for (const c of cases.filter((c) => c.fn === 'rename')) assert.equal(rename(c.files, c.in), c.out, c.in);
});

test('verdicts and the missing list equal Lean', () => {
  const vs = cases.filter((c) => c.fn === 'verdict');
  assert.ok(vs.length > 0);
  for (const c of vs) {
    assert.deepEqual(c.orig.map((u) => verdict(c.files, c.served, c.excl, u)), c.verdicts);
    assert.deepEqual(assetsMissing(c.files, c.served, c.excl, c.orig), c.missing);
    assert.equal(c.missing.length === 0, c.pass);
  }
});

test('the scanner resolves relative URLs, drops queries and skips other hosts', () => {
  assert.deepEqual(scanRefs('url(./a.woff2) url("../b.png?v=1") "/c.svg#x" https://cdn.example/d.png https://fastwork.co/e.jpg', '/_app/x'), [
    '/_app/x/a.woff2',
    '/_app/b.png',
    '/c.svg',
    '/e.jpg',
  ]);
});

test('built page: every snapshot asset is served by the rewrite or excluded', { skip: !dist && 'FW_SITE_DIST unset' }, () => {
  const { assets } = digest({ snapshot: path.join(repo, 'snapshot/site'), dist: path.resolve(dist) });
  assert.ok(assets.orig > 0 && assets.rewrite > 0);
  assert.ok(assets.pass, `missing (${assets.missing.length}):\n${assets.missing.map((m) => `${m.owner} ${m.url}`).join('\n')}`);
});
