import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { flagsOfSearch, readingVerdict, excusedItems, loadDeltas, wireItem, FLAG_DELTA_GOLDEN } from '../src/flag-delta.mjs';
import { applyFlagDeltas } from '../src/summary.mjs';
import { loadReplaced } from '../src/replaced.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const path = resolve(here, '../../contracts/golden/gate/flag-delta.jsonl');
const golden = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => golden.filter((x) => x.kind === k);

test('the golden is the file the gate reads', () => {
  assert.equal(FLAG_DELTA_GOLDEN, path);
  assert.deepEqual(loadDeltas(), of('delta'));
});

test('the allowlist holds the tuples of the reviewed flags with their premises', () => {
  const ds = of('delta').map((d) => [d.flag, d.part, d.role, d.property, d.orig, d.rewrite, d.look, d.premise]);
  assert.deepEqual(ds, [
    ['morph.panel:rest', 'platform', 'section', 'filter', 'blur(0px)', 'none', 'E', 'Fw.Parts.MorphPanelOpt.rest_visSame_E'],
    ['morph.panel:rest', 'engine.scene', 'scene', 'filter', 'blur(0px)', 'none', 'E', 'Fw.Parts.MorphPanelOpt.rest_visSame_E'],
    ['morph.columns:final-scale', 'morph.columns', 'col', 'flex-basis', '0px', 'auto', 'L', 'Fw.Parts.MorphColumnsScale.layout_const'],
    ['morph.columns:final-scale', 'morph.columns', 'col', 'flex-grow', '1', '0', 'L', 'Fw.Parts.MorphColumnsScale.layout_const'],
    ['morph.columns:final-scale', 'morph.columns', 'col', 'flex-shrink', '1', '0', 'L', 'Fw.Parts.MorphColumnsScale.layout_const'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', 'background-clip', 'text', 'border-box', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', '-webkit-background-clip', 'text', 'border-box', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', 'background-image', 'linear-gradient(90deg, rgb(255, 255, 255) 0px, rgb(255, 255, 255) 33.33%, rgb(130, 188, 255) 40%, rgb(36, 131, 255) 45%, rgb(255, 102, 244) 50%, rgb(255, 48, 41) 55%, rgb(254, 123, 2) 60%, rgb(255, 255, 255) 66.67%, rgb(255, 255, 255) 100%)', 'none', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', 'background-image', 'linear-gradient(90deg, rgb(255, 255, 255) 0px, rgb(255, 255, 255) 33.330002%, rgb(130, 188, 255) 40%, rgb(36, 131, 255) 45%, rgb(255, 102, 244) 50%, rgb(255, 48, 41) 55%, rgb(254, 123, 2) 60%, rgb(255, 255, 255) 66.669998%, rgb(255, 255, 255) 100%)', 'none', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', 'display', 'inline', 'inline-block', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', 'position', 'static', 'relative', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', 'position', 'relative', 'static', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', 'mask-image', 'none', 'linear-gradient(rgb(0, 0, 0), rgb(0, 0, 0))', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', 'mask-clip', 'border-box', 'text', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['platform.sweep:layer-sweep', 'platform.sweep', 'word', '-webkit-mask-clip', 'border-box', 'text', 'L', 'Fw.Parts.PlatformSweepLayer.same_look'],
    ['hero.exit:contain', 'hero.exit', 'hero', 'contain', 'none', 'size layout', 'E', 'Fw.Parts.HeroContainOpt.hero_same_box'],
    ['hero.exit:contain', 'hero', 'stage', 'contain', 'none', 'size layout', 'E', 'Fw.Parts.HeroContainOpt.hero_same_box'],
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
    { cls: 'box', role: 'r', key: 'w', status: 'differ', byRect: false, a: null, b: null, rewriteCount: null });
  assert.deepEqual(wireItem({ cls: 'count', role: 'target', key: 'count', status: 'differ', a: 1, b: 0, idx: -1 }),
    { cls: 'count', role: 'target', key: 'count', status: 'differ', byRect: false, a: null, b: null, rewriteCount: 0 });
});

test('the replaced-part list is the reviewed one (Lean Fw.Gate.FlagDelta.replacedParts)', () => {
  assert.deepEqual(loadReplaced(), of('replaced'));
  assert.deepEqual(of('replaced').map((e) => [e.flag, e.part, e.premise]), []);
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
