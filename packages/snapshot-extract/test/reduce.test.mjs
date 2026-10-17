import test from 'node:test';
import assert from 'node:assert/strict';
import { buildRows, cleanSource, cleanValue, expandGroups, groupValues, inOrder, stableRows } from '../src/reduce.mjs';

test('groupValues: one value for all environments collapses to "all"', () => {
  assert.deepEqual(groupValues(['a', 'a', 'a']), [{ x: 'a', e: 'all' }]);
  assert.deepEqual(groupValues(['a', 'b', 'a']), [{ x: 'a', e: [0, 2] }, { x: 'b', e: [1] }]);
  assert.deepEqual(groupValues([undefined, 'a']), [{ x: null, e: [0] }, { x: 'a', e: [1] }]);
});

test('expandGroups inverts groupValues', () => {
  for (const vals of [['a', 'a', 'a'], ['a', 'b', 'a'], [null, 'x', null, 'y']]) {
    assert.deepEqual(expandGroups(groupValues(vals), vals.length), vals);
  }
});

test('cleanValue keeps numbers and keywords, shortens assets and long values', () => {
  assert.equal(cleanValue('16px'), '16px');
  assert.equal(cleanValue('url("https://x.test/a/b/pic.webp?v=1")'), 'url(pic.webp)');
  assert.match(cleanValue('url("data:image/svg+xml;utf8,<svg/>")'), /^url\(data:#[0-9a-f]{8}\)$/);
  assert.match(cleanValue('x'.repeat(400)), /^long:400#[0-9a-f]{8}$/);
  assert.equal(cleanValue('x'.repeat(300)).length, 300);
});

test('cleanSource drops the selector', () => {
  assert.deepEqual(cleanSource({ k: 'rule', sheet: 'a.css', ord: 3, sel: 'body' }), { k: 'rule', sheet: 'a.css', ord: 3 });
});

const perEnv = [
  [{ part: 'p', role: 'r', count: 1, cells: { color: { v: 'red', s: { k: 'rule', sheet: 'a.css', ord: 1, sel: 'x' } }, width: { v: '10px', s: { k: 'initial' } } } }],
  [{ part: 'p', role: 'r', count: 1, cells: { color: { v: 'red', s: { k: 'rule', sheet: 'a.css', ord: 1, sel: 'x' } }, width: { v: '12px', s: { k: 'initial' } } } }],
];

test('buildRows: role row, sorted cell rows, selector kept only on request', () => {
  const { rows, props } = buildRows(perEnv, [{ part: 'p', role: 'r' }]);
  assert.deepEqual(props, { 'p/r': ['color', 'width'] });
  assert.equal(rows[0].t, 'role');
  assert.deepEqual(rows[1].v, [{ x: 'red', e: 'all' }]);
  assert.deepEqual(rows[1].s, [{ x: { k: 'rule', sheet: 'a.css', ord: 1 }, e: 'all' }]);
  assert.deepEqual(rows[2].v, [{ x: '10px', e: [0] }, { x: '12px', e: [1] }]);
  const full = buildRows(perEnv, [{ part: 'p', role: 'r' }], { withSelector: true });
  assert.equal(full.rows[1].s[0].x.sel, 'x');
});

test('stableRows: identical in every run is stable, anything else is unstable', () => {
  const a = { t: 'cell', part: 'p', role: 'r', prop: 'a', v: [{ x: '1', e: 'all' }], s: [] };
  const b1 = { t: 'cell', part: 'p', role: 'r', prop: 'b', v: [{ x: '1', e: 'all' }], s: [] };
  const b2 = { ...b1, v: [{ x: '2', e: 'all' }] };
  const c = { t: 'cell', part: 'p', role: 'r', prop: 'c', v: [], s: [] };
  const { stable, unstable } = stableRows([[a, b1, c], [a, b2], [a, b1, c]]);
  assert.deepEqual(stable.map((r) => r.prop), ['a']);
  assert.deepEqual(unstable.map((u) => [u.key, u.variants]), [['cell|p|r|b', 2], ['cell|p|r|c', 2]]);
  assert.deepEqual(inOrder(stable, [a, b1]).map((r) => r.prop), ['a']);
});
