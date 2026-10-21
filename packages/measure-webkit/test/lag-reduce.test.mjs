// The lag reductions agree with the Lean golden (Fw.Measure.WebKitLag, golden/measure/webkit-lag.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { owner, regionOf, zoneOf, regionLedger, stepArea, stepCount, topPart, rollup, rankRegion, rankWindows, verdict, topK, filterTotals, excess, RARE_MIN, COUNT_COLUMNS, rareBase, flagged, ratioVerdict } from '../src/lag/reduce.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/webkit-lag.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every golden kind has lines', () => {
  for (const k of ['owner', 'region', 'ledger', 'rank', 'rankWindows', 'rankScaled', 'verdict', 'rareConst', 'rareCell', 'topK', 'filter']) assert.ok(of(k).length > 0, k);
});

test('owner: the smallest covering box', () => {
  for (const g of of('owner')) assert.equal(owner(g.boxes, g.clip), g.owner, JSON.stringify(g.clip));
});

test('region of a scroll position', () => {
  for (const g of of('region')) {
    assert.equal(regionOf(g.vh, g.maxY, g.y), g.region, `${g.vh} ${g.maxY} ${g.y}`);
    assert.equal(zoneOf(g.vh, g.y), g.zone, `zone ${g.vh} ${g.y}`);
  }
});

test('ledgers per region, counts and roll-up', () => {
  for (const g of of('ledger')) {
    for (const r of g.regions) {
      assert.deepEqual(regionLedger(g.vh, g.maxY, g.steps, r.region, stepArea), r.area, r.region);
      assert.deepEqual(regionLedger(g.vh, g.maxY, g.steps, r.region, stepCount), r.count, r.region);
      assert.deepEqual(rollup(r.area), r.areaRollup, r.region);
    }
    assert.deepEqual(g.steps.map(topPart), g.steps.map((x) => x.topPart));
  }
});

test('counter ranking by ratio to the calm baseline', () => {
  for (const g of of('rank')) {
    assert.deepEqual(rankRegion(g.vh, g.maxY, g.ys, g.rows, g.names, g.region), { ranked: g.ranked, unranked: g.unranked }, g.region);
  }
});

test('counter ranking of two windows, with frames per row', () => {
  for (const g of of('rankWindows')) {
    assert.deepEqual(rankWindows(g.fR, g.fC, g.window, g.baseline, g.names), { ranked: g.ranked, unranked: g.unranked });
  }
});

test('counting one column in other units leaves the ranking unchanged', () => {
  for (const g of of('rankScaled')) {
    const un = (rows) => rows.map((r) => r.map((v, i) => (i === g.col ? v / g.k : v)));
    const base = rankWindows(g.fR, g.fC, un(g.window), un(g.baseline), g.names);
    assert.deepEqual(rankWindows(g.fR, g.fC, g.window, g.baseline, g.names).ranked, g.ranked);
    assert.deepEqual(base.ranked, g.ranked);
  }
});

test('raw excess does flip with the unit (why the probe ranks by ratio)', () => {
  assert.ok(excess(1, 1, 30, 10) > excess(1, 1, 20, 10));
  assert.ok(excess(1, 1, 30, 10) < excess(1, 1, 200, 100));
});

test('arm verdict from per-pass ranges', () => {
  for (const g of of('verdict')) assert.equal(verdict(g.orig, g.faith), g.verdict, JSON.stringify([g.orig, g.faith]));
});

test('the rare-baseline constants are the Lean ones', () => {
  const [c] = of('rareConst');
  assert.equal(RARE_MIN, c.rareMin);
  assert.deepEqual([...COUNT_COLUMNS], c.countColumns);
});

test('rare baseline: the flag and the ratio verdict per cell, the same in every table', () => {
  for (const g of of('rareCell')) {
    const rareO = flagged(g.name, g.origSums), rareF = flagged(g.name, g.faithSums);
    assert.equal(rareO, g.rareO, `${g.ctx} ${g.name} original`);
    assert.equal(rareF, g.rareF, `${g.ctx} ${g.name} faithful`);
    assert.equal(ratioVerdict(rareO, rareF, g.orig, g.faith), g.verdict, `${g.ctx} ${g.name}`);
    assert.equal(g.verdict === 'rareBaseline', rareO || rareF);
    assert.equal(rareBase(g.origSums) && COUNT_COLUMNS.includes(g.name), rareO);
  }
  const byCell = new Map();
  for (const g of of('rareCell')) {
    const key = JSON.stringify([g.name, g.origSums, g.faithSums]);
    byCell.set(key, [...(byCell.get(key) ?? []), [g.ctx, g.rareO, g.rareF]]);
  }
  assert.ok([...byCell.values()].some((v) => new Set(v.map((x) => x[0])).size > 1), 'a cell appears in two tables');
  for (const v of byCell.values()) assert.equal(new Set(v.map((x) => `${x[1]}${x[2]}`)).size, 1);
});

test('the golden has a faithful-only rare cell, the boundary, a duration and the 10-frame idle baseline', () => {
  const rows = of('rareCell');
  assert.ok(rows.some((g) => g.rareF && !g.rareO && g.verdict === 'rareBaseline'));
  assert.ok(rows.some((g) => g.origSums.every((x) => x === RARE_MIN) && !g.rareO));
  assert.ok(rows.some((g) => g.name.endsWith('Us') && !g.rareO && !g.rareF));
  assert.ok(rows.some((g) => g.ctx === 'idle'));
});

test('top steps of a region', () => {
  for (const g of of('topK')) assert.deepEqual(topK(g.k, g.items), g.top, JSON.stringify(g.items));
});

test('filter layers: visible count, area, area times radius', () => {
  for (const g of of('filter')) assert.deepEqual(filterTotals(g.viewport, g.items), { count: g.count, area: g.area, areaRadius: g.areaRadius });
});
