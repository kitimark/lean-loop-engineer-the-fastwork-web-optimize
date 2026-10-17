import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { loadAnchors, loadGen } from '../src/spec.mjs';
import { fwcoreBin } from '../src/verdict.mjs';
import { portOf } from '../src/run.mjs';
import { HOW, gapCells, gapEdges, probeVariants, realizeChromium, realizeWebkit, zoomLevel } from '../src/gaps/cells.mjs';
import { judgeRun, modelCheck, observedEnv, pairOf } from '../src/gaps/judge.mjs';
import { judgeDevice } from '../src/gaps/devicejudge.mjs';
import { probeHtml } from '../src/gaps/probe.mjs';

const { gen } = loadGen();
const anchors = loadAnchors();

// Tests that ask Lean (fwcore) need the binary: FW_CORE_BIN or lean/.lake/build/bin/fwcore (CI builds it with `lake build fwcore`).
const hasCore = (() => { try { return existsSync(fwcoreBin()); } catch { return false; } })();
const withCore = (name, fn) => test(name, { skip: hasCore ? false : 'fwcore is not built (set FW_CORE_BIN)' }, fn);

test('the gap cells are the 8 probes of the two Lean blocks, and the edges are the 4 gaps', () => {
  const cells = gapCells(gen);
  assert.equal(cells.length, 8);
  assert.deepEqual(cells.filter((c) => c.kind === 'fractional').map((c) => c.probe.width), [600.5, 640.5, 860.5, 1000.5]);
  assert.equal(cells.filter((c) => c.kind === 'cross').length, 4);
  assert.deepEqual(gapEdges(gen), [600, 640, 860, 1000]);
  for (const c of cells) assert.ok(HOW[`${c.kind}/chromium`] && HOW[`${c.kind}/playwright-webkit`], `${c.kind} has a display line per engine`);
});

test('realizeChromium: the fractional width is built at Lean\'s DPR 2 by zoom 2 and a whole override; nothing is rewritten', () => {
  for (const c of gapCells(gen)) {
    const e = realizeChromium(c.probe);
    // Lean's environment is untouched
    assert.equal(e.width, c.probe.width);
    assert.equal(e.dpr, c.probe.dpr);
    assert.equal(e.height, c.probe.height);
    if (c.kind === 'fractional') {
      assert.equal(c.probe.dpr, 2);
      assert.equal(e.zoom, 2);
      assert.deepEqual(e.override, { width: c.probe.width * 2, height: c.probe.height * 2, deviceScaleFactor: 1 });
      assert.ok(Number.isInteger(e.override.width) && e.override.width % 2 === 1, 'override is 2N+1');
      // the page then sees P / (DSF x zoom) = Lean's width and DSF x zoom = Lean's DPR
      assert.equal(e.override.width / (e.override.deviceScaleFactor * e.zoom), c.probe.width);
      assert.equal(e.override.deviceScaleFactor * e.zoom, c.probe.dpr);
    } else {
      assert.equal(e.zoom, 1);
      assert.deepEqual(e.override, { width: c.probe.width, height: c.probe.height, deviceScaleFactor: c.probe.dpr });
    }
  }
  const p = gapCells(gen)[0].probe;
  assert.throws(() => realizeChromium({ ...p, width: 600.25 }), /not whole/);
  assert.deepEqual(realizeWebkit(p), { width: p.width, height: p.height, deviceWidth: p.deviceWidth, deviceHeight: p.deviceHeight, dpr: p.dpr, hover: p.hover, pointer: p.pointer, reducedMotion: p.reducedMotion, colorScheme: p.colorScheme });
});

test('zoomLevel: 200% is log(2)/log(1.2) and 100% is 0', () => {
  assert.ok(Math.abs(zoomLevel(2) - 3.8017840169239308) < 1e-12);
  assert.equal(zoomLevel(1), 0);
});

test('portOf: Chromium, and the WebKit port by platform (Apple on macOS, GLib elsewhere)', () => {
  assert.equal(portOf('chromium', 'linux'), 'chromium');
  assert.equal(portOf('playwright-webkit', 'darwin'), 'webkit-apple');
  assert.equal(portOf('playwright-webkit', 'linux'), 'webkit-glib');
});

test('probeVariants: one vp= and one aim= request per gap target, in matrix order', () => {
  const v = probeVariants(gen);
  assert.deepEqual(v.map((x) => x.id), ['vp-width-600.5', 'vp-width-640.5', 'vp-width-860.5', 'vp-width-1000.5', 'aim-600.5', 'aim-640.5', 'aim-860.5', 'aim-1000.5']);
  assert.equal(v[0].query, 'vp=width%3D600.5');
  assert.equal(v[4].query, 'aim=600.5');
  assert.deepEqual(v.map((x) => x.aimed), [600.5, 640.5, 860.5, 1000.5, 600.5, 640.5, 860.5, 1000.5]);
});

