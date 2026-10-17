import { test } from 'node:test';
import assert from 'node:assert/strict';
import { reasonNames } from '../src/determinism.mjs';

// merge gives every session the union of the reason names, so sessions that saw different reasons keep equal rows
test('reasonNames: sorted union over passes and states', () => {
  const p = (...rcs) => ({ census: rcs.map((reasonCounts) => ({ reasonCounts })) });
  assert.deepEqual(reasonNames([p({ b: 1 }, { a: 2 }), p({ '(gone)': 1 })]), ['(gone)', 'a', 'b']);
  assert.deepEqual(reasonNames([p({})]), []);
});
