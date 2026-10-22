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
import { pathSearch as chromiumPathSearch, laneOffsets } from '../../measure-chromium/src/pathpix-pure.mjs';

test('the Chromium driver computes the same offsets and arm search as the Simulator lane', () => {
  for (const maxY of [0, 1, 7, 8, 4626, 5267, 123457]) assert.deepEqual(laneOffsets(maxY), offsets(maxY), `maxY ${maxY}`);
  for (const l of ['hero_copy', 'nav_bar', 'hero.countdown_face', 'morph.panel_panel']) assert.equal(chromiumPathSearch(l), pathSearch(l), l);
  assert.equal(pathSearch('hero_copy'), '?fwl=hero_copy:c');
});

test('page-side expressions are well-formed scripts', () => {
  for (const e of [BOX_EXPR, FREEZE_EXPR, HOLD_EXPR, VIDEO_EXPR, IMAGES_READY_EXPR, NEAR_IMAGES_EXPR]) assert.doesNotThrow(() => new Function(`return ${e}`));
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
