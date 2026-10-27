import test from 'node:test';
import assert from 'node:assert/strict';
import { judgeRects, loadFlipCell } from '../src/flip-cell.mjs';

const r = (x, y, width, height) => ({ x, y, width, height });
const ok = { columns: [r(0, 0, 100, 400), r(112, 0, 100, 400)], images: [r(0, 0, 100, 200)], pill: r(10, 10, 300, 56), lang: r(100, 14, 80, 48), earn: r(200, 18, 80, 48), actions: r(180, 14, 120, 48), flip: true };
const band = { w: 1280, h: 800, cols: 2, gap: 12, btnH: 48 };

test('the golden defines the cell: bound, ms, elements and 12 bands', () => {
  const c = loadFlipCell();
  assert.equal(c.tolPx, 1);
  assert.deepEqual(c.ms, [0, 0.25, 0.5, 1]);
  assert.deepEqual(c.els, ['image', 'nav', 'lang', 'earn', 'actions']);
  assert.equal(c.bands.length, 12);
  for (const b of c.bands) assert.deepEqual([b.cols, b.gap, b.btnH], b.w <= 640 ? [3, 8, 36] : [5, 12, 48]);
});

test('equal rects and side-by-side columns pass', () => {
  assert.deepEqual(judgeRects(ok, ok, band, 1), []);
});

test('stacked columns (A1) fail on position and on order', () => {
  const stacked = { ...ok, columns: [r(0, 0, 212, 400), r(0, 0, 212, 400)] };
  assert.ok(judgeRects(ok, stacked, band, 1).some((b) => b.startsWith('column1: not beside')));
});

test('an earn button 8 px high (A3b) and a language button 6 px high (A3c) fail', () => {
  assert.ok(judgeRects(ok, { ...ok, earn: r(200, 10, 80, 48) }, band, 1).some((b) => b.startsWith('earn')));
  assert.ok(judgeRects(ok, { ...ok, lang: r(100, 8, 80, 48) }, band, 1).some((b) => b.startsWith('lang')));
});

test('a wrong column count fails', () => {
  assert.ok(judgeRects(ok, { ...ok, columns: [ok.columns[0]] }, band, 1).some((b) => b.startsWith('columns:')));
});
