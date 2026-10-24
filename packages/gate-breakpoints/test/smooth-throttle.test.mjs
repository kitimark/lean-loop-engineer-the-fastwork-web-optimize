import test from 'node:test';
import assert from 'node:assert/strict';
import { THROTTLES, parseThrottle } from '../src/smooth/throttle.mjs';
import { cellOf, summary } from '../src/smooth/cadence-table.mjs';
import { armRows, compareMarkdown } from '../src/smooth/throttle-table.mjs';

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

test('throttle table: lines the 1x and 6x tables up per window and arm, and keeps the Lean pair verdicts', () => {
  const file = (cpuThrottle, gap) => {
    const runs = ['orig', 'base', 'aa', 'cand'].flatMap((a) => [0, 1, 2, 3, 4].map((rep) => ({ width: 390, arm: a, window: 'hero', rep, ivs: [167, 167, gap, 167], ys: [], loaf: [] })));
    return { runs, cpuThrottle, search: '', hash: 'h', baseHash: 'h', version: 'v' };
  };
  const table = (t, gap) => { const cells = [1, 2, 3].map((i) => cellOf(String(i), file(t, gap), 390, 'hero')); return { cells, summary: summary(cells) }; };
  const a = table(1, 167);
  const b = table(6, 700);
  const rows = armRows(b);
  assert.deepEqual(rows.map((r) => r.arm), ['orig', 'base', 'aa', 'cand']);
  assert.equal(rows[0].jobs, 3);
  assert.equal(rows[0].hitches, 1);
  const md = compareMarkdown(a, b);
  assert.match(md, /\| 390 \| hero \| orig \| 3 \/ 3 \| 0\.0 \(0\.0-0\.0\) \| 25\.0 \(25\.0-25\.0\) \| 0 \| 1 \|/);
  assert.match(md, /orig vs base \| not told apart/);
});
