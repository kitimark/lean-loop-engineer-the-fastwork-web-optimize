import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { COMPOSITIONS, EXTRA_SEARCHES, events, byDirection, stretches, lockCounts, passCounts, armRow, verdicts, medianGap, opens, springBack, totalCounts, rates, verdictOf, brickVerdict, stillWorseOf, perStretch, firstStretch } from '../src/throttle/morph-end.mjs';
import { cmp } from '../src/touchlock.mjs';
import { reportMd, reasonOf, brickRow } from '../src/throttle/morph-end-report.mjs';

test('the compositions: one search per arm, only the four-flag page is built on demand', () => {
  assert.deepEqual(Object.keys(COMPOSITIONS), ['rewrite', 'clamp', 'flip', 'release', 'all', 'all-unthrottle']);
  assert.equal(COMPOSITIONS.rewrite, '');
  assert.equal(COMPOSITIONS.all, '?preset=morph-end-all');
  assert.deepEqual(EXTRA_SEARCHES, ['?fw=morph.end.clamp:on,morph.end.flip:on,morph.end.release:on,engine.scroll:unthrottle']);
});

test('events: the first rise is no event, a fall after a rise is a close, a rise after a fall is a re-open', () => {
  const r = [0, 0, 300, 700, 1000, 1000, 600, 100, 0, 0, 400, 1000, 1000, 500, 800];
  const d = r.map((_, i) => (i < 6 ? -1 : i < 10 ? 1 : i < 13 ? -1 : i < 14 ? 1 : -1));
  assert.deepEqual(events(r, d), [
    { kind: 'close', frame: 6, dir: 'down' }, { kind: 'reopen', frame: 10, dir: 'up' },
    { kind: 'close', frame: 13, dir: 'down' }, { kind: 'reopen', frame: 14, dir: 'up' },
  ]);
  assert.deepEqual(byDirection(events(r, d)), { close: { up: 0, down: 2, none: 0 }, reopen: { up: 2, down: 0, none: 0 } });
});

test('events: a monotone rise, a flat series and an empty one have none; direction 0 is none', () => {
  assert.deepEqual(events([0, 100, 200, 1000], [0, 0, 0, 0]), []);
  assert.deepEqual(events([5, 5, 5], [1, 1, 1]), []);
  assert.deepEqual(events([], []), []);
  assert.deepEqual(events([0, 500, 400], [0, 0, 0]), [{ kind: 'close', frame: 2, dir: 'none' }]);
});

test('stretches of open frames', () => {
  assert.deepEqual(stretches([0, 1, 1, 0, 1, 0, 0, 1, 1, 1]), [[1, 2], [4, 4], [7, 9]]);
  assert.deepEqual(stretches([]), []);
});

function fightRec({ pinWrites = true } = {}) {
  const y = [], o = [], ca = [];
  for (let i = 0; i < 3; i++) { y.push(5200 + i); o.push(0); }
  const seq = [5300, 5300, 5260, 5230, 5300, 5260, 5230, 5300, 5300, 5300, 5300, 5300, 5300, 5300];
  seq.forEach((v, i) => {
    y.push(v); o.push(1);
    if (pinWrites && v === 5300 && i > 0 && seq[i - 1] !== 5300) ca.push([5300, 1, y.length - 1]);
  });
  y.push(5300); o.push(0);
  return { o, y, ca };
}

test('lockCounts: the pin against the rubber band is a fight; without a pin write the twin sees none', () => {
  const k = lockCounts(fightRec());
  assert.equal(k.stretches, 1);
  assert.equal(k.fights, 2);
  assert.ok(k.reversals >= 2);
  assert.ok(k.displaced > 0);
  const none = lockCounts(fightRec({ pinWrites: false }));
  assert.equal(none.fights, 0);
  assert.equal(none.displaced, 0);
});

test('lockCounts: a stretch under 10 frames is refused and counted by reason', () => {
  const k = lockCounts({ o: [0, 1, 1, 1, 0], y: [1, 5, 5, 5, 5], ca: [] });
  assert.deepEqual([k.stretches, k.refused], [0, { tooShort: 1 }]);
});

function record(extra = {}) {
  const n = 120;
  const MX = 52000;
  const y = [], o = [], r = [], d = [], t = [], mx = [];
  for (let i = 0; i < n; i++) {
    y.push(MX - 3000 + i * 20 + (i > 90 ? 100 : 0));
    o.push(i > 100 ? 1 : 0);
    r.push(i > 100 ? Math.min(1000, (i - 100) * 100) : 0);
    d.push(i > 90 ? -1 : 0);
    t.push(i * 35);
    mx.push(MX);
  }
  return { start: { ih: 7750, vh: 7750, y: MX - 3000, scale: 1 }, nav: true, frames: n, t, y, mx, o, r, d, ih: y.map(() => 7750), vh: y.map(() => 7750), ca: [], wobble: 1, moves: 40, total: n, ...extra };
}

test('a pass: counts from a record with the morph reads, the median gap of the cadence', () => {
  const c = passCounts(record());
  assert.equal(c.opens, 1);
  assert.deepEqual(c.closes, { up: 0, down: 0, none: 0 });
  assert.equal(c.gap, 35);
  assert.equal(c.maxR, 1000);
  assert.equal(medianGap([0, 10, 20, 50]), 10);
});

test('a record without the morph reads is not counted', () => {
  const rec = record();
  delete rec.r;
  assert.equal(reasonOf({ arm: 'clamp', rec, drag: { code: 0 } }), 'record has no morph reads');
  assert.equal(reasonOf({ arm: 'clamp', rec: record(), drag: { code: 0 } }), null);
});

