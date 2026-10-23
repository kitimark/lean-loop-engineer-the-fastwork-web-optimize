import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { offsets } from '../src/pathpix.mjs';
import { BOX_EXPR, FREEZE_EXPR, HOLD_EXPR, VIDEO_EXPR, IMAGES_READY_EXPR, NEAR_IMAGES_EXPR, pathSearch } from '../src/pathpix-page.mjs';
import { encodePng, decodePng, cropImage, sameImage } from '../src/pathpix-png.mjs';
import { analyzeLane, table } from '../src/pathpix-analyze.mjs';
import { magentaBox, inViewPositions } from '../src/pathpix-webkit.mjs';
import { ACCENT_SERVED_EXPR, ACCENT_SIG_EXPR, EXIT_BOX_EXPR, EXIT_GEOM_EXPR, EXIT_LIVE_EXPR, EXIT_NUDGE_EXPR, EXIT_WAIT_EXPR } from '../src/pathpix-exit-page.mjs';
import { armPin, pinAt, accentPinned, analyzeExit, analyzeDir, exitTable, exitOffsets, splitUnion, region, liveP, liveA } from '../src/pathpix-exit.mjs';
import { pathSearch as chromiumPathSearch, laneOffsets, exitOffsets as chromiumExitOffsets, armPin as chromiumArmPin, pinAt as chromiumPinAt, accentPinned as chromiumAccentPinned } from '../../measure-chromium/src/pathpix-pure.mjs';

test('the Chromium driver computes the same offsets and arm search as the Simulator lane', () => {
  for (const maxY of [0, 1, 7, 8, 4626, 5267, 123457]) assert.deepEqual(laneOffsets(maxY), offsets(maxY), `maxY ${maxY}`);
  for (const l of ['hero_copy', 'nav_bar', 'hero.countdown_face', 'morph.panel_panel']) assert.equal(chromiumPathSearch(l), pathSearch(l), l);
  assert.equal(pathSearch('hero_copy'), '?fwl=hero_copy:c');
});

test('page-side expressions are well-formed scripts', () => {
  for (const e of [BOX_EXPR, FREEZE_EXPR, HOLD_EXPR, VIDEO_EXPR, IMAGES_READY_EXPR, NEAR_IMAGES_EXPR, EXIT_BOX_EXPR, EXIT_GEOM_EXPR, EXIT_LIVE_EXPR, EXIT_NUDGE_EXPR, EXIT_WAIT_EXPR, ACCENT_SERVED_EXPR, ACCENT_SIG_EXPR]) assert.doesNotThrow(() => new Function(`return ${e}`));
});

test('png codec round-trips, crops and compares', () => {
  const img = { w: 4, h: 3, rgba: new Uint8Array(48).map((_, i) => (i * 37) & 255) };
  const back = decodePng(encodePng(img));
  assert.equal(back.w, 4); assert.equal(back.h, 3);
  assert.ok(sameImage(img, back));
  const c = cropImage(img, 1, 1, 2, 2);
  assert.equal(c.w, 2); assert.equal(c.h, 2);
  assert.deepEqual([...c.rgba.slice(0, 4)], [...img.rgba.slice(4 * 4 + 4, 4 * 4 + 8)]);
  const other = { w: 4, h: 3, rgba: img.rgba.slice() }; other.rgba[0] ^= 1;
  assert.ok(!sameImage(img, other));
});

test('magentaBox finds the marker rectangle', () => {
  const w = 10, h = 8, rgba = new Uint8Array(w * h * 4).fill(255);
  for (let y = 2; y < 6; y++) for (let x = 3; x < 9; x++) { const o = (y * w + x) * 4; rgba[o] = 255; rgba[o + 1] = 0; rgba[o + 2] = 255; }
  assert.deepEqual(magentaBox({ w, h, rgba }), [3, 2, 6, 4]);
  assert.equal(magentaBox({ w: 2, h: 2, rgba: new Uint8Array(16).fill(255) }), null);
});

