import test from 'node:test';
import assert from 'node:assert/strict';
import { THROTTLES, parseThrottle } from '../src/smooth/throttle.mjs';
import { cellOf } from '../src/smooth/cadence-table.mjs';

test('throttle: empty is the control, 1 and 6 pass, everything else is refused', () => {
  assert.deepEqual(THROTTLES, [1, 6]);
  for (const [s, want] of [['', 1], [undefined, 1], ['1', 1], ['6', 6], [' 6 ', 6], ['4', null], ['0', null], ['06', 6], ['6x', null], ['-6', null], ['1e0', null]]) {
    assert.equal(parseThrottle(s), want, JSON.stringify(s));
  }
});

test('throttle: a cadence file without the field is a 1x file, one with it keeps it', () => {
  const run = (arm, rep) => ({ width: 390, arm, window: 'hero', rep, ivs: [167, 167, 170], ys: [], loaf: [] });
  const runs = ['orig', 'base', 'aa', 'cand'].flatMap((a) => [0, 1, 2, 3, 4].map((r) => run(a, r)));
  assert.equal(cellOf('1', { runs, search: '', hash: 'h', baseHash: 'h', version: 'v' }, 390, 'hero').cpuThrottle, 1);
  assert.equal(cellOf('2', { runs, cpuThrottle: 6, search: '', hash: 'h', baseHash: 'h', version: 'v' }, 390, 'hero').cpuThrottle, 6);
});
