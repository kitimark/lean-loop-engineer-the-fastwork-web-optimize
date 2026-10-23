import test from 'node:test';
import assert from 'node:assert/strict';
import { FLAG_ARMS, statesOf, zoneArms, NAV_M } from './plan.mjs';
import { CI_PAIRS } from './ci-pairs.mjs';
import { ringSplit, glassOf, glassDelta, againstLoads, maskOf, hashOf } from './pix.mjs';
import { unionBox } from './reduce.mjs';
import { flat } from './mac-capture.mjs';
import { encodePng } from '../../../packages/measure-webkit/src/pathpix-png.mjs';

const img = (w, h, f) => {
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const [r, g, b] = f(x, y); const o = (y * w + x) * 4; rgba[o] = r; rgba[o + 1] = g; rgba[o + 2] = b; rgba[o + 3] = 255; }
  return { w, h, rgba };
};

test('every flag arm has a zone, a task and a CI pairing', () => {
  const ids = FLAG_ARMS.map((a) => a.id);
  assert.equal(new Set(ids).size, ids.length);
  for (const a of FLAG_ARMS) { assert.ok(a.zone && a.task && a.search.startsWith('?fw=')); assert.ok(CI_PAIRS[a.id]?.gate, a.id); }
});

test('a zone loads faithful, the A/A control, its flag arms, then faithful again as an order probe', () => {
  assert.deepEqual(zoneArms('morph').map((a) => a.id), ['base', 'base2', 'morph-panel-threaded', 'morph-panel-threaded-fade', 'base3']);
  assert.deepEqual(zoneArms('pain').map((a) => a.id), ['base', 'base2', 'pain-dark-scroll', 'base3']);
  assert.ok(zoneArms('nav').every((a) => a.id.startsWith('base') || a.zone === 'nav'));
});

test('the nav states hold the task values and the pain states need the flip offset', () => {
  assert.deepEqual(statesOf('nav').map((s) => s.m), NAV_M);
  for (const m of [0.1, 0.5, 0.9, 0.25, 0.75]) assert.ok(statesOf('nav').some((s) => s.m === m));
  assert.throws(() => statesOf('pain'));
  assert.deepEqual(statesOf('pain', 888).map((s) => s.y), [872, 887, 888, 889, 904]);
  assert.throws(() => statesOf('hero'));
});

test('ringSplit separates the mask edge from its interior and ignores the frame border', () => {
  const w = 10, h = 10, del = new Uint8Array(w * h);
  del[2 * w + 2] = 5; // on the mask corner
  del[5 * w + 5] = 9; // deep inside
  del[0] = 7; // outside the mask
  const r = ringSplit(del, w, [2, 8, 2, 8], 2);
  assert.deepEqual(r.edge, { changed: 1, maxDelta: 5 });
  assert.deepEqual(r.interior, { changed: 1, maxDelta: 9 });
  const full = ringSplit(del, w, [0, 10, 0, 10], 2);
  assert.equal(full.edge.changed, 0);
  assert.equal(full.interior.changed, 3);
});

test('glassOf reads mean and median over the shrunk mask and glassDelta subtracts', () => {
  const a = img(40, 40, () => [100, 150, 200]);
  const b = img(40, 40, () => [98, 150, 203]);
  const ga = glassOf(a, [0, 40, 0, 40], 4), gb = glassOf(b, [0, 40, 0, 40], 4);
  assert.deepEqual(ga.mean, [100, 150, 200]);
  assert.deepEqual(ga.median, [100, 150, 200]);
  assert.deepEqual(glassDelta(ga, gb), { mean: [-2, 0, 3], median: [-2, 0, 3] });
  assert.equal(glassOf(a, [0, 10, 0, 10], 8), null);
});

test('againstLoads: an arm equal to one faithful load is within the faithful spread', () => {
  const w = 8, h = 8;
  const f0 = img(w, h, () => [10, 10, 10]);
  const f1 = img(w, h, (x) => (x < 4 ? [10, 10, 10] : [60, 10, 10]));
  const arm = img(w, h, (x) => (x < 4 ? [10, 10, 10] : [60, 10, 10]));
  const r = againstLoads([f0, f1], arm, w, [0, w, 0, h]);
  assert.equal(r.nearest, 0);
  assert.equal(r.spread, 32);
  assert.equal(r.within, true);
  const far = img(w, h, () => [200, 10, 10]);
  const q = againstLoads([f0, f1], far, w, [0, w, 0, h]);
  assert.equal(q.nearest, 64);
  assert.equal(q.within, false);
  const f2 = img(w, h, () => [10, 10, 10]);
  assert.equal(againstLoads([f0, f2], far, w, [0, w, 0, h]).within, false);
});

test('maskOf takes the nav box in micro px and the whole frame otherwise; unionBox grows both', () => {
  assert.deepEqual(maskOf('frame', 3, 1290, 2325), [0, 1290, 0, 2325]);
  assert.deepEqual(maskOf('nav', 3, 1290, 2325, [12000000, 12000000, 406000000, 100000000]), [35, 1255, 35, 337]);
  assert.throws(() => maskOf('nav', 3, 10, 10));
  assert.deepEqual(unionBox([0, 0, 10, 10], [5, 5, 10, 10]), [0, 0, 15, 15]);
});

test('hashOf is stable and sees one changed pixel', () => {
  const a = img(4, 4, () => [1, 2, 3]);
  const b = img(4, 4, (x, y) => (x === 3 && y === 3 ? [1, 2, 4] : [1, 2, 3]));
  assert.equal(hashOf(a), hashOf(img(4, 4, () => [1, 2, 3])));
  assert.notEqual(hashOf(a), hashOf(b));
});

test('flat refuses the all-black frame a locked screen gives and accepts a real one', () => {
  assert.equal(flat(encodePng(img(8, 8, () => [0, 0, 0]))), true);
  assert.equal(flat(encodePng(img(8, 8, (x) => [x * 10, 0, 0]))), false);
});