function fakeLane(dir, pixels) {
  mkdirSync(join(dir, 'shots'), { recursive: true });
  const base = () => { const rgba = new Uint8Array(100 * 100 * 4).fill(255); return { w: 100, h: 100, rgba }; };
  const put = (name, img) => writeFileSync(join(dir, 'shots', name), encodePng(img));
  const mk = (arm, edit) => { const i = base(); if (edit) edit(i); for (let r = 0; r < 2; r++) put(`${arm}_0_${r}.png`, i); };
  mk('A'); mk('A2', pixels.a2); mk('P_box', pixels.p);
  const rec = { layer: 'box', boundsU: [10e6, 10e6, 20e6, 20e6], compositedBounds: null, memory: null, reasons: ['x'] };
  const row = (arm, composited) => ({ i: 0, y: 0, scrollY: 0, boxes: { box: [10e6, 10e6, 20e6, 20e6] }, files: [`shots/${arm}_0_0.png`, `shots/${arm}_0_1.png`], dprMilli: 1000, layers: composited ? [rec] : [], layerCount: composited ? 1 : 0 });
  writeFileSync(join(dir, 'manifest.json'), JSON.stringify({
    schema: 'fw.path-pix/1', engine: 'webkit', lane: 'test', run: 'test', lossless: true, compositing: 'test', dpr: 1, vw: 100, vh: 100, frame: { w: 100, h: 100 }, content: [0, 0, 100, 100],
    maxY: 0, offsets: [0], offsetIndex: [0], layers: ['box'], arms: [], samples: { A: [row('A', false)], A2: [row('A2', false)], 'P:box': [row('P_box', true)] },
  }));
}

