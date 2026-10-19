// Run: node --test test/port-svg.test.mjs (from apps/site). Check 4 of the port completeness gate (Fw.Port.Svg):
// scripts/port/digest.mjs replays every Lean case of packages/contracts/golden/port/svg.jsonl; with FW_SITE_DIST set
// to a built dist/aot, no svg of the snapshot page is missing from the prerendered page and none is extra.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { canon, digest, parseHtml, skel, svgCheck, svgUnits } from '../../../scripts/port/digest.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const cases = readFileSync(path.join(repo, 'packages/contracts/golden/port/svg.jsonl'), 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((l) => JSON.parse(l));
const dist = process.env.FW_SITE_DIST;

test('skeletons equal the Lean skeletons, canonical text included', () => {
  const sk = cases.filter((c) => c.fn === 'skel');
  assert.ok(sk.length > 0);
  for (const c of sk) {
    assert.deepEqual(skel(c.in), c.out);
    assert.equal(canon(skel(c.in)), c.canon);
  }
});

test('svg matching equals the Lean verdicts', () => {
  const ck = cases.filter((c) => c.fn === 'check');
  assert.ok(ck.length > 0);
  for (const c of ck) assert.deepEqual(svgCheck(c.excl, c.orig, c.rewrite), { missing: c.missing, extra: c.extra, pass: c.pass });
});

test('nested svgs belong to their outermost svg, and kids are read in document order', () => {
  const t = parseHtml('<div><svg viewBox="0 0 2 2"><g><path d="M0 0z"/><svg><path d="M1 1"/></svg></g></svg></div>');
  const u = svgUnits(t, () => 'page');
  assert.equal(u.length, 1);
  assert.equal(u[0].elements, 4);
  assert.equal(u[0].paths, 2);
});

test('built page: every snapshot svg has a rewrite svg of the same skeleton and back', { skip: !dist && 'FW_SITE_DIST unset' }, () => {
  const { svg } = digest({ snapshot: path.join(repo, 'snapshot/site'), dist: path.resolve(dist) });
  const show = (l) => l.map((s) => `${s.owner} ${s.key} viewBox=${s.viewBox} elements=${s.elements} paths=${s.paths}`).join('\n');
  assert.ok(svg.pass, `svg missing (${svg.missing.length}):\n${show(svg.missing)}\nsvg extra (${svg.extra.length}):\n${show(svg.extra)}`);
});
