import test from 'node:test';
import assert from 'node:assert/strict';
import { KEYS, leaks } from '../src/end-floor.mjs';

test('leaks reads the mut: keys the page records against the silenced set', () => {
  assert.equal(leaks(KEYS.write, [{ r: 1, keys: ['mut:platform#data-fw-scene'] }, { r: 0, keys: ['mut:nav#style'] }, { r: 0, keys: ['timer:t'] }]), 2);
  assert.equal(leaks(KEYS.plat, [{ r: 1, keys: ['mut:platform#data-fw-scene'] }]), 1);
  assert.equal(leaks(KEYS.style, [{ r: 1, keys: ['mut:platform#data-fw-scene'] }]), 0);
});

test('the platform scene attribute is in the platform and the all-writers silenced sets', () => {
  assert.ok(KEYS.plat.includes('platform#data-fw-scene'));
  assert.ok(KEYS.write.includes('platform#data-fw-scene'));
});