test('the verdict of a composition runs through the Lean verdict twin on both counts', () => {
  const base = { band: 83, short: 300, frames: 4300 };
  assert.deepEqual(verdicts(base, { band: 2, short: 20, frames: 4100 }), { band: 'lifted', short: 'lifted' });
  assert.deepEqual(verdicts({ ...base, band: 0 }, { band: 0, short: 300, frames: 4100 }), { band: 'no-signature', short: 'not-lifted' });
});

test('the table has a row per job and arm and pools the jobs', () => {
  const passes = [{ arm: 'rewrite', rec: record(), drag: { code: 0 } }, { arm: 'clamp', rec: record(), drag: { code: 0 } }, { arm: 'clamp', rec: record(), drag: { code: 12 } }];
  const md = reportMd([{ vm: 'job 1', passes }]);
  assert.match(md, /\| job 1 \| clamp \| 2 \(1\) \|/);
  assert.match(md, /\| all jobs \| rewrite \| 1 \(1\) \|/);
  assert.match(md, /Excluded passes: touch driver failed/);
  assert.equal(armRow([]).usable, 0);
});

// The counting against the Lean golden (Fw.Measure.MorphEndCount, packages/contracts/golden/device/morph-end-count.jsonl).
const here = dirname(fileURLToPath(import.meta.url));
const gold = readFileSync(join(here, '../../contracts/golden/device/morph-end-count.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => gold.filter((l) => l.kind === kind);
const evJ = (evs) => evs.map((e) => ({ kind: e.kind, frame: e.frame, dir: e.dir }));
const dirsOf = (b) => ({ up: b.up, down: b.down, none: b.none });

test('golden: every kind has lines', () => {
  for (const k of ['events', 'stretches', 'fights', 'pass', 'total', 'verdict']) assert.ok(of(k).length > 0, k);
});

test('golden: events, their count by kind and finger direction, and the opens', () => {
  for (const g of of('events')) {
    const evs = events(g.r, g.d);
    assert.deepEqual(evJ(evs), g.events, g.name);
    const by = byDirection(evs);
    assert.deepEqual([dirsOf(by.close), dirsOf(by.reopen)], [g.closes, g.reopens], g.name);
    assert.equal(opens(g.r), g.opens, g.name);
    const seen = (b) => b.up + b.down + b.none;
    assert.equal(seen(by.close) + seen(by.reopen), evs.length, `${g.name}: each event once`);
  }
});

test('golden: stretches of open frames', () => {
  for (const g of of('stretches')) assert.deepEqual(stretches(g.o), g.stretches, JSON.stringify(g.o));
});

test('golden: spring-back fights are writes against the finger direction', () => {
  for (const g of of('fights')) assert.deepEqual(dirsOf(springBack(g.y, g.d, g.writes)), g.springBack, g.name);
});

test('golden: the counts of a pass and the pooled counts, whatever the pass order', () => {
  for (const g of of('pass')) {
    const evs = events(g.r, g.d);
    const by = byDirection(evs);
    assert.deepEqual({ opens: opens(g.r), closes: dirsOf(by.close), reopens: dirsOf(by.reopen), springBack: dirsOf(springBack(g.y, g.d, g.writes)) }, g.counts, g.name);
  }
  for (const g of of('total')) assert.deepEqual(totalCounts(g.passes), g.total);
});

test('golden: the verdict of a brick', () => {
  for (const g of of('verdict')) {
    assert.equal(cmp(rates(g.faithRev), rates(g.candRev)), g.rev, g.name);
    assert.equal(cmp(rates(g.faithFight), rates(g.candFight)), g.fight, g.name);
    assert.equal(stillWorseOf(g.stillJobs), g.stillWorse, g.name);
    assert.equal(verdictOf(g.faithRev, g.candRev, g.faithFight, g.candFight, g.stillJobs, g.stillLifted), g.verdict, g.name);
    assert.equal(brickVerdict(g.rev, g.fight, g.stillLifted, g.stillWorse), g.verdict, g.name);
  }
});

test('the verdict of a composition is made against the faithful passes of the jobs it ran in', () => {
  const mk = (arm, job, writes) => ({ arm, job, rec: { ...record(), ca: writes }, drag: { code: 0 } });
  const pin = [[5223, 1, 95]];
  const row = brickRow('clamp', [mk('rewrite', 'job 1', pin), mk('rewrite', 'job 2', pin), mk('clamp', 'job 1', pin)]);
  assert.deepEqual([row.n, row.jobs, row.baseN], [1, 1, 1]);
  assert.equal(brickRow('release', [mk('rewrite', 'job 1', [])]).verdict, 'no-data');
  assert.deepEqual([row.rev, row.fight, row.firstRev, row.firstFight], Array(4).fill('undecided'), 'one pass per side is below TouchLock.minSamples');
  const none = brickRow('release', [mk('rewrite', 'job 1', pin)]);
  assert.deepEqual([none.rev, none.fight, none.firstRev, none.firstFight], Array(4).fill('undecided'), 'no brick pass');
});

test('the first stretch of a pass: its reversals and fights, or null without an open stretch', () => {
  const f = firstStretch({ ...record(), ca: [[5223, 1, 105], [5223, 1, 300]] });
  assert.ok(f && Number.isInteger(f.reversals) && Number.isInteger(f.fights));
  assert.equal(firstStretch({ ...record(), o: record().o.map(() => 0) }), null);
  assert.equal(firstStretch({ ...record(), r: undefined }), null);
});

test('first stretches count one open start per pass on both sides', () => {
  assert.deepEqual(perStretch([0, 3]), [[0, 1], [3, 1]]);
});
