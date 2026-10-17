// compare() on synthetic images (no browser), cellOf() glue, and the default probe list against the gate's Lean matrix.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { compare, decode, encodePng, sameImage } from '../src/diff.mjs';
import { cellOf, loadTolerances, tolFor } from '../src/run.mjs';
import { DEFAULT_TOL } from '../src/verdict.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const solid = (w, h, rgba) => {
  const data = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) data.set(rgba, 4 * i);
  return { width: w, height: h, data };
};
const paint = (img, x, y, rgba) => img.data.set(rgba, 4 * (y * img.width + x));
const WHITE = [255, 255, 255, 255];

test('identical images: all counts zero', () => {
  const c = compare(solid(10, 10, WHITE), solid(10, 10, WHITE));
  assert.deepEqual(c.stats, { total: 100, changed: 0, aa: 0, maxDelta: 0, aaMaxDelta: 0 });
});

test('a block of black pixels is counted as changed with its delta', () => {
  const a = solid(20, 20, WHITE);
  const b = solid(20, 20, WHITE);
  for (let y = 5; y < 10; y++) for (let x = 5; x < 10; x++) paint(b, x, y, [0, 0, 0, 255]);
  const c = compare(a, b);
  assert.equal(c.stats.total, 400);
  assert.equal(c.stats.changed + c.stats.aa, 25);
  assert.ok(c.stats.changed >= 9);
  assert.equal(c.stats.maxDelta, 255);
});

test('a size mismatch counts the outside strip as changed with delta 255', () => {
  const c = compare(solid(10, 10, WHITE), solid(10, 12, WHITE));
  assert.equal(c.stats.total, 120);
  assert.equal(c.stats.changed, 20);
  assert.equal(c.stats.maxDelta, 255);
});

test('an absent arm is a full change', () => {
  const c = compare(solid(4, 5, WHITE), null);
  assert.deepEqual(c.stats, { total: 20, changed: 20, aa: 0, maxDelta: 255, aaMaxDelta: 0 });
});

test('png round trip and sameImage', () => {
  const a = solid(6, 3, [10, 20, 30, 255]);
  const back = decode(encodePng(a));
  assert.ok(sameImage(a, back));
  paint(back, 0, 0, [11, 20, 30, 255]);
  assert.ok(!sameImage(a, back));
});

test('cellOf: pass, fail, unsettled, invalid, nc, error', () => {
  const tol = tolFor(loadTolerances(), 'any');
  assert.deepEqual(tol, DEFAULT_TOL);
  const shot = (img, o = {}) => ({ img, stable: true, gate: true, fontsLoaded: true, imagesLoaded: true, ...o });
  const w = solid(50, 50, WHITE);
  const k = solid(50, 50, WHITE);
  for (let y = 0; y < 25; y++) for (let x = 0; x < 50; x++) paint(k, x, y, [0, 0, 0, 255]);
  assert.equal(cellOf('p', tol, shot(w), shot(solid(50, 50, WHITE))).verdict, 'pass');
  assert.equal(cellOf('p', tol, shot(w), shot(k)).verdict, 'fail');
  assert.equal(cellOf('p', tol, shot(w), shot(k, { stable: false })).verdict, 'unsettled');
  assert.equal(cellOf('p', tol, shot(w), shot(w, { gate: false })).verdict, 'unsettled');
  // unloaded assets: invalid, never fail, even when the pictures differ completely
  assert.equal(cellOf('p', tol, shot(w), shot(k, { fontsLoaded: false })).verdict, 'invalid');
  assert.equal(cellOf('p', tol, shot(w, { imagesLoaded: false }), shot(k)).verdict, 'invalid');
  assert.equal(cellOf('p', tol, shot(w), shot(k, { fontsLoaded: false, stable: false })).verdict, 'invalid');
  assert.equal(cellOf('p', tol, { absent: 'zero box' }, { absent: 'no element' }).verdict, 'nc');
  assert.equal(cellOf('p', tol, shot(w), { absent: 'no element' }).verdict, 'fail');
  assert.equal(cellOf('p', tol, { error: 'x' }, shot(w)).status, 'error');
  assert.equal(cellOf('p', tol, shot(w), shot(solid(50, 50, WHITE))).images, null);
});

test('default probes exist in the Lean matrix and tolerances are well formed', () => {
  const probes = JSON.parse(readFileSync(join(HERE, '..', 'probes.default.json'), 'utf8')).probes;
  const gen = JSON.parse(readFileSync(resolve(HERE, '../../../apps/site/src/breakpoints.gen.json'), 'utf8'));
  const ids = new Set(gen.matrix.probes.map((p) => p.id));
  for (const p of probes) assert.ok(ids.has(p), p);
  const t = loadTolerances();
  for (const v of [t.default, ...Object.values(t.parts)]) {
    for (const [k, x] of Object.entries(v)) assert.ok(k === 'countAA' ? typeof x === 'boolean' : Number.isInteger(x) && x >= 0, k);
  }
});
