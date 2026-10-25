import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { flagsOfSearch, readingVerdict, excusedItems, loadDeltas, wireItem, FLAG_DELTA_GOLDEN } from '../src/flag-delta.mjs';
import { applyFlagDeltas } from '../src/summary.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const path = resolve(here, '../../contracts/golden/gate/flag-delta.jsonl');
const golden = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => golden.filter((x) => x.kind === k);

test('the golden is the file the gate reads', () => {
  assert.equal(FLAG_DELTA_GOLDEN, path);
  assert.deepEqual(loadDeltas(), of('delta'));
});

test('the allowlist holds the five tuples of the two runs with their premises', () => {
  const ds = of('delta').map((d) => [d.flag, d.part, d.role, d.property, d.orig, d.rewrite, d.look, d.premise]);
  assert.deepEqual(ds, [
    ['morph.panel:rest', 'platform', 'section', 'filter', 'blur(0px)', 'none', 'E', 'Fw.Parts.MorphPanelOpt.rest_visSame_E'],
    ['morph.panel:rest', 'engine.scene', 'scene', 'filter', 'blur(0px)', 'none', 'E', 'Fw.Parts.MorphPanelOpt.rest_visSame_E'],
    ['morph.columns:final-scale', 'morph.columns', 'col', 'flex-basis', '0px', 'auto', 'L', 'Fw.Parts.MorphColumnsScale.layout_const'],
    ['morph.columns:final-scale', 'morph.columns', 'col', 'flex-grow', '1', '0', 'L', 'Fw.Parts.MorphColumnsScale.layout_const'],
    ['morph.columns:final-scale', 'morph.columns', 'col', 'flex-shrink', '1', '0', 'L', 'Fw.Parts.MorphColumnsScale.layout_const'],
  ]);
});

test('flagsOfSearch replays every Lean search case', () => {
  assert.ok(of('search').length >= 10);
  for (const c of of('search')) assert.deepEqual(flagsOfSearch(c.search), c.flags, c.search);
});

test('readingVerdict and excusedItems replay every Lean reading case', () => {
  assert.ok(of('reading').length >= 20);
  for (const c of of('reading')) {
    const label = JSON.stringify([c.flags, c.part, c.v, c.fails.length]);
    assert.equal(readingVerdict(c.flags, c.part, c.v, c.fails), c.out, label);
    assert.deepEqual(excusedItems(c.flags, c.part, c.v, c.fails).map(([, d]) => d.id), c.excused, label);
  }
});

test('wireItem keeps string values and nulls the others', () => {
  assert.deepEqual(wireItem({ cls: 'box', role: 'r', key: 'w', status: 'differ', a: 3, b: undefined, idx: 0 }),
    { cls: 'box', role: 'r', key: 'w', status: 'differ', byRect: false, a: null, b: null });
});

const evOf = (rows, fails) => ({ rows: { ...rows }, fails: Object.fromEntries(Object.entries(fails).map(([k, v]) => [k, [...v]])) });
const sec = (a, b) => ({ cls: 'style', role: 'section', idx: 0, key: 'filter', status: 'differ', a, b });

test('applyFlagDeltas turns only fully excused part readings into passes and lists their items', () => {
  const ev = evOf({ platform: 'fail', nav: 'fail', 'matchMedia =Lean': 'pass' }, { platform: [sec('blur(0px)', 'none')], nav: [sec('blur(0px)', 'none')] });
  const ex = applyFlagDeltas(['morph.panel:rest'], ev, ['platform', 'nav']);
  assert.equal(ev.rows.platform, 'pass');
  assert.equal(ev.rows.nav, 'fail');
  assert.deepEqual(ev.fails.platform, []);
  assert.equal(ev.fails.nav.length, 1);
  assert.deepEqual(ex.map((x) => [x.part, x.delta, x.idx]), [['platform', 'panel-rest-section-filter', 0]]);
});

test('applyFlagDeltas leaves a reading with one other item failing', () => {
  const ev = evOf({ platform: 'fail' }, { platform: [sec('blur(0px)', 'none'), { ...sec('1', '0.5'), key: 'opacity' }] });
  assert.deepEqual(applyFlagDeltas(['morph.panel:rest'], ev, ['platform']), []);
  assert.equal(ev.rows.platform, 'fail');
  assert.equal(ev.fails.platform.length, 2);
});

test('applyFlagDeltas with no flag changes nothing', () => {
  const ev = evOf({ platform: 'fail' }, { platform: [sec('blur(0px)', 'none')] });
  const before = JSON.stringify(ev);
  assert.deepEqual(applyFlagDeltas([], ev, ['platform']), []);
  assert.equal(JSON.stringify(ev), before);
});