test('the probe page embeds the two shared in-page functions, the config and the viewport variants', () => {
  const html = probeHtml({ conditions: [], neutral: [], edges: [600] });
  assert.match(html, /function gapFacts/);
  assert.match(html, /function collectInPage/);
  assert.match(html, /"edges":\[600\]/);
  assert.match(html, /<meta name="viewport" id="vp"/);
  assert.match(html, /q\.get\('vp'\)/);
  assert.match(html, /q\.get\('aim'\)/);
  // the viewport script runs in the head, before the body script that sends the first record
  assert.ok(html.indexOf("q.get('aim')") < html.indexOf('const CFG'));
});

// -- Lean (fwcore) judging ------------------------------------------------------------------------------------------------
const gap = (mediaWidth, pointer, over = {}) => ({
  mediaWidth, innerHeight: 900, dpr: 2, screenWidth: mediaWidth,
  pointer: { hover: true, hoverNone: false, pointerFine: true, pointerCoarse: false, pointerNone: false, ...pointer },
  ...over,
});
const rec = (w, pointer) => ({ req: { w }, gap: gap(w, pointer) });
const TOUCH = { hover: false, hoverNone: true, pointerFine: false, pointerCoarse: true };

test('pairOf and observedEnv read the page\'s answers into Lean\'s request form', () => {
  assert.deepEqual(pairOf(TOUCH), { hover: 'none', pointer: 'coarse' });
  assert.deepEqual(pairOf({ hover: true, pointerFine: true }), { hover: 'hover', pointer: 'fine' });
  assert.equal(observedEnv({ mediaWidth: 601, pointer: {} }), null, 'no pair answered: unreadable');
  assert.deepEqual(observedEnv(gap(601, {})), { width: 601, height: 900, deviceWidth: 601, dpr: 2, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' });
});

withCore('modelCheck (Lean reach): whole widths on Apple primary pairs hold; a fraction or a foreign pair contradicts the model', () => {
  assert.equal(modelCheck('webkit-apple', [rec(601, {}), rec(1001, {}), rec(430, TOUCH)]).verdict, 'pass');
  const frac = modelCheck('webkit-apple', [rec(601, {}), rec(600.5, {})]);
  assert.equal(frac.verdict, 'fail');
  assert.equal(frac.contradicted.length, 1);
  assert.equal(frac.contradicted[0].mediaWidth, 600.5);
  assert.equal(modelCheck('webkit-apple', [rec(430, { pointerFine: false, pointerCoarse: true })]).verdict, 'fail', 'hover/coarse is not an Apple primary pair');
  assert.equal(modelCheck('webkit-apple', []).verdict, 'not-comparable');
  const unreadable = modelCheck('webkit-apple', [{ req: {}, gap: { mediaWidth: 601, pointer: {} } }]);
  assert.equal(unreadable.unreadable, 1);
  assert.notEqual(unreadable.verdict, 'pass');
});

// A synthetic arm that answers exactly what the Lean probe expects, so a cell is only ever unreachable or achieved by the port.
const armFor = (p, media = p.width) => ({
  raw: {
    viewport: { innerWidth: Math.floor(media), innerHeight: p.height, dpr: p.dpr, vvWidth: media }, observed: { dprWanted: 0, widthWanted: 0, reducedMotion: false, dark: false },
    truth: { ...p.expect }, truthLegacy: {}, neutral: { ...p.expectNeutral }, parts: {},
    gap: gap(media, p.pointer === 'coarse' ? TOUCH : {}, { dpr: p.dpr }),
  },
});
const synthRun = (port, cells, media) => ({
  header: { port, props: null },
  probes: cells.map((c) => ({ id: c.id, block: c.block, env: realizeWebkit(c.probe), orig: armFor(c.probe, media(c)), rewrite: armFor(c.probe, media(c)) })),
});

withCore('judgeRun (Lean gate.state): fractional cells on WebKit are unreachable with the proved reason, whichever port', () => {
  const cells = gapCells(gen).filter((c) => c.kind === 'fractional');
  for (const port of ['webkit-apple', 'webkit-glib']) {
    const out = judgeRun({ cells, engine: 'playwright-webkit', run: synthRun(port, cells, (c) => Math.ceil(c.probe.width)), anchors, deviceEdges: gen.edgePairs.deviceWidth, parts: [] });
    assert.equal(out.port, port);
    assert.deepEqual(out.cells.map((c) => c.verdict), Array(4).fill('unreachable:whole-width'));
    assert.deepEqual(out.cells.map((c) => c.reach), Array(4).fill('whole-width'));
    assert.equal(out.blocks['fractional-gaps'].verdict, 'unreachable:whole-width');
    assert.equal(out.blocks['fractional-gaps'].unreachable, 4);
  }
});

withCore('judgeRun: cross cells are reached or unreachable by the port\'s primary pairs, and a Chromium fraction is reachable', () => {
  const cross = gapCells(gen).filter((c) => c.kind === 'cross');
  const out = judgeRun({ cells: cross, engine: 'playwright-webkit', run: synthRun('webkit-apple', cross, (c) => c.probe.width), anchors, deviceEdges: gen.edgePairs.deviceWidth, parts: [] });
  const byPair = Object.fromEntries(out.cells.map((c) => [`${c.env.hover}/${c.env.pointer}@${c.env.width}`, c.verdict]));
  for (const [k, v] of Object.entries(byPair)) {
    if (k.startsWith('none/fine') || k.startsWith('hover/coarse')) assert.equal(v, 'unreachable:primary-pair', k);
    else assert.notEqual(v, 'unreachable:primary-pair', k);
  }
  const frac = gapCells(gen).filter((c) => c.kind === 'fractional');
  const ch = judgeRun({ cells: frac, engine: 'chromium', run: synthRun('chromium', frac, (c) => c.probe.width), anchors, deviceEdges: gen.edgePairs.deviceWidth, parts: [] });
  assert.ok(ch.cells.every((c) => c.reach === null), 'Chromium can build width x dpr whole');
});

// -- the phone-session pass rule on synthetic records --------------------------------------------------------------------
const allPointer = (o = {}) => ({
  hover: false, hoverNone: true, pointerFine: false, pointerCoarse: true, pointerNone: false,
  anyHoverHover: false, anyHoverNone: true, anyPointerFine: false, anyPointerCoarse: true, anyPointerNone: false,
  noneFine: false, hoverCoarse: false, noneCoarse: true, hoverFine: false, touchArm: true, ...o,
});
const lean = (w, hover, pointer) => gen.matrix.probes.find((q) => q.width === w && q.deviceWidth === w && q.hover === hover && q.pointer === pointer && q.reducedMotion === 'no-preference' && q.colorScheme === 'light');
const phoneRec = (label, seq, w, over = {}, vec = lean(430, 'none', 'coarse')) => ({
  label, seq, gap: { mediaWidth: w, innerHeight: 900, dpr: 3, screenWidth: w, vvWidth: w, pointer: allPointer(over) },
  truth: { ...vec.expect }, neutral: { ...vec.expectNeutral }, observed: { reducedMotion: false, dark: false },
});
const check = (r, letter) => r.checks.find((c) => c.id.startsWith(letter));

withCore('judgeDevice: records equal to the Simulator, to Lean, and with a touchArm that follows the width, pass', () => {
  assert.ok(lean(430, 'none', 'coarse'), 'the matrix has a 430 touch probe');
  const sim = [phoneRec('sim', 0, 430)];
  const r = judgeDevice({ device: [phoneRec('p100', 0, 430), phoneRec('p100', 1, 430)], sim, gen });
  assert.equal(r.pass, true, JSON.stringify(r.checks));
});

withCore('judgeDevice X: touchArm is not compared with the Simulator\'s width, so a wider record with its own touchArm still passes X', () => {
  const sim = [phoneRec('sim', 0, 430)];
  const wide = lean(1201, 'none', 'coarse');
  if (!wide) return; // the matrix has no 1201 touch vector: nothing to check here
  const r = judgeDevice({ device: [phoneRec('wide', 0, 1201, { touchArm: false }, wide)], sim, gen });
  assert.equal(check(r, 'X').ok, true, JSON.stringify(check(r, 'X')));
  assert.equal(check(r, 'T').ok, true, JSON.stringify(check(r, 'T')));
});

withCore('judgeDevice: a fractional media width, a different primary pair, a wrong condition or a wrong touchArm fails', () => {
  const sim = [phoneRec('sim', 0, 430)];
  assert.equal(check(judgeDevice({ device: [phoneRec('z', 0, 430.5)], sim, gen }), 'W').ok, false);
  assert.equal(check(judgeDevice({ device: [phoneRec('z', 0, 430, { hover: true, hoverNone: false })], sim, gen }), 'X').ok, false);
  const bad = phoneRec('z', 0, 430); bad.truth = { ...bad.truth, wLe480: !bad.truth.wLe480 };
  const r = judgeDevice({ device: [bad], sim, gen });
  assert.equal(check(r, 'L').ok, false);
  assert.equal(r.pass, false);
  assert.equal(check(judgeDevice({ device: [phoneRec('z', 0, 430, { touchArm: false })], sim, gen }), 'T').ok, false, 'touchArm false at 430 touch contradicts Lean');
  assert.equal(judgeDevice({ device: [], sim, gen }).pass, false);
});

withCore('judgeDevice: a mouse-labelled record may differ in any-* only', () => {
  const sim = [phoneRec('sim', 0, 430)];
  const mouse = phoneRec('mouse-1', 0, 430, { anyHoverHover: true, anyHoverNone: false, anyPointerFine: true });
  assert.equal(check(judgeDevice({ device: [mouse], sim, gen }), 'X').ok, true);
  const plain = phoneRec('p', 0, 430, { anyHoverHover: true, anyHoverNone: false });
  assert.equal(check(judgeDevice({ device: [plain], sim, gen }), 'X').ok, false);
});
