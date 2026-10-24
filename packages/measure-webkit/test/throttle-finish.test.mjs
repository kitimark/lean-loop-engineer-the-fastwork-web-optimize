// The finish-zone twin against the Lean golden (Fw.Device.FinishRuns, packages/contracts/golden/device/finishruns.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as F from '../src/throttle/finish.mjs';
import { MIN_BASE, DROP_DEN } from '../src/throttle/stillruns.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/finishruns.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every golden kind has lines', () => {
  for (const k of ['consts', 'pass', 'turns', 'verdict', 'arm']) assert.ok(of(k).length > 0, k);
});

test('constants', () => {
  const [c] = of('consts');
  assert.deepEqual([F.ZONE_PX, F.END_PX, F.OPEN_WINDOW, MIN_BASE, DROP_DEN], [c.zonePx, c.endPx, c.openWindow, c.minBase, c.dropDen]);
});

test('zone rows and the counts of a pass', () => {
  for (const g of of('pass')) {
    assert.deepEqual(F.zoneRows(g.frames), g.rows, g.name);
    assert.deepEqual(F.reduce(g.frames), g.result, g.name);
  }
});

test('turns', () => {
  for (const g of of('turns')) assert.equal(F.turns(g.positions), g.turns, JSON.stringify(g.positions));
});

test('verdict', () => {
  for (const g of of('verdict')) assert.equal(F.verdict(g.base, g.lift), g.verdict, JSON.stringify(g));
});

test('arm sums', () => {
  for (const g of of('arm')) {
    assert.deepEqual(F.armOf(g.results), g.arm);
    assert.equal(F.reversalSum(g.results), g.reversals);
  }
});
