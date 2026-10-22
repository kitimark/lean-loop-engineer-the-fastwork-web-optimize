import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { identOf, gridOk, rows, refusals, describeRefusal, checkPair, declaredTable, censusVerdict, varying, stable } from '../src/census-check.mjs';
import { reportRuns, runsOf } from '../src/census-check-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/census.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every golden kind has lines', () => {
  for (const k of ['ident', 'grid', 'varying', 'rows', 'check']) assert.ok(of(k).length > 0, k);
});

test('identity of a node from its attributes', () => {
  for (const g of of('ident')) assert.deepEqual(identOf(g.fw, g.layer), g.ident, `${g.fw}/${g.layer}`);
});

test('device-pixel grid of an origin', () => {
  for (const g of of('grid')) assert.equal(gridOk(g.dpr, g.o), g.ok, `dpr ${g.dpr} o ${g.o}`);
});

test('free-running box names, by identity', () => {
  for (const g of of('varying')) assert.equal(varying(g.name), g.varying, g.name);
});

test('stable boxes leave out torn-down layers and free-running boxes, however many', () => {
  const l = (name, reasons = ['willChange']) => ({ name, fw: null, layer: null, bounds: [0, 0, 1, 1], reasons });
  const layers = [l('div#a'), l('span.accent-module_frame_x'), l('span.accent-module_frame_x'), l('?', ['(gone)']), l('div#b', ['(gone)', 'x'])];
  assert.deepEqual(stable(layers).map((b) => b.name), ['div#a', 'div#b']);
});

test('declared rows of a census', () => {
  for (const g of of('rows')) assert.deepEqual(rows(g.layers), g.rows);
});

test('refusals of two arms, in the golden order', () => {
  for (const g of of('check')) assert.deepEqual(refusals(g.wantA, g.wantB, g.a, g.b), g.refusals, g.name);
});

test('every refusal that is not about the viewport or the sample list names a box', () => {
  for (const g of of('check')) for (const r of g.refusals) {
    if (r.code === 'viewport' || r.code === 'samples') continue;
    assert.ok(r.box, `${g.name} ${r.code}`);
    assert.ok(describeRefusal(r).includes(r.box) || r.code === 'undeclared', g.name);
  }
});

const rec = (name, { fw = null, layer = null, boundsU = [0, 0, 1e6, 1e6], origin = null, memory = 4096 } = {}) =>
  ({ name, fw, layer, boundsU, origin, reasons: ['willChange'], memory });
const sample = (y, layers, rendered = [], dprMilli = 3000) => ({ requestedY: y, dprMilli, rendered, layers });

test('two identical runs are accepted; an extra undeclared layer in one is named', () => {
  const a = [sample(0, [rec('div#a'), rec('nav', { fw: 'nav', layer: 'nav_bar' })], ['nav_bar'])];
  assert.equal(checkPair(a, a).state, 'accepted');
  const b = [sample(0, [rec('div#a'), rec('span.glow', { boundsU: [5e6, 5e6, 2e6, 2e6] }), rec('nav', { fw: 'nav', layer: 'nav_bar' })], ['nav_bar'])];
  const v = checkPair(a, b);
  assert.equal(v.state, 'refused');
  assert.deepEqual(v.refusals.map((r) => [r.code, r.box, r.inA, r.inB]), [['undeclared', 'span.glow', 0, 1]]);
  assert.match(v.lines[0], /span\.glow/);
});

test('composite and snap wants refuse a missing layer and an off-grid origin by id', () => {
  const ok = [sample(0, [rec('div#a'), rec('nav', { fw: 'nav', layer: 'nav_bar', origin: [0, 0] })], ['nav_bar'])];
  assert.equal(checkPair(ok, ok, { composite: 'all', snap: 'all' }).state, 'accepted');
  const gone = [sample(0, [rec('div#a')], ['nav_bar'])];
  assert.deepEqual(checkPair(gone, ok, { composite: 'all' }).refusals.map((r) => [r.code, r.side, r.box]), [['notComposited', 'a', 'nav_bar']]);
  const off = [sample(0, [rec('div#a'), rec('nav', { fw: 'nav', layer: 'nav_bar', origin: [500000, 0] })], ['nav_bar'])];
  assert.deepEqual(checkPair(ok, off, { snap: 'nav_bar' }).refusals.map((r) => [r.code, r.side, r.box, r.axis]), [['offGrid', 'b', 'nav_bar', 'x']]);
});

test('two loads that differ in free-running layers only are accepted; one unlisted layer is named', () => {
  const anim = (w) => rec('span.accent-module_frame_0z18R8', { boundsU: [0, 0, w * 1e6, 47e6] });
  const gone = { ...rec('?'), reasons: ['(gone)'] };
  const a = [sample(0, [rec('div#a'), anim(60), anim(60), gone])];
  const b = [sample(0, [rec('div#a'), anim(101)])];
  assert.equal(checkPair(a, b).state, 'accepted');
  const c = [sample(0, [rec('div#a'), rec('span.accent-module_frame'), anim(101)])];
  assert.deepEqual(checkPair(a, c).refusals.map((r) => [r.code, r.box]), [['undeclared', 'span.accent-module_frame']]);
});

test('a sample a collector could not read is unavailable, neither accepted nor refused', () => {
  const ok = [sample(0, [rec('div#a')])];
  const bad = [{ requestedY: 0, dprMilli: 3000, rendered: [], layers: [], error: 'no LayerTree.layerTreeDidChange after enable' }];
  const v = checkPair(ok, bad);
  assert.equal(v.state, 'unavailable');
  assert.match(v.lines[0], /no LayerTree/);
});

test('a different pixel ratio refuses before anything else', () => {
  const v = checkPair([sample(0, [rec('x')], [], 3000)], [sample(0, [rec('y')], [], 2000)]);
  assert.deepEqual(v.refusals.map((r) => r.code), ['viewport']);
});

test('declared table reports rendered nodes, layers and bytes per id', () => {
  const t = declaredTable([sample(0, [rec('a', { fw: 'h', layer: 'hero_copy', memory: 100 }), rec('b', { fw: 'h', layer: 'hero_copy', memory: 50 }), rec('c')], ['hero_copy', 'hero_copy', 'nav_bar'])]);
  assert.deepEqual(t[0].declared, [{ id: 'hero_copy', rendered: 2, layers: 2, bytes: 150 }, { id: 'nav_bar', rendered: 1, layers: 0, bytes: 0 }]);
  assert.equal(t[0].undeclared, 1);
});

test('passes of a session are each checked against pass 1', () => {
  const p = (layers) => ({ census: [sample(0, layers)] });
  const v = censusVerdict([p([rec('a')]), p([rec('a')]), p([rec('a'), rec('z')])]);
  assert.equal(v.state, 'refused');
  assert.deepEqual(v.pairs.map((x) => x.state), ['accepted', 'refused']);
});

test('offline report reads determinism passes and a Chromium counts record', () => {
  const det = { passes: [{ census: [sample(0, [rec('a')])] }, { census: [sample(0, [rec('a')])] }] };
  assert.equal(reportRuns(runsOf('d.json', det), {}).state, 'accepted');
  const counts = { meta: { layerCensus: { schema: 'fw.layer-census/1', samples: [sample(0, [rec('a')])] } } };
  const runs = [...runsOf('r1', counts), ...runsOf('r2', { meta: { layerCensus: { samples: [sample(0, [rec('b')])] } } })];
  const rep = reportRuns(runs, {});
  assert.equal(rep.state, 'refused');
  assert.ok(rep.lines.some((l) => /undeclared layer "a"/.test(l)));
});
