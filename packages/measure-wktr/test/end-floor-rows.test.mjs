import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { rowLine, rowsOfRun } from '../src/end-floor-rows.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const RUNS = ['end-floor-writes/r1', 'end-floor-writes/r2', 'end-floor-writes/r3', 'end-wktr-flip/r1'];

test('rows.txt of each run regenerates byte-equal from the committed JSON', () => {
  for (const run of RUNS) {
    const dir = join(root, 'results', run);
    assert.equal(rowsOfRun(dir).join('\n') + '\n', readFileSync(join(dir, 'rows.txt'), 'utf8'), run);
  }
});

test('rowLine counts frames, recalc 0 and 1, window range and mut: keys', () => {
  const row = { arm: 'a', rs: { kt: ['mut:x#y', 'timer:t'], wins: [3, 5], frames: [{ r: 1, k: [0, 1] }, { r: 2, k: [0] }, { r: 0, k: [1] }, { r: 1, k: [] }] } };
  assert.equal(
    rowLine('j', 'f.json', 7, row),
    'j f.json rows[7] a: frames 4, rate 100 per 100 frames, r=0 1, r=1 2, wins 3 to 5, frames without mut: key 2, frames per mut: key mut:x#y=2',
  );
  assert.equal(rowLine('j', 'f.json', 0, { arm: 'e', rs: { frames: [] } }).includes('frames 0, rate -'), true);
});
