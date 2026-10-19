// Run: node --test test/port-sections.test.mjs (from apps/site). The Lean section table (Fw.Port.Sections, golden
// packages/contracts/golden/port/sections.json) is the first role of every anchors.json part it does not drop; on the
// snapshot page (and with FW_SITE_DIST set, on the prerendered page) no node is matched by two section rows and the
// rows that match no node are exactly the Lean unrooted list; the owner rule of scripts/port/digest.mjs answers the
// Lean owner cases.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { owner, parseHtml, elements, owners, sections, selector } from '../../../scripts/port/digest.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const anchors = JSON.parse(readFileSync(path.join(repo, 'packages/gate-breakpoints/src/anchors.json'), 'utf8'));
const dist = process.env.FW_SITE_DIST;

test('the section table is the first role of each anchors.json part it does not drop, in order', () => {
  const dropped = new Set(sections.dropped.map((d) => d.part));
  const want = Object.entries(anchors.parts)
    .filter(([part]) => !dropped.has(part))
    .map(([part, p]) => ({ part, orig: p.roles[0].orig, rewrite: p.roles[0].rewrite }));
  assert.deepEqual(sections.table.map(({ part, orig, rewrite }) => ({ part, orig, rewrite })), want);
  for (const d of sections.dropped) assert.ok(d.part in anchors.parts && d.reason, d.part);
  for (const r of sections.table) assert.equal(r.pageLevel, r.orig === 'html', r.part);
});

const nodeMap = (file, arm) => {
  const els = elements(parseHtml(readFileSync(file, 'utf8')));
  const rows = sections.table.filter((r) => !r.pageLevel).map((r) => ({ part: r.part, match: selector(r[arm]) }));
  const shared = els.map((e) => rows.filter((r) => r.match(e)).map((r) => r.part)).filter((l) => l.length > 1);
  const none = rows.filter((r) => !els.some(r.match)).map((r) => r.part);
  return { shared, none };
};

test('snapshot page: each node is matched by at most one section row; the rows without a node are unrooted', () => {
  const { shared, none } = nodeMap(path.join(repo, 'snapshot/site/index.html'), 'orig');
  assert.deepEqual(shared, []);
  assert.deepEqual(none, sections.unrooted);
});

test('built page: each node is matched by at most one section row; the rows without a node are unrooted', { skip: !dist && 'FW_SITE_DIST unset' }, () => {
  const { shared, none } = nodeMap(path.join(path.resolve(dist), 'index.html'), 'rewrite');
  assert.deepEqual(shared, []);
  assert.deepEqual(none, sections.unrooted);
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
  assert.deepEqual(elements(tree).filter((e) => e.tag === 'svg').map(ownerOf), ['nav', 'hero.cue', 'page']);
  const rw = parseHtml('<div data-fw-row=""><div><svg></svg></div><span><svg></svg></span></div>');
  assert.deepEqual(elements(rw).filter((e) => e.tag === 'svg').map(owners('rewrite')), ['platform.stageBg', 'page']);
});
