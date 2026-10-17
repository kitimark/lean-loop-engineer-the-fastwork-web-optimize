import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseTop, lagBuckets, lagSummary } from '../src/hostmon.mjs';
import { rotate } from '../src/quiet.mjs';

const TOP = `Processes: 755 total, 4 running
Load Avg: 913.68, 19.29, 13.42
CPU usage: 16.79% user, 8.34% sys, 74.85% idle
Disks: 1/2G read

PID    COMMAND          %CPU
649    WindowServer     49.1
2094   iTerm2           13.9
Processes: 755 total, 4 running
Load Avg: 1.5, 19.29, 13.42
CPU usage: 0.0% user, 100.0% sys, 0.0% idle

PID    COMMAND          %CPU
5898   com.apple.Safari 58.3
`;

test('parseTop reads load, cpu split and the top processes of every block', () => {
  const s = parseTop(TOP);
  assert.equal(s.length, 2);
  assert.deepEqual([s[0].load1, s[0].user, s[0].sys, s[0].idle], [913.68, 16.79, 8.34, 74.85]);
  assert.deepEqual(s[0].top, [{ cmd: 'WindowServer', cpu: 49.1 }, { cmd: 'iTerm2', cpu: 13.9 }]);
  assert.equal(s[1].idle, 0);
  assert.equal(s[1].top[0].cmd, 'com.apple.Safari');
  assert.deepEqual(parseTop('garbage'), []);
});

test('lagBuckets keeps the max per bucket and ignores samples outside the window', () => {
  const b = lagBuckets([{ t: 1000, lag: 3 }, { t: 1100, lag: 9 }, { t: 1300, lag: 2 }, { t: 5000, lag: 99 }, { t: 900, lag: 77 }], 1000, 1500, 250);
  assert.deepEqual(b, { bucketMs: 250, max: [9, 2] });
  assert.deepEqual(lagSummary([{ t: 1, lag: 4 }], 5, 6), { n: 0, mean: null, p95: null, max: null });
});

test('rotate shifts the arm order by the round', () => {
  assert.deepEqual(rotate([0, 1, 3], 0), [0, 1, 3]);
  assert.deepEqual(rotate([0, 1, 3], 1), [1, 3, 0]);
  assert.deepEqual(rotate([0, 1, 3], 3), [0, 1, 3]);
});
