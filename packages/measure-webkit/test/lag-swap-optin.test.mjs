import test from 'node:test';
import assert from 'node:assert/strict';
import { parseCost, swapSetup } from '../src/lag/costmode.mjs';

const base = { site: '/s', search: 'fw=people.carousel:crop' };

test('a cost run without --swap captures no swap windows and builds no extra arms', () => {
  for (const mode of ['on', 'only']) {
    assert.deepEqual(swapSetup({ ...base, swap: false, cost: parseCost(mode).cost }), { swap: null, arms: null });
  }
});

test('--swap needs a cost run at a site with a query', () => {
  assert.deepEqual(swapSetup({ ...base, swap: true, cost: false }), { swap: null, arms: null });
  assert.deepEqual(swapSetup({ ...base, swap: true, cost: true, site: undefined }), { swap: null, arms: null });
  assert.deepEqual(swapSetup({ ...base, swap: true, cost: true, search: '' }), { swap: null, arms: null });
});

test('--swap with a cost run, a site and a query builds the crop and faithful arms', () => {
  const r = swapSetup({ ...base, swap: true, cost: true });
  assert.equal(r.swap.arms.crop.search, base.search);
  assert.equal(r.swap.arms.faithful.search, '');
  assert.equal(r.arms.faithful.dir, '/s');
  assert.equal(r.swap.home.id, 'crop');
});
