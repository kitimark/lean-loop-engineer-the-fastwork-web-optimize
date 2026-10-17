import test from 'node:test';
import assert from 'node:assert/strict';
import { loadGen } from '../src/spec.mjs';
import { gapCells, gapEdges, realizeEnv, zoomLevel, WEBKIT_PRIMARY_PAIRS } from '../src/gaps/cells.mjs';
import { crossEvidence, fractionalEvidence, gapCheck, pairOf } from '../src/gaps/judge.mjs';
import { judgeDevice } from '../src/gaps/devicejudge.mjs';
import { probeHtml } from '../src/gaps/probe.mjs';

const { gen } = loadGen();

test('the gap cells are the 8 probes of the two Lean blocks, and the edges are the 4 gaps', () => {
  const cells = gapCells(gen);
  assert.equal(cells.length, 8);
  assert.deepEqual(cells.filter((c) => c.kind === 'fractional').map((c) => c.probe.width), [600.5, 640.5, 860.5, 1000.5]);
  assert.equal(cells.filter((c) => c.kind === 'cross').length, 4);
  assert.deepEqual(gapEdges(gen), [600, 640, 860, 1000]);
});

test('realizeEnv: a fractional width gets zoom 2 and dpr 2 with a whole override; whole widths are unchanged', () => {
  for (const c of gapCells(gen)) {
    const e = realizeEnv(c.probe);
    if (c.kind === 'fractional') {
      assert.equal(e.zoom, 2);
      assert.equal(e.dpr, 2);
      assert.ok(Number.isInteger(e.width * e.zoom) && Number.isInteger(e.height * e.zoom));
      assert.ok(Number.isInteger(e.width * e.dpr), 'width x dpr is whole: a browser can make it');
    } else {
      assert.equal(e.zoom, undefined);
      assert.equal(e.dpr, c.probe.dpr);
    }
  }
  assert.throws(() => realizeEnv({ id: 'x', width: 600.25 }));
});

test('zoomLevel: 200% is log(2)/log(1.2) and 100% is 0', () => {
  assert.ok(Math.abs(zoomLevel(2) - 3.8017840169239308) < 1e-12);
  assert.equal(zoomLevel(1), 0);
});

const gap = (mediaWidth, over = {}) => ({
  mediaWidth, edges: Object.fromEntries([600, 640, 860, 1000].map((n) => [n, { le: mediaWidth <= n, ge1: mediaWidth >= n + 1, maxWidth: mediaWidth <= n, minWidth1: mediaWidth >= n + 1 }])),
  pointer: { hover: true, hoverNone: false, pointerFine: true, pointerCoarse: false, pointerNone: false, ...over },
});

test('gapCheck: 600.5 is a gap only when neither side matches and the media width is exact', () => {
  assert.equal(gapCheck(gap(600.5), 600.5).ok, true);
  assert.equal(gapCheck(gap(601), 600.5).ok, false);
  assert.equal(gapCheck(gap(600), 600.5).ok, false);
  assert.equal(gapCheck(undefined, 600.5).ok, false);
});

test('fractionalEvidence: whole widths pass; a fraction or a gap fails; no records fail', () => {
  assert.equal(fractionalEvidence([{ gap: gap(601) }, { gap: gap(1001) }]).ok, true);
  assert.equal(fractionalEvidence([{ gap: gap(601) }, { gap: gap(600.5) }]).ok, false);
  assert.equal(fractionalEvidence([]).ok, false);
  assert.equal(fractionalEvidence([{ gap: { mediaWidth: null, edges: {} } }]).ok, false);
});

