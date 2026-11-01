// No browser: the PNG tools, the difference and heat map, the crop, and the page of the sweep strips.
import test from 'node:test';
import assert from 'node:assert/strict';
import { combine, decodePng, diffImages, encodePng, heat, stack, strip, zoom } from '../src/png.mjs';
import { MOMENTS, WIDTHS, WORDS, cropOf, pageHtml, stripPath, wordPx } from '../src/sweep-strips.mjs';

const img = (w, h, f) => { const data = new Uint8Array(w * h * 4); for (let p = 0; p < w * h; p++) data.set(f(p % w, Math.floor(p / w)), p * 4); return { width: w, height: h, data }; };

test('encode then decode gives the same pixels', () => {
  const a = img(5, 3, (x, y) => [x * 40, y * 80, (x + y) * 10, 255]);
  const b = decodePng(encodePng(a));
  assert.equal(b.width, 5); assert.equal(b.height, 3);
  assert.deepEqual([...b.data], [...a.data]);
});

test('the diff is the largest channel difference, with count, over-2 count, place and columns', () => {
  const a = img(4, 2, () => [10, 10, 10, 255]);
  const b = img(4, 2, (x, y) => (x === 2 && y === 1 ? [10, 50, 12, 255] : x === 0 && y === 0 ? [11, 10, 10, 255] : [10, 10, 10, 255]));
  const d = diffImages(a, b);
  assert.equal(d.max, 40); assert.equal(d.count, 2); assert.equal(d.over2, 1);
  assert.deepEqual(d.at, { x: 2, y: 1 }); assert.deepEqual(d.columns, [0, 2]);
  assert.throws(() => diffImages(a, img(3, 2, () => [0, 0, 0, 255])));
});

test('heat colours follow the ladder 0, 1-2, 3-8, 9-32, over 32', () => {
  const c = [0, 1, 2, 3, 8, 9, 32, 33, 255].map((v) => heat(v).join());
  assert.equal(new Set(c).size, 5);
  assert.equal(c[1], c[2]); assert.equal(c[3], c[4]); assert.equal(c[5], c[6]); assert.equal(c[7], c[8]);
});

test('zoom repeats each pixel k x k; stack and combine pad with grey bars', () => {
  const a = img(2, 1, (x) => [x * 100, 0, 0, 255]);
  const z = zoom(a, 4);
  assert.equal(z.width, 8); assert.equal(z.height, 4); assert.equal(z.data[(3 * 8 + 7) * 4], 100);
  const s = strip(a, a, 4);
  assert.equal(s.diff.max, 0); assert.equal(s.image.height, 4 * 3 + 16);
  const c = combine([s.image, strip(img(3, 1, () => [0, 0, 0, 255]), img(3, 1, () => [0, 0, 0, 255]), 4).image]);
  assert.equal(c.width, 12); assert.equal(c.height, s.image.height * 2 + 16);
  assert.equal(stack([a, a], 2, [1, 2, 3]).height, 4);
});

test('the crop is whole pixels with a margin, inside the viewport', () => {
  assert.deepEqual(cropOf({ left: 24.4, top: 30.2, right: 100.6, bottom: 60.1 }, 390, 1000), { x: 20, y: 26, width: 85, height: 39 });
  assert.deepEqual(cropOf({ left: 1, top: 1, right: 395, bottom: 20 }, 390, 1000), { x: 0, y: 0, width: 390, height: 24 });
});

test('moments, widths and file names', () => {
  assert.deepEqual(MOMENTS.map((m) => m.word), ['p0', 'f1', 'f2', 't500', 't2000']);
  assert.ok(MOMENTS.every((m) => m.us < 4_000_000));
  assert.deepEqual(WIDTHS, [390, 1440]);
  assert.equal(stripPath('webkit', 390, 'p0'), 'strips/playwright-webkit-390-sweep-p0.png');
  assert.equal(stripPath('chromium', 1440, 't500'), 'strips/chromium-1440-sweep-t500.png');
  assert.equal(wordPx(390), 28); assert.equal(wordPx(1000), 28); assert.equal(wordPx(1440), 40);
});

test('the page has the four words and the flag arm adds the layer child', () => {
  const css = '.sweep.sweep{}';
  const f = pageHtml('faithful', 390, 'file:///f.woff2', css); const l = pageHtml('layer', 1440, 'file:///f.woff2', css);
  for (const w of WORDS) { assert.ok(f.includes(`>${w}</span>`)); assert.ok(l.includes(`>${w}<i class="layerBg"`)); }
  assert.ok(!f.includes('layerBg"')); assert.ok(l.includes('.restBlock { display: block; }')); assert.ok(!f.includes('.restBlock { display'));
  assert.equal((l.match(/data-word/g) ?? []).length, 4);
});
