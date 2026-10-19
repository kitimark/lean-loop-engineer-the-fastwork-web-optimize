// Run: node --test test/port-assets.test.mjs (from apps/site). Check 3 of the port completeness gate
// (Fw.Site.Assets): scripts/port/digest.mjs replays every Lean case of packages/contracts/golden/port/assets.jsonl;
// renameFiles and the crawl read identities from files as Lean's renameRows expects; with FW_SITE_DIST set to a built
// dist/aot, every asset the snapshot page references is served by the rewrite (as a URL or inlined) or excluded.
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  assetsMissing,
  crawl,
  dataIdents,
  digest,
  ext,
  inlineNorm,
  isAsset,
  origIdents,
  origUrl,
  rename,
  renameFiles,
  renameRows,
  scanRefs,
  verdict,
} from '../../../scripts/port/digest.mjs';

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

test('inlineNorm, renameRows and their verdicts equal Lean', () => {
  const ns = cases.filter((c) => c.fn === 'inlineNorm');
  assert.ok(ns.length > 0);
  for (const c of ns) assert.equal(inlineNorm(c.in), c.out, JSON.stringify(c.in));
  const rs = cases.filter((c) => c.fn === 'renameRows');
  assert.ok(rs.length > 0);
  for (const c of rs) {
    const F = renameRows(c.orig, c.rewrite, c.files);
    assert.deepEqual(F, c.rows);
    assert.deepEqual(c.urls.map((u) => verdict(F, c.rewrite.map((w) => w.name), [], u)), c.verdicts);
  }
});

test('renameFiles reads identities from files: equal bytes, the first rewrite URL, inlined svg text and base64', () => {
  const t = mkdtempSync(path.join(tmpdir(), 'port-assets-'));
  try {
    const snap = path.join(t, 'snap');
    const dist = path.join(t, 'dist');
    mkdirSync(path.join(snap, 's'), { recursive: true });
    mkdirSync(path.join(dist, 'assets'), { recursive: true });
    const svg = '<svg viewBox="0 0 1 1">\n  <g/>\n</svg>\n';
    const txt = '<svg><text>a</text></svg>';
    writeFileSync(path.join(snap, 's/a.png'), 'PNGDATA');
    writeFileSync(path.join(snap, 's/b.svg'), svg);
    writeFileSync(path.join(snap, 's/c.svg'), txt);
    writeFileSync(path.join(snap, 's/d.png'), 'OTHER');
    writeFileSync(path.join(dist, 'assets/a1.png'), 'PNGDATA');
    writeFileSync(path.join(dist, 'assets/a2.png'), 'PNGDATA');
    const enc = 'data:image/svg+xml,' + encodeURIComponent(inlineNorm(svg));
    const b64 = 'data:image/svg+xml;base64,' + Buffer.from(txt).toString('base64');
    writeFileSync(path.join(dist, 'assets/x.js'), `const a="/assets/a2.png",b="/assets/a1.png",c="${enc}",d="${b64}";`);
    writeFileSync(path.join(dist, 'index.html'), `<script src="/assets/x.js"></script><img src="${enc.replaceAll("'", '&#x27;')}">`);
    const rw = crawl(dist);
    assert.deepEqual(rw.assets, ['/assets/a1.png', '/assets/a2.png']);
    assert.equal(rw.inline.length, 2);
    assert.deepEqual(dataIdents(`url("${enc}")`), [origIdents(path.join(snap, 's/b.svg'))[1]]);
    const O = ['/s/a.png', '/s/b.svg', '/s/c.svg', '/s/d.png'];
    const F = renameFiles({ files: [{ url: '/m/d.png', src: 'snapshot/site/s/d.png' }] }, snap, O, dist, rw);
    assert.deepEqual(F.map((f) => [f.url.replace(/[0-9a-f]{64}$/, 'H'), f.src]), [
      ['/assets/a1.png', 'snapshot/site/s/a.png'],
      ['inline:svgtext:H', 'snapshot/site/s/b.svg'],
      ['inline:bytes:H', 'snapshot/site/s/c.svg'],
      ['/m/d.png', 'snapshot/site/s/d.png'],
    ]);
    const R = [...rw.assets, ...rw.inline.map((i) => 'inline:' + i)];
    assert.deepEqual(O.map((u) => verdict(F, R, [], u)), ['present', 'present', 'present', 'missing']);
  } finally {
    rmSync(t, { recursive: true, force: true });
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

test('built page: every snapshot asset is served by the rewrite (as a URL or inlined) or excluded', { skip: !dist && 'FW_SITE_DIST unset' }, () => {
  const { assets } = digest({ snapshot: path.join(repo, 'snapshot/site'), dist: path.resolve(dist) });
  assert.ok(assets.orig > 0 && assets.rewrite > 0);
  assert.ok(assets.pass, `missing (${assets.missing.length}):\n${assets.missing.map((m) => `${m.owner} ${m.url}`).join('\n')}`);
});
