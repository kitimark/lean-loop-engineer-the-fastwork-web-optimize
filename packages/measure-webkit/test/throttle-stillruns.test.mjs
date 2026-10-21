// The still-run twin against the Lean golden (Fw.Device.StillRuns, packages/contracts/golden/device/stillruns.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as S from '../src/throttle/stillruns.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/stillruns.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every golden kind has lines', () => {
  for (const k of ['consts', 'runs', 'stairs', 'throttleK', 'verdict']) assert.ok(of(k).length > 0, k);
});

test('constants', () => {
  const [c] = of('consts');
  assert.deepEqual([S.BAND_LO, S.BAND_HI, S.MIN_BASE, S.DROP_DEN], [c.bandLo, c.bandHi, c.minBase, c.dropDen]);
});

test('runs and counts', () => {
  for (const g of of('runs')) {
    assert.deepEqual(S.runs(g.rows), g.runs);
    assert.equal(S.shortRuns(g.rows), g.short);
    assert.equal(S.bandRuns(g.rows), g.band);
    assert.equal(S.exitFrames(g.rows), g.exitFrames);
    assert.equal(S.allMove(g.rows), g.moving);
  }
});

test('stairs', () => {
  for (const g of of('stairs')) {
    assert.equal(S.moves(g.positions), g.moves);
    const rows = S.stairs(g.positions, g.period, g.value);
    assert.deepEqual(rows, g.rows);
    assert.deepEqual(S.runs(rows), g.runs);
    assert.equal(S.bandRuns(rows), g.band);
  }
});

test('throttle frames', () => {
  for (const g of of('throttleK')) assert.equal(S.throttleK(g.d), g.k, `${g.d}`);
});

test('verdict', () => {
  for (const g of of('verdict')) {
    assert.equal(S.sameHeight(g.heights), g.sameHeight);
    assert.equal(S.verdict(g.heights, g.base, g.lift), g.verdict, JSON.stringify(g));
  }
});

test('part series pairs a position with the next frame value', () => {
  assert.deepEqual(S.partSeries([1, 2, 3], [9, 10, 11]), [[1, 10], [2, 11]]);
  assert.deepEqual(S.armCounts([{ ys: [0, 0, 0, 0, 0, 0, 100, 100], vs: [0, 400, 400, 400, 400, 400, 400, 400] }]), { runs: 1, frames: 7 });
});
