// The gate's decisions are Lean's (lean/Fw/Gate); these tests run them through the fwcore binary, so they check the
// binary is current, the request shapes of verdict.mjs, and the display values verdict.mjs attaches.
// Needs lean/.lake/build/bin/fwcore (cd lean && lake build fwcore).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { call, cellVerdicts, context, evaluate, reach, styleEq, tallies } from '../src/verdict.mjs';
import { rectDecided } from '../src/summary.mjs';

const GOLDEN = join(resolve(dirname(fileURLToPath(import.meta.url)), '../../..'), 'packages/contracts/golden/gate');
const lines = (f) => readFileSync(join(GOLDEN, f), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('golden: the binary answers the saved-run cases as Lean does', () => {
  const cases = JSON.parse(readFileSync(join(GOLDEN, 'cases.json'), 'utf8'));
  const want = lines('gate.jsonl');
  assert.equal(cases.length, want.length);
  const got = call(cases.map((c) => c.request));
  cases.forEach((c, i) => { assert.equal(want[i].name, c.name); assert.deepEqual(got[i], want[i].response, c.name); });
});

test('golden: the literal cases, refusals included', () => {
  const all = lines('literal.jsonl');
  const ok = all.filter((c) => c.response.error === undefined);
  const got = call(ok.map((c) => c.request));
  ok.forEach((c, i) => assert.deepEqual(got[i], c.response, c.name));
  for (const c of all.filter((x) => x.response.error !== undefined)) assert.throws(() => call([c.request]), new RegExp(c.response.error.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')), c.name);
});

test('cellVerdict: the one rule', () => {
  assert.deepEqual(cellVerdicts([[], ['na', 'na'], ['equal', 'equal'], ['equal', 'na', 'equal'], ['equal', 'differ'], ['equal', 'missing'], ['na', 'missing']]),
    ['not-comparable', 'not-comparable', 'pass', 'pass', 'fail', 'fail', 'fail']);
});

test('tally: rollup and table cells', () => {
  assert.deepEqual(tallies([
    { verdicts: ['pass', 'not-comparable', 'pass'] }, { verdicts: ['pass', 'fail'] }, { verdicts: ['not-comparable'] }, { verdicts: [] }, { verdicts: [], block: true },
  ]), [
    { verdict: 'pass', failing: 0, total: 2, unreachable: 0 }, { verdict: 'fail', failing: 1, total: 2, unreachable: 0 },
    { verdict: 'not-comparable', failing: 0, total: 0, unreachable: 0 },
    { verdict: 'not-comparable', failing: 0, total: 0, unreachable: 0 }, { verdict: 'not-run', failing: 0, total: 0, unreachable: 0 },
  ]);
});

test('tally: unreachable verdicts are neither pass nor fail', () => {
  assert.deepEqual(tallies([
    { verdicts: ['unreachable:whole-width', 'pass'] }, { verdicts: ['unreachable:primary-pair', 'fail'] },
    { verdicts: ['unreachable:whole-width', 'unreachable:primary-pair'], block: true },
  ]), [
    { verdict: 'pass', failing: 0, total: 1, unreachable: 1 }, { verdict: 'fail', failing: 1, total: 1, unreachable: 1 },
    { verdict: 'unreachable:primary-pair', failing: 0, total: 0, unreachable: 2 },
  ]);
});

test('reach: WebKit cannot reach a fractional width or a cross hover/pointer pair; Chromium needs whole device px', () => {
  const env = (width, dpr, hover, pointer) => ({ width, height: 900, deviceWidth: width, dpr, hover, pointer, reducedMotion: 'no-preference', colorScheme: 'light' });
  const envs = [env(600.5, 2, 'hover', 'fine'), env(1200, 1, 'hover', 'coarse'), env(1200, 1, 'none', 'none'), env(600.5, 1.25, 'none', 'coarse')];
  assert.deepEqual(reach('webkit-apple', envs), ['whole-width', 'primary-pair', 'primary-pair', 'whole-width']);
  assert.deepEqual(reach('webkit-glib', envs), ['whole-width', 'primary-pair', null, 'whole-width']);
  assert.deepEqual(reach('chromium', envs), [null, null, null, 'width-dpr']);
  assert.deepEqual(reach('chromium', []), []);
  assert.throws(() => reach('gecko', envs), /unknown port gecko/);
});

test('styleValueEq: exact, or numbers within 1/1000 (exact decimals, inclusive) with equal skeletons', () => {
  assert.deepEqual(styleEq([
    ['120px', '120px'], ['120px', '120.0009px'], ['120px', '120.001px'], ['120px', '120.002px'], ['120px', '120em'],
    ['matrix(1, 0, 0, 1, -5, 0)', 'matrix(1, 0, 0, 1, -5.0005, 0)'], ['rgb(0, 0, 0)', 'rgb(0, 0, 1)'], ['auto', undefined], ['auto', '0px'],
  ]), [true, true, true, false, false, true, false, false, false]);
});

// A small part: a frame (width only) and two units boxed relative to the frame's first item.
const anchors = {
  style: { skipPrefixes: [{ prefix: 'animation', why: 'motion' }], skipSets: { ld: { props: ['width'], why: 'derived from the box' } } },
  parts: { p: { roles: [
    { role: 'frame', boxRel: null, dims: ['w'], skipSets: ['ld'], skipProps: [], why: 'the frame' },
    { role: 'unit', boxRel: { role: 'frame', index: 0 }, dims: ['x', 'w'], skipSets: [], skipProps: ['top'], why: 'the units' }] } },
};
const props = { p: { frame: { restated: ['width', 'animation-name'], originOnly: [] }, unit: { restated: ['color', 'top'], originOnly: ['extra'] } } };
const requested = { width: 600.5, height: 900, deviceWidth: 600.5, dpr: 2, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
const arm = ({ fx = 0, ux = [5, 20], color = 'red', extra = 'a', truth = { a: true, b: false }, observed = {}, viewport = {} } = {}) => ({
  viewport: { innerHeight: 900, screenWidth: 601, dpr: 2, ...viewport },
  observed: { widthExact: true, hoverHover: true, hoverNone: false, pointerFine: true, pointerCoarse: false, reducedMotion: false, dark: false, ...observed },
  truth, truthLegacy: { a: true, b: null }, neutral: { print: false },
  parts: { p: {
    frame: { count: 1, items: [{ rect: { x: fx, y: 0, w: 100, h: 10 }, style: { width: `${fx}px`, 'animation-name': `n${fx}` } }] },
    unit: { count: 2, items: ux.map((x) => ({ rect: { x, y: 0, w: 10, h: 10 }, style: { color, top: `${x}px`, extra } })) },
  } },
});
const ctx = context({ anchors, parts: ['p'], props, deviceEdges: [[500, 501]] });
const one = (o, r, expect = { a: true, b: false }, expectNeutral = { print: false }) => evaluate(ctx, [{ requested, orig: o, rewrite: r, expect, expectNeutral }]).states[0];

test('environment achieved: width exact; device width on the same side of every edge', () => {
  assert.deepEqual(one(arm(), arm()).dev, { orig: [], rewrite: [] });
  assert.deepEqual(one(arm({ observed: { widthExact: false } }), arm()).dev, { orig: ['width'], rewrite: [] });
  assert.deepEqual(one(arm(), arm({ observed: { pointerFine: false, pointerCoarse: true } })).dev, { orig: [], rewrite: ['pointer'] });
  assert.deepEqual(one(arm({ viewport: { screenWidth: 400 } }), arm()).dev.orig, ['deviceWidth']);
});

test('truth: the Lean row is not comparable without an achieved env or a vector', () => {
  assert.equal(one(arm(), arm()).rows['matchMedia =Lean'], 'pass');
  assert.equal(one(arm({ observed: { dark: true } }), arm()).rows['matchMedia =Lean'], 'not-comparable');
  assert.equal(one(arm(), arm(), null, null).rows['matchMedia =Lean'], 'not-comparable');
  assert.equal(one(arm(), arm(), { a: false, b: false }).rows['matchMedia =Lean'], 'fail');
  const diff = one(arm(), arm({ truth: { a: false, b: false } }));
  assert.equal(diff.rows['matchMedia orig=rewrite'], 'fail');
  assert.deepEqual(diff.truth.find((t) => t.cls === 'truth.AR' && t.key === 'a'), { cls: 'truth.AR', key: 'a', status: 'differ', fails: true, a: true, b: false });
});

test('part items: boxes relative to the reference, skipped properties never fail, info outside the verdict', () => {
  // the frame moves by 100 and the units with it; width, animation-* and top are skipped; extra is info only
  const same = one(arm({ fx: 0, ux: [5, 20], extra: 'a' }), arm({ fx: 100, ux: [105, 120], extra: 'b' }));
  assert.equal(same.rows.p, 'pass');
  assert.equal(same.compared.p, 1 + 1 + 1 + 2 * 3);
  assert.deepEqual(same.infoDiffs.p.map((x) => [x.role, x.idx, x.key, x.a, x.b]), [['unit', 0, 'extra', 'a', 'b'], ['unit', 1, 'extra', 'a', 'b']]);
  // a unit 0.75 px off against its frame fails, 0.5 px does not; display values are relative to the frame
  const off = one(arm({ fx: 0, ux: [5, 20] }), arm({ fx: 100, ux: [105.75, 120.5] }));
  assert.equal(off.rows.p, 'fail');
  assert.deepEqual(off.fails.p.map((x) => [x.cls, x.role, x.idx, x.key, x.status, x.a, x.b]), [['box', 'unit', 0, 'x', 'differ', 5, 5.75]]);
  const col = one(arm(), arm({ color: 'blue' }));
  assert.deepEqual(col.fails.p.map((x) => [x.cls, x.idx, x.key, x.a, x.b]), [['style', 0, 'color', 'red', 'blue'], ['style', 1, 'color', 'red', 'blue']]);
  // a role absent on one arm: count missing, shown with null
  const gone = arm(); delete gone.parts.p.unit;
  assert.deepEqual(one(arm(), gone).fails.p.map((x) => [x.cls, x.role, x.status, x.a, x.b]), [['count', 'unit', 'missing', 2, null]]);
});

test('state verdict: a part failure fails the state; an unreachable state on WebKit has no pass, fail or failing item', () => {
  const col = one(arm(), arm({ color: 'blue' }));
  assert.equal(col.rows['matchMedia =Lean'], 'pass');
  assert.equal(col.reach, null);
  assert.equal(col.verdict, 'fail');
  const wk = evaluate(context({ anchors, parts: ['p'], props, deviceEdges: [[500, 501]], port: 'webkit-apple' }),
    [{ requested, orig: arm(), rewrite: arm({ color: 'blue' }), expect: { a: true, b: false }, expectNeutral: { print: false } }]).states[0];
  assert.equal(wk.reach, 'whole-width');
  assert.equal(wk.verdict, 'unreachable:whole-width');
  assert.deepEqual(Object.values(wk.rows), Array(4).fill('unreachable:whole-width'));
  assert.deepEqual(wk.fails.p, []);
  assert.ok(wk.truth.every((t) => !t.fails));
});

test('sweep hysteresis counts', () => {
  const { stale } = evaluate(ctx, [], [{ after: arm(), fresh: arm() }, { after: arm({ ux: [5, 21] }), fresh: arm() }]);
  assert.deepEqual(stale, [{ compared: 9, differ: 0 }, { compared: 9, differ: 1 }]);
});

test('anchors that drop a comparison without a reason are refused', () => {
  const bad = { ...anchors, style: { ...anchors.style, skipPrefixes: [{ prefix: 'animation', why: '' }] } };
  assert.throws(() => evaluate({ ...ctx, anchors: bad }, [{ requested, orig: arm(), rewrite: arm() }]), /without a reason/);
});

test('page-root anchor: each arm scrollWidth <= the viewport the engines give (the requested width rounded up), judged by Lean (Fw.Gate.PageRoot)', () => {
  const rootAnchors = { style: anchors.style, parts: { 'engine.scroll': { roles: [{ role: 'pageRoot', boxRel: null, dims: [], skipSets: [], skipProps: [], why: 'the page root' }] } } };
  const rootCtx = context({ anchors: rootAnchors, parts: ['engine.scroll'], props: {}, deviceEdges: [[500, 501]] });
  const req = { ...requested, width: 430, deviceWidth: 430 };
  const rootArm = (viewport) => ({ ...arm({ viewport }), parts: { 'engine.scroll': { pageRoot: { count: 1, items: [{}] } } } });
  const run = (o, r) => evaluate(rootCtx, [{ requested: req, orig: rootArm(o), rewrite: rootArm(r), expect: { a: true, b: false }, expectNeutral: { print: false } }]).states[0];
  const equal = run({ scrollWidth: 430 }, { scrollWidth: 430 });
  assert.equal(equal.rows['engine.scroll'], 'pass');
  assert.equal(equal.compared['engine.scroll'], 2);
  // the layout viewport widened (run 39130842058): innerWidth would be 645 too, the requested width is not
  const wide = run({ scrollWidth: 430 }, { scrollWidth: 645 });
  assert.equal(wide.verdict, 'fail');
  assert.deepEqual(wide.fails['engine.scroll'].map((x) => [x.cls, x.role, x.key, x.status, x.a, x.b]), [['box', 'pageRoot', 'scrollWidth<=requestedWidth', 'differ', 430, 645]]);
  // an original that overflows is no control; an arm that did not report is missing; nobody reporting adds no item
  assert.equal(run({ scrollWidth: 645 }, { scrollWidth: 645 }).compared['engine.scroll'], 1);
  assert.equal(run({ scrollWidth: 430 }, {}).fails['engine.scroll'][0].status, 'missing');
  assert.equal(run({}, {}).compared['engine.scroll'], 1);
  // a fractional request gets the next whole px (engines.mjs): 600.5 -> 601 fits, 602 does not
  const frac = (o, r) => evaluate(rootCtx, [{ requested: { ...req, width: 600.5 }, orig: rootArm(o), rewrite: rootArm(r), expect: { a: true, b: false }, expectNeutral: { print: false } }]).states[0];
  assert.equal(frac({ scrollWidth: 601 }, { scrollWidth: 601 }).rows['engine.scroll'], 'pass');
  assert.equal(frac({ scrollWidth: 601 }, { scrollWidth: 602 }).verdict, 'fail');
  assert.equal(frac({ scrollWidth: 602 }, { scrollWidth: 602 }).compared['engine.scroll'], 1);
});

test('margin rule: readState carries the rect-decided cells with both style values, and rectDecided counts them', () => {
  const literal = lines('literal.jsonl');
  const run = (name) => {
    const q = literal.find((c) => c.name === name).request;
    const ctx = context({ anchors: q.anchors, parts: q.parts, props: q.props, deviceEdges: q.deviceEdges, port: null, variants: null });
    return evaluate(ctx, q.states).states[0];
  };
  const strut = run('margin rule: original non-fixed, rewrite non-fixed, styles differ, rect equal');
  const ofNode = (ev) => ev.fails.m.filter((it) => it.role === 'node');
  assert.deepEqual(ofNode(strut), []);
  assert.equal(strut.fails.m.filter((it) => it.role === 'bare').length, 1);
  assert.deepEqual(strut.byRect.m.map(({ cls, role, idx, key, status, styleStatus, a, b }) => ({ cls, role, idx, key, status, styleStatus, a, b })),
    [{ cls: 'style', role: 'node', idx: 0, key: 'margin-inline-start', status: 'equal', styleStatus: 'differ', a: '96px', b: '0px' }]);
  const acc = { cells: 0, styleDiffer: [] };
  rectDecided(acc, 'probe-x', strut, ['m'], []);
  assert.equal(acc.cells, 1);
  assert.deepEqual(acc.styleDiffer, [{ at: 'probe-x', node: 'm/node[0]', key: 'margin-inline-start', orig: '96px', rewrite: '0px', styleStatus: 'differ', rect: 'equal' }]);
  const masked = { cells: 0, styleDiffer: [] };
  rectDecided(masked, 'probe-x', strut, ['m'], [{ part: 'm', role: 'node', idx: 0 }]);
  assert.deepEqual(masked, { cells: 0, styleDiffer: [] });
  const fixed = run('margin rule: original fixed, rewrite non-fixed, styles differ, rect equal');
  assert.deepEqual(fixed.byRect.m, []);
  assert.equal(ofNode(fixed).length, 1);
  const rectFail = run('margin rule: original non-fixed, rewrite non-fixed, styles equal, rect differs');
  assert.ok(ofNode(rectFail).some((it) => it.key === 'margin-inline-start' && it.status === 'differ'));
  assert.equal(rectFail.rows.m, 'fail');
});
