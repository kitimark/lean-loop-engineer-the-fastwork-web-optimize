import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { REPLACED_GOLDEN, readingVerdict, excusedItems, absent } from '../src/replaced.mjs';
import { readingVerdict as deltaVerdict } from '../src/flag-delta.mjs';
import { applyFlagDeltas } from '../src/summary.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const path = resolve(here, '../../contracts/golden/gate/replaced.jsonl');
const golden = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => golden.filter((x) => x.kind === k);
const fixture = of('fixture');
const entriesOf = (c) => (c.entries === 'fixture' ? fixture : []);

test('the golden is the Lean-generated replaced file', () => {
  assert.equal(REPLACED_GOLDEN, path);
  assert.deepEqual(fixture.map((e) => [e.id, e.flag, e.part, e.premise]), [
    ['fixture-stage-mount', 'fixture.stage:on', 'morph.mount', 'Fw.Gate.Replaced.fixture_unmounted_iff'],
    ['fixture-stage-tween', 'fixture.stage:on', 'morph.tween', 'Fw.Gate.Replaced.fixture_unmounted_iff'],
  ]);
});

test('readingVerdict and excusedItems replay every Lean reading case', () => {
  assert.ok(of('reading').length >= 20);
  for (const c of of('reading')) {
    const label = JSON.stringify([c.entries, c.flags, c.part, c.v, c.fails]);
    const es = entriesOf(c);
    assert.equal(readingVerdict(c.flags, c.part, c.v, c.fails, es), c.out, label);
    assert.deepEqual(excusedItems(c.flags, c.part, c.v, c.fails, es).map(([, x]) => ({ by: x.by, id: x.id })), c.excused, label);
  }
});

test('with no entries every Lean case gives the style-delta verdict', () => {
  for (const c of of('reading')) assert.equal(readingVerdict(c.flags, c.part, c.v, c.fails, []), deltaVerdict(c.flags, c.part, c.v, c.fails), JSON.stringify(c));
});

test('an excused replaced item is always an absent anchor of the entry part', () => {
  for (const c of of('reading')) {
    for (const [it, x] of excusedItems(c.flags, c.part, c.v, c.fails, entriesOf(c))) {
      if (x.by !== 'replaced') continue;
      assert.ok(absent(it));
      assert.equal(x.entry.part, c.part);
      assert.ok(c.flags.includes(x.entry.flag));
    }
  }
});

const evOf = (rows, fails) => ({ rows: { ...rows }, fails: Object.fromEntries(Object.entries(fails).map(([k, v]) => [k, [...v]])) });
const count = (role, a, b) => ({ cls: 'count', role, idx: -1, key: 'count', status: a === b ? 'equal' : 'differ', a, b });
const flags = ['fixture.stage:on'];

test('applyFlagDeltas excuses the absent anchors of the replaced parts and nothing else', () => {
  const ev = evOf(
    { 'morph.mount': 'fail', 'morph.tween': 'fail', platform: 'fail', nav: 'pass' },
    { 'morph.mount': [count('target', 1, 0)], 'morph.tween': [count('scroller', 1, 0)], platform: [count('section', 1, 0)] },
  );
  const ex = applyFlagDeltas(flags, ev, ['morph.mount', 'morph.tween', 'platform', 'nav'], fixture);
  assert.deepEqual(ev.rows, { 'morph.mount': 'pass', 'morph.tween': 'pass', platform: 'fail', nav: 'pass' });
  assert.deepEqual(ex.map((x) => [x.part, x.delta, x.by, x.orig, x.rewrite, x.premise]), [
    ['morph.mount', 'fixture-stage-mount', 'replaced', 1, 0, 'Fw.Gate.Replaced.fixture_unmounted_iff'],
    ['morph.tween', 'fixture-stage-tween', 'replaced', 1, 0, 'Fw.Gate.Replaced.fixture_unmounted_iff'],
  ]);
});

test('applyFlagDeltas keeps a present anchor, a flag-off run and an extra item failing', () => {
  const cases = [
    [flags, [count('target', 1, 2)]],
    [[], [count('target', 1, 0)]],
    [flags, [count('target', 1, 0), { cls: 'style', role: 'target', idx: 0, key: 'opacity', status: 'differ', a: '1', b: '0' }]],
  ];
  for (const [fs, items] of cases) {
    const ev = evOf({ 'morph.mount': 'fail' }, { 'morph.mount': items });
    assert.deepEqual(applyFlagDeltas(fs, ev, ['morph.mount'], fixture), []);
    assert.equal(ev.rows['morph.mount'], 'fail');
    assert.equal(ev.fails['morph.mount'].length, items.length);
  }
});

test('applyFlagDeltas with no entries leaves an absent anchor failing', () => {
  const ev = evOf({ 'morph.mount': 'fail' }, { 'morph.mount': [count('target', 1, 0)] });
  assert.deepEqual(applyFlagDeltas(flags, ev, ['morph.mount'], []), []);
  assert.equal(ev.rows['morph.mount'], 'fail');
});
