// Run: node --test test/port-sections.test.mjs (from apps/site). The Lean section table (Fw.Port.Sections, golden
// packages/contracts/golden/port/sections.json) equals the first role of every anchors.json part, and the owner rule
// of scripts/port/digest.mjs answers the Lean owner cases.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { owner, parseHtml, elements, owners, sections } from '../../../scripts/port/digest.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const anchors = JSON.parse(readFileSync(path.join(repo, 'packages/gate-breakpoints/src/anchors.json'), 'utf8'));

test('the section table is the first role of each anchors.json part, in order', () => {
  const want = Object.entries(anchors.parts).map(([part, p]) => ({ part, orig: p.roles[0].orig, rewrite: p.roles[0].rewrite }));
  assert.deepEqual(sections.table.map(({ part, orig, rewrite }) => ({ part, orig, rewrite })), want);
  for (const r of sections.table) assert.equal(r.pageLevel, r.orig === 'html', r.part);
});

test('owner answers every Lean case', () => {
  for (const c of sections.owner) assert.equal(owner(c.ancestors), c.owner, JSON.stringify(c.ancestors));
});

test('the selector subset owns nodes by the innermost matching root', () => {
  const tree = parseHtml(
    '<header class="start-selling-top-nav x"><a><svg viewBox="0 0 1 1"><path d="M0 0"/></svg></a></header>' +
      '<div class="hero-track"><div class="hero"><button class="scroll-cue"><svg></svg></button></div></div><p><svg></svg></p>',
  );
  const ownerOf = owners('orig');
  assert.deepEqual(elements(tree).filter((e) => e.tag === 'svg').map(ownerOf), ['nav.hitTest', 'hero.cue', 'page']);
  const rw = parseHtml('<div data-fw-row=""><div><svg></svg></div><span><svg></svg></span></div>');
  assert.deepEqual(elements(rw).filter((e) => e.tag === 'svg').map(owners('rewrite')), ['platform.stageBg', 'page']);
});