test('analysis of a lane directory: equal frames are exact, a change inside the box is reported, one outside is too', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-pp-test-'));
  try {
    fakeLane(dir, { a2: null, p: (img) => { const o = (15 * 100 + 15) * 4; img.rgba[o] = 250; } });
    const strips = [];
    const res = analyzeLane(dir, { strips: 'changed', emit: (n, b) => strips.push([n, b.length]) });
    assert.equal(res.cells.length, 2);
    assert.equal(res.frames.length, 2);
    assert.equal(res.frames.find((f) => f.arm === 'A2').changed, 0);
    const pf = res.frames.find((f) => f.arm === 'P:box');
    assert.equal(pf.changed, 1);
    assert.deepEqual(pf.bbox, [15, 15, 16, 16]);
    const aa = res.cells.find((c) => c.kind === 'A/A'), p = res.cells.find((c) => c.kind === 'P');
    assert.equal(aa.cell.inside.changed + aa.cell.out.changed, 0);
    assert.equal(aa.cell.sameA, true);
    assert.equal(p.cell.inside.changed, 1);
    assert.equal(p.cell.out.changed, 0);
    assert.equal(p.cell.claim.compA, false);
    assert.equal(p.cell.claim.compB, true);
    assert.ok(strips.length >= 2);
    assert.match(table(res), /hero|box/);
    writeFileSync(join(dir, 'cells.json'), JSON.stringify(res));
    assert.equal(JSON.parse(readFileSync(join(dir, 'cells.json'), 'utf8')).schema, 'fw.path-pix.cells/1');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a P arm is captured only where arm A shows the layer, and the analysis reads a hole as not captured', () => {
  const frame = { w: 100, h: 100 };
  const rowsA = [{ boxes: { box: [10e6, 10e6, 20e6, 20e6] } }, { boxes: { box: [10e6, 500e6, 20e6, 20e6] } }, { boxes: {} }, null, { boxes: { box: [10e6, 90e6, 20e6, 20e6] } }];
  assert.deepEqual(inViewPositions(rowsA, 'box', 1, frame), [0, 4]);
  assert.deepEqual(inViewPositions(rowsA, 'other', 1, frame), []);
  const dir = mkdtempSync(join(tmpdir(), 'fw-pp-test-'));
  try {
    fakeLane(dir, { a2: null, p: null });
    const man = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
    man.samples['P:box'] = [null];
    man.cut = ['P:other (failed: x)'];
    writeFileSync(join(dir, 'manifest.json'), JSON.stringify(man));
    const res = analyzeLane(dir, { strips: 'none' });
    assert.equal(res.cells.filter((c) => c.kind === 'P').length, 0);
    assert.ok(res.skipped.some((x) => x.kind === 'P' && /not captured/.test(x.why)));
    assert.deepEqual(res.cut, ['P:other (failed: x)']);
    assert.match(table(res), /arms cut short/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('the Chromium driver computes the same exit offsets as the Simulator lane', () => {
  for (const [T, n] of [[0, 600], [0, 932], [300, 664], [12, 1688], [0, 1]]) assert.deepEqual(chromiumExitOffsets(T, n), exitOffsets(T, n), `${T} ${n}`);
});

test('the union split agrees with the Lean region rule pixel by pixel', () => {
  const w = 40, h = 30, del = new Uint8Array(w * h);
  for (let i = 0; i < del.length; i++) del[i] = (i * 7) % 5 === 0 ? 1 + (i % 9) : 0;
  const masks = [[5, 20, 4, 15], [12, 30, 10, 25], [33, 36, 0, 3]];
  const sp = splitUnion(del, w, h, masks);
  const want = { out: { changed: 0, maxDelta: 0 }, inside: masks.map(() => ({ changed: 0, maxDelta: 0 })) };
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const d = del[y * w + x];
    if (!d) continue;
    if (region(masks, [0, 0, 0, 0], x, y) === 'out') { want.out.changed++; want.out.maxDelta = Math.max(want.out.maxDelta, d); }
    masks.forEach((m, k) => { if (region(masks, m, x, y) === 'inside') { want.inside[k].changed++; want.inside[k].maxDelta = Math.max(want.inside[k].maxDelta, d); } });
  }
  assert.deepEqual(sp.out, want.out);
  assert.deepEqual(sp.inside.map((x) => x.raw), want.inside);
});

test('the union split leaves a pixel in another mask to that mask: only the yielding mask drops it, and it is counted once', () => {
  const w = 20, h = 20, del = new Uint8Array(w * h);
  del[5 * w + 5] = 1; del[5 * w + 12] = 3; del[12 * w + 5] = 2;
  const masks = [[0, 15, 0, 15], [10, 20, 3, 8]];
  const none = splitUnion(del, w, h, masks);
  assert.deepEqual(none.inside.map((x) => x.raw), [{ changed: 3, maxDelta: 3 }, { changed: 1, maxDelta: 3 }]);
  assert.deepEqual(none.shared, [{ changed: 0, maxDelta: 0 }, { changed: 0, maxDelta: 0 }]);
  const sp = splitUnion(del, w, h, masks, [[masks[1]], []]);
  assert.deepEqual(sp.inside.map((x) => x.raw), [{ changed: 2, maxDelta: 2 }, { changed: 1, maxDelta: 3 }], 'the other mask keeps every pixel');
  assert.deepEqual(sp.shared[0], { changed: 1, maxDelta: 3 });
  assert.deepEqual(sp.inside[0].bbox, [5, 5, 6, 13]);
  assert.equal(sp.out.changed, 0);
  assert.equal(splitUnion(del, w, h, masks, [[], [masks[0]]]).inside[1].raw.changed, 0, 'a mask told to yield drops what the first covers');
});

test('the live witnesses', () => {
  assert.equal(liveP({ live: true, variant: 'threaded', supported: true, nonDoc: 4 }), true);
  for (const bad of [null, { live: false, variant: 'threaded', supported: true, nonDoc: 4 }, { live: true, variant: 'faithful', supported: true, nonDoc: 4 }, { live: true, variant: 'threaded', supported: false, nonDoc: 4 }, { live: true, variant: 'threaded', supported: true, nonDoc: 0 }]) assert.equal(liveP(bad), false);
  assert.equal(liveA({ live: false, variant: 'faithful' }), true);
  assert.equal(liveA({ live: true, variant: 'threaded' }), false);
});

function fakeExitLane(dir, { boxes: boxes0, pEdit, pLive, a2Edit, still = false, clear = false, accentOf = () => ({ n: 1, sig: 'ssr' }), scrollOf = () => 0, coverOf = () => undefined, maxY, dateOf = () => 1000, parts }) {
  mkdirSync(join(dir, 'shots'), { recursive: true });
  const base = () => ({ w: 100, h: 100, rgba: new Uint8Array(100 * 100 * 4).fill(255) });
  const put = (name, edit) => { const i = base(); if (edit) edit(i); for (let r = 0; r < 2; r++) writeFileSync(join(dir, 'shots', `${name}_${r}.png`), encodePng(i)); };
  put('A_0'); put('A2_0', a2Edit); put('P_0', pEdit);
  const boxes = boxes0 ?? { hero_copy: [10e6, 10e6, 20e6, 20e6], 'hero.deck_article#1': [50e6, 50e6, 20e6, 20e6] };
  const accent = (arm) => { const a = accentOf(arm); return a && { shotStart: a, shotEnd: a }; };
  const row = (arm, live) => ({ accent: accent(arm), i: 0, y: 0, scrollY: scrollOf(arm), dateNow: dateOf(arm), cover: coverOf(arm), parts: parts, boxes, alpha: clear ? { hero_copy: 0, 'hero.deck_article#1': 1 } : undefined, live, files: [`shots/${arm}_0_0.png`, `shots/${arm}_0_1.png`], dprMilli: 1000, layers: [], layerCount: 0 });
  const faithful = { live: false, variant: 'faithful', supported: true, nonDoc: 0 };
  const moved = { i: 1, y: 50, scrollY: 50, boxes: { ...boxes, hero_copy: [10e6, still ? 10e6 : 5e6, 20e6, 20e6] }, live: faithful, files: [], dprMilli: 1000, layers: [], layerCount: 0 };
  writeFileSync(join(dir, 'manifest.json'), JSON.stringify({
    schema: 'fw.path-pix/1', mode: 'exit', flag: 'hero.exit:threaded', engine: 'webkit', lane: 'test', run: 'test', lossless: true, compositing: 'test', dpr: 1, vw: 100, vh: 100,
    frame: { w: 100, h: 100 }, exit: { T: 0, h: 200, v: 100, n: 100 }, offsets: [0, 1], cut: [], ...(maxY === undefined ? {} : { maxY }),
    handover: { pin: { A: { ssr: 'ssr' }, A2: { ssr: 'ssr' }, P: { ssr: 'ssr' } } },
    samples: { A: [row('A', faithful), moved], A2: [row('A2', faithful), null], P: [row('P', pLive), null] },
  }));
}
const liveOk = { live: true, variant: 'threaded', supported: true, nonDoc: 4 };
const setPx = (x, y, v = 250) => (img) => { img.rgba[(y * 100 + x) * 4] = v; };

test('exit analysis: cells per consumer, floor from A/A, outside change is L, a live witness gates P', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-pp-exit-'));
  try {
    fakeExitLane(dir, { a2Edit: setPx(15, 15), pEdit: (img) => { setPx(15, 15)(img); setPx(15, 16)(img); setPx(80, 80)(img); }, pLive: liveOk });
    const res = analyzeExit(dir, { strips: 'changed', emit: () => {} });
    const cell = (kind, key) => res.cells.find((c) => c.kind === kind && c.key === key);
    assert.equal(res.driverMoved, true);
    assert.equal(res.cells.length, 4);
    assert.deepEqual(cell('A/A', 'hero_copy').cell.inside, { changed: 1, maxDelta: 5 });
    assert.deepEqual(cell('P', 'hero_copy').cell.inside, { changed: 2, maxDelta: 5 });
    assert.deepEqual(cell('P', 'hero_copy').cell.out, { changed: 1, maxDelta: 5 });
    assert.deepEqual(cell('P', 'hero_copy').floor.inside, { changed: 1, maxDelta: 5 });
    assert.equal(cell('P', 'hero_copy').why, 'outside');
    assert.equal(cell('P', 'hero_copy').grade, 'L');
    assert.equal(cell('P', 'hero.deck_article#1').cell.inside.changed, 0);
    assert.equal(cell('P', 'hero.deck_article#1').cell.out.changed, 1);
    assert.equal(cell('P', 'hero.deck_article#1').cell.claim.props.join(), 'opacity,translate');
    assert.match(exitTable(res), /hero_copy/);
    fakeExitLane(dir, { a2Edit: null, pEdit: null, pLive: { ...liveOk, live: false } });
    const dead = analyzeExit(dir, { strips: 'none' });
    assert.ok(dead.cells.filter((c) => c.kind === 'P').every((c) => c.grade === 'invalid' && !c.live));
    assert.ok(dead.cells.filter((c) => c.kind === 'A/A').every((c) => c.grade !== 'invalid'));
    assert.equal(analyzeDir(dir, { strips: 'none' }).res.schema, 'fw.path-pix.exit/1');
    fakeExitLane(dir, { a2Edit: null, pEdit: null, pLive: liveOk, still: true });
    const frozen = analyzeExit(dir, { strips: 'none' });
    fakeExitLane(dir, { a2Edit: null, pEdit: setPx(15, 15), pLive: liveOk, clear: true });
    const clear = analyzeExit(dir, { strips: 'none' });
    assert.ok(clear.cells.every((c) => c.key !== 'hero_copy'));
    assert.ok(clear.skipped.some((x) => x.key === 'hero_copy' && x.why === 'transparent in both arms'));
    assert.equal(frozen.driverMoved, false);
    assert.ok(frozen.cells.every((c) => c.grade === 'invalid'));
    assert.ok(res.cells.every((c) => c.accentPinned && c.invalidWhy === null));
    const edits = { a2Edit: setPx(15, 15), pEdit: setPx(15, 15), pLive: liveOk };
    for (const [name, accentOf, hit] of [
      ['arm A re-created', (arm) => (arm === 'A' ? { n: 1, sig: 'live' } : { n: 1, sig: 'ssr' }), () => true],
      ['arm P two elements', (arm) => (arm === 'P' ? { n: 2, sig: 'ssr' } : { n: 1, sig: 'ssr' }), (c) => c.kind === 'P'],
      ['arm A2 unrecorded', (arm) => (arm === 'A2' ? null : { n: 1, sig: 'ssr' }), () => true],
    ]) {
      fakeExitLane(dir, { ...edits, accentOf });
      const bad = analyzeExit(dir, { strips: 'none' });
      for (const c of bad.cells) {
        assert.equal(c.accentPinned, !hit(c), `${name} ${c.kind} ${c.key}`);
        if (hit(c)) { assert.equal(c.grade, 'invalid'); assert.equal(c.invalidWhy, 'accent-unpinned'); assert.equal(c.why, null); assert.equal(c.ifAccepted, 'invalid'); assert.equal(c.absGrade, 'invalid'); }
        else assert.equal(c.invalidWhy, null);
      }
      assert.ok(bad.cells.some(hit), name);
    }
    fakeExitLane(dir, { ...edits, accentOf: (arm) => (arm === 'A2' ? { n: 1, sig: 'live' } : { n: 1, sig: 'ssr' }) });
    const noFloor = analyzeExit(dir, { strips: 'none' });
    assert.ok(noFloor.cells.filter((c) => c.kind === 'P').every((c) => !c.accentPinned && c.floor.valid === false && c.grade === 'invalid' && c.invalidWhy === 'accent-unpinned'));
    assert.equal(accentPinned('s', 's', 's', 1), true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('exit analysis: a misplaced row is invalid, an occluded layer is skipped with its reason, a change names the parts it touches', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-pp-exit2-'));
  try {
    const edits = { a2Edit: setPx(15, 15), pEdit: (img) => { setPx(15, 15)(img); setPx(15, 16)(img); setPx(80, 80)(img); }, pLive: liveOk, maxY: 4000 };
    fakeExitLane(dir, edits);
    const base = analyzeExit(dir, { strips: 'none' });
    assert.ok(base.cells.every((c) => c.accentPinned && c.invalidWhy === null), 'rows at their offsets are placed');
    assert.equal(base.maxY, 4000);
    fakeExitLane(dir, { ...edits, scrollOf: (arm) => (arm === 'A' ? 7 : 0) });
    const all = analyzeExit(dir, { strips: 'none' });
    assert.ok(all.cells.every((c) => c.grade === 'invalid' && c.invalidWhy === 'misplaced' && c.why === null && c.ifAccepted === 'invalid'));
    fakeExitLane(dir, { ...edits, scrollOf: (arm) => (arm === 'P' ? 3 : 0) });
    const pOnly = analyzeExit(dir, { strips: 'none' });
    assert.ok(pOnly.cells.filter((c) => c.kind === 'A/A').every((c) => c.invalidWhy === null && c.grade !== 'invalid'));
    assert.ok(pOnly.cells.filter((c) => c.kind === 'P').every((c) => c.invalidWhy === 'misplaced' && c.grade === 'invalid'));
    fakeExitLane(dir, { ...edits, scrollOf: (arm) => (arm === 'A2' ? 3 : 0) });
    const floorBad = analyzeExit(dir, { strips: 'none' });
    assert.ok(floorBad.cells.filter((c) => c.kind === 'P').every((c) => c.invalidWhy === 'misplaced' && c.grade === 'invalid'), 'the floor rows are checked for placement too');

    const full = { hero_copy: { n: 49, k: 49 } };
    fakeExitLane(dir, { ...edits, coverOf: () => full });
    const occ = analyzeExit(dir, { strips: 'none' });
    assert.ok(occ.cells.every((c) => c.key !== 'hero_copy'));
    assert.equal(occ.skipped.filter((x) => x.key === 'hero_copy' && x.why === 'occluded by opaque foreign content in both arms').length, 2);
    assert.ok(occ.cells.some((c) => c.key === 'hero.deck_article#1'));
    fakeExitLane(dir, { ...edits, coverOf: (arm) => (arm === 'P' ? full : { hero_copy: { n: 49, k: 48 } }) });
    assert.ok(analyzeExit(dir, { strips: 'none' }).cells.some((c) => c.kind === 'P' && c.key === 'hero_copy'), 'one arm covered, or one grid point open: graded');
    fakeExitLane(dir, { ...edits, coverOf: (arm) => (arm === 'P' ? full : undefined) });
    assert.ok(analyzeExit(dir, { strips: 'none' }).cells.some((c) => c.kind === 'P' && c.key === 'hero_copy'), 'an arm without cover data is not occluded');

    fakeExitLane(dir, { ...edits, parts: { hero_copy: [['button.cta', 14, 14, 3, 3], ['p.far', 25, 25, 4, 4]] } });
    const where = analyzeExit(dir, { strips: 'none' });
    const w = (kind, key) => where.cells.find((c) => c.kind === kind && c.key === key).where;
    assert.deepEqual(w('P', 'hero_copy'), { bbox: [15, 15, 16, 17], parts: ['button.cta'], outBbox: [80, 80, 81, 81] });
    assert.deepEqual(w('A/A', 'hero_copy'), { bbox: [15, 15, 16, 16], parts: ['button.cta'], outBbox: null });
    assert.deepEqual(w('P', 'hero.deck_article#1'), { bbox: null, parts: [], outBbox: [80, 80, 81, 81] });

    assert.deepEqual(where.clock, { values: [1000], constant: true });
    fakeExitLane(dir, { ...edits, dateOf: (arm) => (arm === 'P' ? 2000 : 1000) });
    const moving = analyzeExit(dir, { strips: 'none' });
    assert.deepEqual(moving.clock, { values: [1000, 2000], constant: false });
    assert.match(exitTable(moving), /Date\.now in every row: moves/);
    assert.match(exitTable(where), /Date\.now in every row: constant \(1000\)/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('exit analysis: a pixel inside both hero_copy and a deck card is the card cell\'s, unless the card is not graded', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-pp-shared-'));
  try {
    const boxes = { hero_copy: [10e6, 10e6, 30e6, 30e6], 'hero.deck_article#1': [25e6, 25e6, 40e6, 40e6] };
    const edits = { boxes, a2Edit: setPx(28, 28), pEdit: (img) => { setPx(28, 28)(img); setPx(15, 15)(img); }, pLive: liveOk };
    fakeExitLane(dir, edits);
    const res = analyzeExit(dir, { strips: 'none' });
    const cell = (kind, key) => res.cells.find((c) => c.kind === kind && c.key === key);
    assert.deepEqual(cell('A/A', 'hero_copy').cell.inside, { changed: 0, maxDelta: 0 });
    assert.deepEqual(cell('A/A', 'hero_copy').shared, { changed: 1, maxDelta: 5 });
    assert.equal(cell('A/A', 'hero_copy').sharedWith, 1);
    assert.deepEqual(cell('A/A', 'hero.deck_article#1').cell.inside, { changed: 1, maxDelta: 5 }, 'the card layer counts it');
    assert.equal(cell('A/A', 'hero.deck_article#1').sharedWith, 0);
    assert.deepEqual(cell('P', 'hero_copy').cell.inside, { changed: 1, maxDelta: 5 }, 'only the pixel that is not in the card mask');
    assert.deepEqual(cell('P', 'hero_copy').shared, { changed: 1, maxDelta: 5 });
    assert.equal(cell('P', 'hero_copy').grade, 'L');
    assert.equal(cell('P', 'hero_copy').why, 'text');
    assert.equal(cell('P', 'hero_copy').ifAccepted, 'L', 'strips would not help: the inside change is above the floor');
    const deckFull = { 'hero.deck_article#1': { n: 49, k: 49 } };
    fakeExitLane(dir, { ...edits, coverOf: () => deckFull });
    const open = analyzeExit(dir, { strips: 'none' });
    assert.ok(open.cells.every((c) => c.key !== 'hero.deck_article#1'), 'the card is skipped as occluded');
    assert.deepEqual(open.cells.find((c) => c.kind === 'A/A' && c.key === 'hero_copy').cell.inside, { changed: 1, maxDelta: 5 }, 'no graded card, so hero_copy keeps the pixel');
    assert.equal(open.cells.find((c) => c.kind === 'A/A' && c.key === 'hero_copy').sharedWith, 0);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

class El {
  constructor(attrs, kids = []) { this.attrs = attrs; this.kids = kids; this.parent = null; kids.forEach((k) => { k.parent = this; }); }
  get className() { return this.attrs.class ?? ''; }
  getAttribute(n) { return this.attrs[n] ?? null; }
  all() { return this.kids.flatMap((k) => [k, ...k.all()]); }
  querySelector(sel) { return this.querySelectorAll(sel)[0] ?? null; }
  querySelectorAll(sel) { return this.all().filter((e) => (sel === 'svg' ? e.attrs.tag === 'svg' : sel === 'path' ? e.attrs.tag === 'path' : sel === '[data-paint]' ? 'data-paint' in e.attrs : sel === '[data-fw="hero-accent"]' ? e.attrs['data-fw'] === 'hero-accent' : false)); }
  replaceWith(n) { const i = this.parent.kids.indexOf(this); this.parent.kids[i] = n; n.parent = this.parent; this.parent = null; }
}
const accentEl = (word, cls) => new El({ 'data-fw': 'hero-accent', class: cls, style: `width:${word}`, 'aria-label': 'you' }, [
  new El({ 'data-paint': '', style: 'top:0' }, [0, 1, 2].map(() => new El({ tag: 'svg', viewBox: `0 0 ${word} 9` }, [new El({ tag: 'path', d: `M${word}` })]))),
]);

test('the served-accent expression only reads: it compares the live accent with the served page and reports the hook', () => {
  for (const [liveWord, liveCls, hooked] of [['10', 'accent idle', true], ['20', 'accent drawingIn', true], ['10', 'accent idle', false]]) {
    const live = accentEl(liveWord, liveCls);
    if (hooked) live.attrs['data-fw-pin'] = 'accent';
    const body = new El({}, [live]);
    const served = new El({}, [accentEl('10', 'accent idle')]);
    const asked = [];
    const doc = { querySelector: (s) => body.querySelector(s), querySelectorAll: (s) => body.querySelectorAll(s) };
    const env = {
      document: doc, location: { pathname: '/', search: '?fw=hero.exit:threaded&fwpin=accent' },
      XMLHttpRequest: class { open(m, u) { asked.push(u); } send() { this.status = 200; this.responseText = 'html'; } },
      DOMParser: class { parseFromString() { return served; } },
    };
    const out = JSON.parse(new Function(...Object.keys(env), `return ${ACCENT_SERVED_EXPR}`)(...Object.values(env)));
    assert.deepEqual(asked, ['/?fw=hero.exit:threaded'], 'the server is asked for the prerendered search, without the hook');
    assert.equal(out.hooked, hooked);
    assert.equal(out.same, liveWord === '10' && liveCls === 'accent idle');
    assert.equal(body.querySelector('[data-fw="hero-accent"]'), live, 'the live element is not replaced');
    const seen = JSON.parse(new Function('document', `return ${ACCENT_SIG_EXPR}`)(doc));
    assert.deepEqual(seen, { n: 1, sig: out.live, pinned: hooked });
  }
  const only = { document: { querySelector: () => null } };
  assert.equal(JSON.parse(new Function(...Object.keys(only), `return ${ACCENT_SERVED_EXPR}`)(...Object.values(only))).hooked, false);
  const bare = { document: { querySelector: () => accentEl('1', 'a'), querySelectorAll: () => [1] }, location: { pathname: '/', search: '?fwpin=accent' }, XMLHttpRequest: class { open(m, u) { this.u = u; bareAsked.push(u); } send() { this.status = 404; } }, DOMParser: class {} };
  const bareAsked = [];
  JSON.parse(new Function(...Object.keys(bare), `return ${ACCENT_SERVED_EXPR}`)(...Object.values(bare)));
  assert.deepEqual(bareAsked, ['/'], 'a hook-only search asks for the bare page');
});

test('both lanes pin every arm the same way', () => {
  for (const [sv, a, b, n] of [['s', 's', 's', 1], ['s', 'x', 's', 1], ['s', 's', 'x', 1], ['s', 's', 's', 2], ['s', 's', 's', 0]]) assert.equal(chromiumAccentPinned(sv, a, b, n), accentPinned(sv, a, b, n));
  for (const arm of ['A', 'A2', 'P']) { assert.equal(chromiumArmPin(arm), armPin(arm)); for (let i = 0; i < 9; i++) assert.equal(chromiumPinAt(arm, i), pinAt(arm, i)); }
});
