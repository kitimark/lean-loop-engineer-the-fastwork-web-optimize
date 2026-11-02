import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { REST_TOL10, REST_MARGIN, restOf, gapOf, goalOf, targetOf, touchEnd10, arrival, settle10, restCmp, cmpVerdict, jobVerdict, acrossRest, restDecisive, restRow, restTallyOf, restReport } from '../src/touchlock-rest.mjs';
import { acrossReport, acrossMarkdown } from '../src/touchlock.mjs';
import { restartServer, beginServer, endServer } from '../src/touchlock-run.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(join(HERE, '../../contracts/golden/measure/touch-lock.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);
const win = (g) => ({ max10: g.max, final10: g.final, peak10: g.peak, target10: g.target });

test('the rest constants and cases replay the Lean golden', () => {
  assert.deepEqual([REST_TOL10, REST_MARGIN], [ops('constants')[0].restTol10, ops('constants')[0].restMargin]);
  assert.ok(ops('rest').length >= 10);
  for (const g of ops('rest')) {
    assert.equal(restOf(win(g)), g.out, g.case);
    assert.equal(gapOf(win(g)), g.gap, g.case);
    assert.equal(goalOf(win(g)), g.goal, g.case);
  }
  for (const g of ops('target')) assert.equal(targetOf(g.seen), g.out, g.case);
  for (const g of ops('touchEnd')) assert.equal(touchEnd10(g.ev0, g.firstScroll, g.swipe), g.out, g.case);
  for (const g of ops('settle')) {
    assert.equal(arrival(g.final, g.frames), g.arrival, g.case);
    assert.equal(settle10(g.touchEnd, g.final, g.frames), g.out, g.case);
  }
});

test('restCmp and the across rest verdict replay the Lean golden, and a live write never ranks the pin better', () => {
  assert.ok(ops('restCmp').length >= 8 && ops('restAcross').length >= 8);
  for (const g of ops('restCmp')) {
    const c = restCmp({ rested: g.base[0], reached: g.base[1] }, { rested: g.pin[0], reached: g.pin[1] });
    assert.equal(c, g.out, g.case);
    assert.equal(cmpVerdict(c), g.verdict, g.case);
  }
  for (const g of ops('restAcross')) {
    assert.equal(acrossRest(g.jobs), g.out, g.case);
    assert.equal(restDecisive(g.jobs), g.decisive, g.case);
  }
  assert.equal(jobVerdict(['pinBetter', 1]), 'insufficient');
  assert.equal(jobVerdict(['pinBetter', 0]), 'second');
  assert.equal(jobVerdict(['pinWorse', 3]), 'first');
});

const row = (arm, over = {}) => ({ arm, rep: 0, maxY10: 52270, finalY10: 52270, frames: [[50000, true, 100], [52270, true, 120]], events: [[0, 0, 100]], q2: { firstScrollMs: 0 }, obs: { swipeAt: 0 }, ...over });
const rows = (arm, n, rested) => Array.from({ length: n }, (_, i) => row(arm, i < rested ? {} : { finalY10: 40000 }));

test('a window row is classed by its final position and the report keeps the live-write guard', () => {
  const all = [...rows('base', 4, 1), ...rows('lock', 4, 4), ...rows('pin', 4, 4)];
  assert.deepEqual(restTallyOf(all, 'base'), { rested: 1, reached: 4 });
  assert.equal(restRow(row('pin')).cls, 'atEnd');
  const r = restReport([{ label: 'a', rows: all, liveWrites: 0 }, { label: 'b', rows: all, liveWrites: 2 }, { label: 'c', rows: all, liveWrites: 0 }]);
  assert.deepEqual(r.jobs.map((j) => j.verdict), ['second', 'insufficient', 'second']);
  assert.equal(r.decisive, 2);
  assert.match(acrossMarkdown(acrossReport([{ label: 'a', rows: all }])), /by rest position, Lean acrossRest/);
});

test('every touch-lock server start goes through beginServer, whose launches fit the ready allowance', async () => {
  const src = readFileSync(join(HERE, '../src/touchlock-run.mjs'), 'utf8');
  assert.equal((src.match(/await startServer\(/g) ?? []).length, 0);
  assert.equal((src.match(/readyMs/g) ?? []).length, 0);
  const seen = [];
  const start = async (_d, o) => { seen.push(o.tag); return { launches: [{ n: 1, fault: null }] }; };
  const touch = { driver: 'd', restarts: 0, server: null, on: true, why: null, launches: [] };
  await restartServer(touch, { udid: 'u', log: () => {}, push: {}, start });
  assert.deepEqual(seen, ['serve-r1']);
  assert.deepEqual(touch.launches, [{ tag: 'serve-r1', launches: [{ n: 1, fault: null }] }]);
});

test('a failed start keeps its named launches and fault in the snapshot; a late stop is noted', async () => {
  const touch = { driver: 'd', restarts: 0, server: null, on: true, why: null, launches: [] };
  const launches = [{ n: 1, fault: 'driver-launch-stuck' }, { n: 2, fault: 'driver-ended' }];
  await beginServer(touch, { udid: 'u', log: () => {}, push: {}, start: async () => { throw Object.assign(new Error('push server: no ready file after 480 s'), { launches, fault: 'driver-ended' }); } });
  assert.equal(touch.on, false);
  assert.deepEqual(touch.launches, [{ tag: 'serve', launches, fault: 'driver-ended' }]);
  touch.server = { stopFault: 'driver-stop-late' };
  await endServer(touch, async () => {});
  assert.equal(touch.server, null);
  assert.deepEqual(touch.launches[1], { tag: 'stop', launches: [], fault: 'driver-stop-late' });
});
