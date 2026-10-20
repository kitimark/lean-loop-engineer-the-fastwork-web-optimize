// TS stand-in tests of the people-layout analyzer: origins and causes of synthetic dumps (no Lean golden: bookkeeping).
import test from 'node:test';
import assert from 'node:assert/strict';
import { causeOf, compareDumps } from '../src/people-layout-analyze.mjs';

const n = (p, g, c, b, extra = {}) => ({ p, g, c, b, ...extra });
const pairOf = (cmp, p) => cmp.pairs.find((d) => d.a.p === p);

// a column flex block holding an empty `picture` before its cover (the original) or only the cover (the port)
const orig = {
  nodes: [n('0', 'div', 'block', [0, 0, 100, 200]), n('0.0', 'picture', '', [0, 0, 0, 0]), n('0.1', 'div', 'cover', [0, 12, 100, 100]), n('0.2', 'div', 'meta', [0, 124, 100, 30])],
  sibs: [],
};
const port = {
  nodes: [n('0', 'div', 'block', [0, 0, 100, 188]), n('0.0', 'span', 'cover', [0, 0, 100, 100]), n('0.1', 'div', 'meta', [0, 112, 100, 30])],
  sibs: [],
};

test('a block whose children differ in number gets the structure cause, and so does its child that moved', () => {
  const cmp = compareDumps(orig, port);
  const block = pairOf(cmp, '0');
  assert.ok(block.why.includes('height'));
  assert.equal(causeOf(block).cause, 'structure: unmatched child');
  assert.match(causeOf(block).detail, /orig only \[picture\./);
  const meta = pairOf(cmp, '0.2');
  assert.ok(meta.why.includes('offset-y'));
  assert.equal(causeOf(meta).cause, 'structure: parent has an unmatched child');
});

test('descendants of a node with a differing transform are labelled by the ancestor', () => {
  const a = { nodes: [n('0', 'div', 'x', [0, 0, 100, 100], { tf: 'matrix(1, 0, 0, 1, 0, 0)' }), n('0.0', 'div', 'k', [0, 0, 50, 50])], sibs: [] };
  const b = { nodes: [n('0', 'div', 'x', [0, 0, 100, 100], { tf: 'matrix(0.9, 0, 0, 0.9, 0, 0)' }), n('0.0', 'div', 'k', [0, 0, 45, 45])], sibs: [] };
  const cmp = compareDumps(a, b);
  assert.equal(pairOf(cmp, '0.0').tfAnc, true);
  assert.equal(pairOf(cmp, '0').tfAnc, false);
  assert.equal(causeOf(pairOf(cmp, '0.0')).cause, 'transform of an ancestor differs (scroll-driven motion)');
  assert.equal(causeOf(pairOf(cmp, '0')).cause, 'transform differs (scroll-driven motion)');
});

test('equal trees have no differing pair', () => {
  const cmp = compareDumps(port, port);
  assert.equal(cmp.pairs.filter((d) => d.diff).length, 0);
});
