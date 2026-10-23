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
import { EXIT_BOX_EXPR, EXIT_GEOM_EXPR, EXIT_LIVE_EXPR, EXIT_NUDGE_EXPR, EXIT_WAIT_EXPR } from '../src/pathpix-exit-page.mjs';
import { analyzeExit, analyzeDir, exitTable, exitOffsets, splitUnion, region, liveP, liveA } from '../src/pathpix-exit.mjs';
import { pathSearch as chromiumPathSearch, laneOffsets, exitOffsets as chromiumExitOffsets } from '../../measure-chromium/src/pathpix-pure.mjs';

test('the Chromium driver computes the same offsets and arm search as the Simulator lane', () => {
  for (const maxY of [0, 1, 7, 8, 4626, 5267, 123457]) assert.deepEqual(laneOffsets(maxY), offsets(maxY), `maxY ${maxY}`);
  for (const l of ['hero_copy', 'nav_bar', 'hero.countdown_face', 'morph.panel_panel']) assert.equal(chromiumPathSearch(l), pathSearch(l), l);
  assert.equal(pathSearch('hero_copy'), '?fwl=hero_copy:c');
});

test('page-side expressions are well-formed scripts', () => {
  for (const e of [BOX_EXPR, FREEZE_EXPR, HOLD_EXPR, VIDEO_EXPR, IMAGES_READY_EXPR, NEAR_IMAGES_EXPR, EXIT_BOX_EXPR, EXIT_GEOM_EXPR, EXIT_LIVE_EXPR, EXIT_NUDGE_EXPR, EXIT_WAIT_EXPR]) assert.doesNotThrow(() => new Function(`return ${e}`));
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

test('the live witnesses', () => {
  assert.equal(liveP({ live: true, variant: 'threaded', supported: true, nonDoc: 4 }), true);
  for (const bad of [null, { live: false, variant: 'threaded', supported: true, nonDoc: 4 }, { live: true, variant: 'faithful', supported: true, nonDoc: 4 }, { live: true, variant: 'threaded', supported: false, nonDoc: 4 }, { live: true, variant: 'threaded', supported: true, nonDoc: 0 }]) assert.equal(liveP(bad), false);
  assert.equal(liveA({ live: false, variant: 'faithful' }), true);
  assert.equal(liveA({ live: true, variant: 'threaded' }), false);
});

function fakeExitLane(dir, { pEdit, pLive, a2Edit, still = false, clear = false }) {
  mkdirSync(join(dir, 'shots'), { recursive: true });
  const base = () => ({ w: 100, h: 100, rgba: new Uint8Array(100 * 100 * 4).fill(255) });
  const put = (name, edit) => { const i = base(); if (edit) edit(i); for (let r = 0; r < 2; r++) writeFileSync(join(dir, 'shots', `${name}_${r}.png`), encodePng(i)); };
  put('A_0'); put('A2_0', a2Edit); put('P_0', pEdit);
  const boxes = { hero_copy: [10e6, 10e6, 20e6, 20e6], 'hero.deck_article#1': [50e6, 50e6, 20e6, 20e6] };
  const row = (arm, live) => ({ i: 0, y: 0, scrollY: 0, boxes, alpha: clear ? { hero_copy: 0, 'hero.deck_article#1': 1 } : undefined, live, files: [`shots/${arm}_0_0.png`, `shots/${arm}_0_1.png`], dprMilli: 1000, layers: [], layerCount: 0 });
  const faithful = { live: false, variant: 'faithful', supported: true, nonDoc: 0 };
  const moved = { i: 1, y: 50, scrollY: 50, boxes: { ...boxes, hero_copy: [10e6, still ? 10e6 : 5e6, 20e6, 20e6] }, live: faithful, files: [], dprMilli: 1000, layers: [], layerCount: 0 };
  writeFileSync(join(dir, 'manifest.json'), JSON.stringify({
    schema: 'fw.path-pix/1', mode: 'exit', flag: 'hero.exit:threaded', engine: 'webkit', lane: 'test', run: 'test', lossless: true, compositing: 'test', dpr: 1, vw: 100, vh: 100,
    frame: { w: 100, h: 100 }, exit: { T: 0, h: 200, v: 100, n: 100 }, offsets: [0, 1], cut: [],
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
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
