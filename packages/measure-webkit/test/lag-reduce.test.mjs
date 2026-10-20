// The lag reductions agree with the Lean golden (Fw.Measure.WebKitLag, golden/measure/webkit-lag.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { owner, regionOf, regionLedger, stepArea, stepCount, rollup, rankRegion, filterTotals } from '../src/lag/reduce.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/webkit-lag.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every golden kind has lines', () => {
  for (const k of ['owner', 'region', 'ledger', 'rank', 'filter']) assert.ok(of(k).length > 0, k);
});

test('owner: the smallest covering box', () => {
  for (const g of of('owner')) assert.equal(owner(g.boxes, g.clip), g.owner, JSON.stringify(g.clip));
});

test('region of a scroll position', () => {
  for (const g of of('region')) assert.equal(regionOf(g.vh, g.maxY, g.y), g.region, `${g.vh} ${g.maxY} ${g.y}`);
});

test('ledgers per region, counts and roll-up', () => {
  for (const g of of('ledger')) {
    for (const r of g.regions) {
      assert.deepEqual(regionLedger(g.vh, g.maxY, g.steps, r.region, stepArea), r.area, r.region);
      assert.deepEqual(regionLedger(g.vh, g.maxY, g.steps, r.region, stepCount), r.count, r.region);
      assert.deepEqual(rollup(r.area), r.areaRollup, r.region);
    }
  }
});

test('counter ranking by excess over the baseline', () => {
  for (const g of of('rank')) {
    assert.deepEqual(rankRegion(g.vh, g.maxY, g.ys, g.rows, g.names, g.region), g.ranked, g.region);
  }
});

test('filter layers: visible count, area, area times radius', () => {
  for (const g of of('filter')) assert.deepEqual(filterTotals(g.viewport, g.items), { count: g.count, area: g.area, areaRadius: g.areaRadius });
});
