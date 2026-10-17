import { test } from 'node:test';
import assert from 'node:assert/strict';
import { T, timeoutScale, attempts } from '../src/timeouts.mjs';

test('defaults are the local values', () => {
  assert.equal(timeoutScale({}), 1);
  assert.equal(T(15000, {}), 15000);
  assert.equal(attempts({}), 2);
});
test('env scales every wait and sets the attempts', () => {
  assert.equal(T(15000, { FW_WK_TIMEOUT_SCALE: '4' }), 60000);
  assert.equal(attempts({ FW_WK_ATTEMPTS: '3' }), 3);
});
test('bad values fall back to the defaults', () => {
  for (const v of ['0', '-2', 'x', '']) assert.equal(timeoutScale({ FW_WK_TIMEOUT_SCALE: v }), 1);
  assert.equal(attempts({ FW_WK_ATTEMPTS: '0' }), 2);
  assert.equal(attempts({ FW_WK_ATTEMPTS: '1.5' }), 2);
});