test('crossEvidence: only the two Apple pairs pass', () => {
  const rec = (o) => ({ gap: gap(430, o) });
  const touch = { hover: false, hoverNone: true, pointerFine: false, pointerCoarse: true };
  assert.deepEqual(WEBKIT_PRIMARY_PAIRS, [['hover', 'fine'], ['none', 'coarse']]);
  assert.equal(crossEvidence([rec({}), rec(touch)]).ok, true);
  assert.equal(crossEvidence([rec({ pointerFine: false, pointerCoarse: true })]).ok, false, 'hover/coarse is not an Apple pair');
  assert.equal(crossEvidence([rec({ hover: false, hoverNone: true })]).ok, false, 'none/fine is not an Apple pair');
  assert.deepEqual(pairOf(touch), { hover: 'none', pointer: 'coarse' });
});

test('the probe page embeds the two shared in-page functions and the config', () => {
  const html = probeHtml({ conditions: [], neutral: [], edges: [600] });
  assert.match(html, /function gapFacts/);
  assert.match(html, /function collectInPage/);
  assert.match(html, /"edges":\[600\]/);
});

// -- the phone-session pass rule on synthetic records --------------------------------------------------------------------
const allPointer = (o = {}) => ({
  hover: false, hoverNone: true, pointerFine: false, pointerCoarse: true, pointerNone: false,
  anyHoverHover: false, anyHoverNone: true, anyPointerFine: false, anyPointerCoarse: true, anyPointerNone: false,
  noneFine: false, hoverCoarse: false, noneCoarse: true, hoverFine: false, touchArm: true, ...o,
});
const lean430 = () => { const p = gen.matrix.probes.find((q) => q.width === 430 && q.deviceWidth === 430 && q.hover === 'none' && q.pointer === 'coarse' && q.reducedMotion === 'no-preference' && q.colorScheme === 'light'); return p; };
const phoneRec = (label, seq, w, over = {}) => {
  const p = lean430();
  return { label, seq, gap: { ...gap(w), screenWidth: 430, vvWidth: w, pointer: allPointer(over) }, truth: { ...p.expect }, neutral: { ...p.expectNeutral }, observed: { reducedMotion: false, dark: false } };
};

test('judgeDevice: records equal to the Simulator and to Lean pass', () => {
  assert.ok(lean430(), 'the matrix has a 430 touch probe');
  const sim = [phoneRec('sim', 0, 430)];
  const r = judgeDevice({ device: [phoneRec('p100', 0, 430), phoneRec('p100', 1, 430)], sim, gen });
  assert.equal(r.pass, true, JSON.stringify(r.checks));
});

test('judgeDevice: a fractional media width, a different primary pair, or a wrong condition fails', () => {
  const sim = [phoneRec('sim', 0, 430)];
  assert.equal(judgeDevice({ device: [phoneRec('z', 0, 430.5)], sim, gen }).checks.find((c) => c.id.startsWith('W')).ok, false);
  assert.equal(judgeDevice({ device: [phoneRec('z', 0, 430, { hover: true, hoverNone: false })], sim, gen }).checks.find((c) => c.id.startsWith('X')).ok, false);
  const bad = phoneRec('z', 0, 430); bad.truth = { ...bad.truth, wLe480: !bad.truth.wLe480 };
  const r = judgeDevice({ device: [bad], sim, gen });
  assert.equal(r.checks.find((c) => c.id.startsWith('L')).ok, false);
  assert.equal(r.pass, false);
  assert.equal(judgeDevice({ device: [], sim, gen }).pass, false);
});

test('judgeDevice: a mouse-labelled record may differ in any-* only', () => {
  const sim = [phoneRec('sim', 0, 430)];
  const mouse = phoneRec('mouse-1', 0, 430, { anyHoverHover: true, anyHoverNone: false, anyPointerFine: true });
  assert.equal(judgeDevice({ device: [mouse], sim, gen }).checks.find((c) => c.id.startsWith('X')).ok, true);
  const plain = phoneRec('p', 0, 430, { anyHoverHover: true, anyHoverNone: false });
  assert.equal(judgeDevice({ device: [plain], sim, gen }).checks.find((c) => c.id.startsWith('X')).ok, false);
});
