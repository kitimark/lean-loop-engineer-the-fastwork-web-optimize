import { test } from 'node:test';
import assert from 'node:assert/strict';
import { withRetry, classify } from '../src/simretry.mjs';

// the rule itself is checked against the Lean goldens in fwcore.test.mjs; here the loop around a simctl call
const textOf = (r) => (r.error ? r.error.code : r.stderr);
const run = (results, opts = {}) => {
  let i = 0; const waits = [];
  const r = withRetry(() => results[Math.min(i++, results.length - 1)], { max: 3, text: textOf, sleepSync: (ms) => waits.push(ms), ...opts });
  return { r, calls: i, waits };
};
const timeout = { status: null, error: { code: 'ETIMEDOUT' }, stderr: '' };
const ok = { status: 0, stderr: '' };
const bad = { status: 1, stderr: 'Invalid device: x' };

test('a timeout is asked again after 2 s, then the call works', () => {
  const x = run([timeout, ok]);
  assert.equal(x.r, ok); assert.equal(x.calls, 2); assert.deepEqual(x.waits, [2000]);
});
test('timeouts stop at the limit: 3 calls, waits 2 s and 4 s, the last failure is returned', () => {
  const x = run([timeout]);
  assert.equal(x.r, timeout); assert.equal(x.calls, 3); assert.deepEqual(x.waits, [2000, 4000]);
});
test('a permanent failure is returned at once, no wait', () => {
  const x = run([bad, ok]);
  assert.equal(x.r, bad); assert.equal(x.calls, 1); assert.deepEqual(x.waits, []);
});
test('onRetry is told before every wait', () => {
  const seen = []; run([timeout, timeout, ok], { onRetry: (e) => seen.push(e) });
  assert.deepEqual(seen.map((e) => [e.attempt, e.delayMs, e.text]), [[1, 2000, 'ETIMEDOUT'], [2, 4000, 'ETIMEDOUT']]);
});
test('classify: the ETIMEDOUT error code of a killed spawnSync is transient', () => {
  assert.equal(classify('ETIMEDOUT'), 'transient');
  assert.equal(classify('Invalid device: x'), 'permanent');
});
