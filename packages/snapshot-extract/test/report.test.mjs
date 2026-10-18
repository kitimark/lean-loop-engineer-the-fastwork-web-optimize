import test from 'node:test';
import assert from 'node:assert/strict';
import { compare, familiesOf, fontReport, summarize } from '../src/report.mjs';

const cell = (part, role, prop, x, s) => ({ t: 'cell', part, role, prop, v: [{ x, e: 'all' }], s: [{ x: s, e: 'all' }] });
const role = (part, r, n) => ({ t: 'role', part, role: r, n: [{ x: n, e: 'all' }] });

test('compare sorts a difference into one category', () => {
  const ref = [
    role('a', 'x', 1), role('a', 'y', 1), role('a', 'z', 1), role('a', 'w', 1),
    cell('a', 'x', 'color', 'rgb(1, 1, 1)', { k: 'inherited', from: 'body', up: 2 }),
    cell('a', 'y', 'color', 'rgb(2, 2, 2)', { k: 'rule', sheet: 's.css', ord: 1 }),
    cell('a', 'z', 'color', 'rgb(3, 3, 3)', { k: 'rule', sheet: 's.css', ord: 2 }),
    cell('a', 'w', 'color', 'rgb(4, 4, 4)', { k: 'rule', sheet: 's.css', ord: 3 }),
    cell('a', 'x', 'display', 'block', { k: 'initial' }),
  ];
  const port = [
    role('a', 'x', 1), role('a', 'y', 1), role('a', 'z', 0), role('a', 'w', 1),
    cell('a', 'x', 'color', 'rgb(0, 0, 0)', { k: 'initial' }),
    cell('a', 'y', 'color', 'rgb(0, 0, 0)', { k: 'initial' }),
    cell('a', 'w', 'color', 'rgb(9, 9, 9)', { k: 'rule', sheet: 'p.css', ord: 1 }),
    cell('a', 'x', 'display', 'block', { k: 'initial' }),
  ];
  const c = compare(ref, port, 1);
  const by = Object.fromEntries(c.diffs.map((d) => [`${d.role}.${d.prop}`, d.category]));
  assert.deepEqual(by, {
    'x.color': 'inherited-never-set',
    'y.color': 'declared-in-ref-unset-in-port',
    'z.color': 'port-element-missing',
    'w.color': 'port-sets-differently',
  });
  assert.equal(c.same, 1);
  const s = summarize(c);
  assert.equal(s.differing, 4);
  assert.deepEqual(s.topInheritedProps, [{ prop: 'color', cells: 1 }]);
});

test('compare skips animated cells', () => {
  const ref = [role('a', 'x', 1), cell('a', 'x', 'transform', '@animated', { k: 'rule', sheet: 's.css', ord: 1 })];
  const c = compare(ref, [role('a', 'x', 1)], 1);
  assert.equal(c.animated, 1);
  assert.equal(c.diffs.length, 0);
});

test('fontReport flags a non-generic family with no loaded face', () => {
  const fonts = {
    orig: { used: [{ family: '"Prompt", sans-serif', elements: 5 }], faces: [{ family: 'Prompt', status: 'loaded' }], rules: [] },
    port: { used: [{ family: '"Prompt", Arial, sans-serif', elements: 7 }], faces: [], rules: [] },
  };
  const r = fontReport(fonts, (f) => f === 'Prompt');
  const port = Object.fromEntries(r.port.map((f) => [f.family, f]));
  assert.equal(port.Prompt.withoutLoadedFace, true);
  assert.equal(port.Prompt.snapshotShips, true);
  assert.equal(port.Arial.snapshotShips, false);
  assert.equal(port['sans-serif'].withoutLoadedFace, false);
  assert.deepEqual(familiesOf('"A B", c'), ['A B', 'c']);
});
