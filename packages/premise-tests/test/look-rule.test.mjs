// The look report's decision rules in JS equal the Lean golden (lean/Fw/Parts/MorphGeomLookRule.lean, packages/contracts/golden/morph-geom.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { diffMap, elementTable, fadeOf, fadeShows, loadLookGolden, pixelOver, pxRange, regionStats, scrollEq, share, timedSettled, trackAt, tracksOk } from '../src/look-rule.mjs';

const golden = loadLookGolden();
const { cell } = golden;
const of = (fn) => golden.lines.filter((l) => l.fn === fn);
const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} vs ${b}`);

test('golden has every look fn', () => {
  for (const fn of ['lookPixel', 'lookRange', 'lookShare', 'lookTrack', 'lookCount', 'lookScroll', 'lookShows', 'lookFade', 'lookSettled']) assert.ok(of(fn).length > 0, fn);
});

test('pixelOver', () => { for (const l of of('lookPixel')) assert.equal(pixelOver(cell, l.in.a, l.in.b), l.out, JSON.stringify(l.in)); });
test('pxRange', () => { for (const l of of('lookRange')) assert.deepEqual(pxRange(l.in.size, l.in.x, l.in.w), l.out, JSON.stringify(l.in)); });
test('share', () => { for (const l of of('lookShare')) close(share(l.in.over, l.in.n), l.out); });
test('trackAt', () => { for (const l of of('lookTrack')) assert.equal(trackAt(cell, l.in.dur, l.in.t, l.in.m), l.out, JSON.stringify(l.in)); });
test('tracksOk', () => { for (const l of of('lookCount')) assert.equal(tracksOk(l.in.m, l.in.n), l.out, JSON.stringify(l.in)); });
test('scrollEq', () => { for (const l of of('lookScroll')) assert.equal(scrollEq(cell, l.in.a, l.in.b), l.out, JSON.stringify(l.in)); });
test('fadeShows', () => { for (const l of of('lookShows')) assert.equal(fadeShows(cell, golden, l.in.o, l.in.m), l.out, JSON.stringify(l.in)); });
test('timedSettled', () => { for (const l of of('lookSettled')) assert.equal(timedSettled(l.in.m, l.in.flip, l.in.goal, l.in.n), l.out, JSON.stringify(l.in)); });

test('the fade written on base is the golden fade, not a restated curve', () => {
  assert.equal(fadeOf(golden, 1).fade, 0);
  assert.equal(fadeOf(golden, 0).fade, 1);
  assert.equal(fadeOf(golden, 0.25).pointerNone, false);
  assert.equal(fadeOf(golden, 0.75).pointerNone, true);
  assert.throws(() => fadeOf(golden, 0.123));
});

test('the sources the golden constants stand for', () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const site = join(here, '..', '..', '..', 'apps', 'site', 'src', 'parts');
  const driver = readFileSync(join(site, 'morph.geom', 'driver.ts'), 'utf8');
  assert.match(driver, new RegExp(`M_DURATION = ${cell.gridMs};`));
  const tween = readFileSync(join(site, 'morph.tween', 'logic.ts'), 'utf8');
  assert.match(tween, new RegExp(`DURATION_MS = ${cell.tweenMs};`));
  assert.match(tween, new RegExp(`FADE_END = ${cell.fadeEnd};`));
});

test('diffMap marks exactly the pixelOver pixels', () => {
  const img = (px) => ({ width: px.length, height: 1, data: Uint8ClampedArray.from(px.flatMap((p) => [...p, 255])) });
  const pairs = of('lookPixel').map((l) => [l.in.a, l.in.b]);
  const map = diffMap(img(pairs.map((p) => p[0])), img(pairs.map((p) => p[1])));
  pairs.forEach(([a, b], i) => assert.equal(map[i] > cell.over, pixelOver(cell, a, b)));
});

test('regionStats counts the pixels pxRange covers', () => {
  const map = new Uint8Array(6 * 4);
  map[0] = 13; map[7] = 40; map[23] = 12;
  assert.deepEqual(regionStats(cell, map, 6, 4, { x: 0.5, y: 0, width: 5, height: 2 }), { max: 40, share: 2 / 12, px: 12, over: 2 });
  assert.deepEqual(regionStats(cell, map, 6, 4, { x: 9, y: 9, width: 2, height: 2 }), { max: 0, share: 0, px: 0, over: 0 });
});

test('elementTable gives each differing pixel to the smallest box holding it', () => {
  const W = 6, H = 4;
  const map = new Uint8Array(W * H);
  for (const [x, y] of [[0, 0], [1, 0], [4, 3], [5, 1]]) map[y * W + x] = 99;
  const t = elementTable(cell, map, W, H, [
    { key: 'page', x: 0, y: 0, width: 6, height: 4 },
    { key: 'a', x: 0, y: 0, width: 2, height: 1 },
    { key: 'b', x: 3.5, y: 2.2, width: 2, height: 2 },
    { key: 'z', x: 9, y: 9, width: 1, height: 1 },
  ]);
  assert.equal(t.total, 4);
  assert.equal(t.unowned, 0);
  assert.deepEqual(t.rows.map((r) => [r.key, r.px, r.over, r.own]), [['a', 2, 2, 2], ['page', 24, 4, 1], ['b', 6, 1, 1]]);
});
