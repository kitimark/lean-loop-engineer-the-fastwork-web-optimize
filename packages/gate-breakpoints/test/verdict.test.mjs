import test from 'node:test';
import assert from 'node:assert/strict';
import { STATUS, boxEq, cellVerdict, comparedProps, countStatus, envDeviations, isSkipped, partItems, relBox, rollup, sameSideOfEdges, styleValueEq, truthItems, verdictToStatus } from '../src/verdict.mjs';

test('cellVerdict: the one rule', () => {
  assert.equal(cellVerdict([]), 'not-comparable');
  assert.equal(cellVerdict(['na', 'na']), 'not-comparable');
  assert.equal(cellVerdict(['equal', 'equal']), 'pass');
  assert.equal(cellVerdict(['equal', 'na', 'equal']), 'pass');
  assert.equal(cellVerdict(['equal', 'differ']), 'fail');
  assert.equal(cellVerdict(['equal', 'missing']), 'fail');
  assert.equal(cellVerdict(['na', 'missing']), 'fail');
});

test('rollup reuses the rule through verdictToStatus', () => {
  assert.equal(verdictToStatus('pass'), STATUS.equal);
  assert.equal(rollup(['pass', 'not-comparable', 'pass']), 'pass');
  assert.equal(rollup(['pass', 'fail']), 'fail');
  assert.equal(rollup(['not-comparable']), 'not-comparable');
  assert.equal(rollup([]), 'not-comparable');
});

test('styleValueEq: exact, or numbers within 1e-3 with equal skeletons', () => {
  assert.ok(styleValueEq('120px', '120px'));
  assert.ok(styleValueEq('120px', '120.0009px'));
  assert.ok(!styleValueEq('120px', '120.002px'));
  assert.ok(!styleValueEq('120px', '120em'));
  assert.ok(styleValueEq('matrix(1, 0, 0, 1, -5, 0)', 'matrix(1, 0, 0, 1, -5.0005, 0)'));
  assert.ok(!styleValueEq('rgb(0, 0, 0)', 'rgb(0, 0, 1)'));
  assert.ok(!styleValueEq('auto', undefined));
  assert.ok(!styleValueEq('auto', '0px'));
});

test('boxEq: 0.5 px inclusive', () => {
  assert.ok(boxEq(10, 10.5));
  assert.ok(!boxEq(10, 10.51));
  assert.ok(!boxEq(undefined, 1));
  assert.ok(!boxEq(NaN, 1));
});

test('countStatus: both zero means the anchor is absent', () => {
  assert.equal(countStatus(4, 4), 'equal');
  assert.equal(countStatus(4, 3), 'differ');
  assert.equal(countStatus(0, 0), 'missing');
});

test('isSkipped and comparedProps', () => {
  assert.ok(isSkipped('animation', [], ['animation']));
  assert.ok(isSkipped('animation-name', [], ['animation']));
  assert.ok(!isSkipped('animations', [], ['animation']));
  assert.ok(isSkipped('width', ['width'], []));
  const anchors = { style: { skipPrefixes: [{ prefix: 'animation' }], skipSets: { ld: { props: ['width', 'height'] } } } };
  assert.deepEqual(comparedProps(['width', 'color', 'animation-name', 'top'], { skipSets: ['ld'], skipProps: ['top'] }, anchors), ['color']);
});

test('relBox', () => {
  const it = { rect: { x: 10, y: 20, w: 5, h: 6 } };
  assert.deepEqual(relBox(it, { rect: { x: 4, y: 5, w: 1, h: 1 } }), { x: 6, y: 15, w: 5, h: 6 });
  assert.deepEqual(relBox(it, null), { x: 10, y: 20, w: 5, h: 6 });
});

test('sameSideOfEdges and envDeviations', () => {
  assert.ok(sameSideOfEdges(600, 601, [[500, 501]]));
  assert.ok(!sameSideOfEdges(500, 501, [[500, 501]]));
  const req = { width: 600.5, height: 900, deviceWidth: 600.5, dpr: 1.25, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
  const raw = { viewport: { innerHeight: 900, screenWidth: 601, dpr: 1.25 }, observed: { widthExact: false, hoverHover: true, hoverNone: false, pointerFine: true, pointerCoarse: false, reducedMotion: false, dark: false } };
  assert.deepEqual(envDeviations(req, raw, [[500, 501]]), ['width']);
  raw.observed.widthExact = true;
  assert.deepEqual(envDeviations(req, raw, [[500, 501]]), []);
  raw.observed.pointerFine = false; raw.observed.pointerCoarse = true;
  assert.deepEqual(envDeviations(req, raw, [[500, 501]]), ['pointer']);
});

test('truthItems: the Lean check is n/a without an achieved env or a vector', () => {
  const side = { truth: { a: true, b: false }, truthLegacy: { a: true, b: null }, neutral: { print: false } };
  const items = truthItems(side, side, { a: true, b: false }, { print: false }, true);
  assert.equal(cellVerdict(items.map((i) => i.status)), 'pass');
  const off = truthItems(side, side, { a: true, b: false }, { print: false }, false);
  assert.ok(off.filter((i) => i.cls === 'truth.lean').every((i) => i.status === 'na'));
  const wrong = truthItems(side, side, { a: false, b: false }, { print: false }, true);
  assert.equal(cellVerdict(wrong.map((i) => i.status)), 'fail');
  const diff = truthItems(side, { ...side, truth: { a: false, b: false } }, undefined, undefined, true);
  assert.ok(diff.some((i) => i.cls === 'truth.AR' && i.status === 'differ'));
});

test('partItems: counts, boxes relative to a reference, styles, and info items outside the verdict', () => {
  const anchors = { style: { skipPrefixes: [{ prefix: 'animation' }], skipSets: {} } };
  const spec = { roles: [{ role: 'unit', boxRel: { role: 'unit', index: 0 }, dims: ['x', 'w'], skipSets: [], skipProps: [] }] };
  const mk = (x0, x1, color) => ({ unit: { count: 2, declared: [], items: [
    { rect: { x: x0, y: 0, w: 10, h: 10 }, style: { color, extra: 'a' } },
    { rect: { x: x1, y: 0, w: 10, h: 10 }, style: { color, extra: 'a' } }] } });
  const props = { unit: { restated: ['color'], originOnly: ['extra'] } };
  const same = partItems(spec, mk(5, 20, 'red'), mk(100, 115, 'red'), props, anchors);
  assert.equal(cellVerdict(same.map((i) => i.status)), 'pass');
  assert.ok(same.some((i) => i.cls === 'info' && i.status === 'na'));
  const off = partItems(spec, mk(5, 20, 'red'), mk(100, 116, 'red'), props, anchors);
  assert.equal(cellVerdict(off.map((i) => i.status)), 'fail');
  const col = partItems(spec, mk(5, 20, 'red'), mk(5, 20, 'blue'), props, anchors);
  assert.ok(col.some((i) => i.cls === 'style' && i.status === 'differ'));
  const none = partItems({ roles: [] }, {}, {}, {}, anchors);
  assert.equal(cellVerdict(none.map((i) => i.status)), 'not-comparable');
});
