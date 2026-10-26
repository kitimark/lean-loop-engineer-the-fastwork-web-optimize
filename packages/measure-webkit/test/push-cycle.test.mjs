import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import * as P from '../src/throttle/push-cycle.mjs';
import { armTable, reportMd } from '../src/throttle/push-cycle-report.mjs';
import { EXTRA_START_JS } from '../src/throttle/push-cycle-page.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(join(HERE, '../../contracts/golden/measure/push-cycle.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);

test('constants match the Lean module', () => {
  const [c] = ops('constants');
  assert.equal(P.CYCLES, c.cycles);
  assert.equal(P.LEG_FRAMES, c.legFrames);
  assert.equal(P.THROTTLE_MS, c.throttleMs);
  assert.equal(P.TICK, c.tick);
  assert.equal(P.LIFT_GAP, c.liftGap);
  assert.equal(P.FINGER_X, c.fingerX);
  assert.equal(P.START_Y, c.startY);
  assert.equal(P.TOP_Y, c.topY);
  assert.equal(P.H1_MIN_CHANGES, c.h1MinChanges);
  assert.equal(P.H1_MIN_SLOW, c.h1MinSlow);
  assert.equal(P.poolCap(false), c.iosPoolB);
  assert.equal(P.poolCap(true), c.macPoolB);
});

test('the cost model: per-cycle series, totals, single open and trend', () => {
  const cases = ops('model');
  assert.ok(cases.length >= 4);
  for (const g of cases) {
    assert.deepEqual(P.series(g.cost, false, 6), g.released, g.case);
    assert.deepEqual(P.series(g.cost, true, 6), g.kept, g.case);
    assert.equal(P.totalWork(g.cost, false, 6), g.totalReleased, g.case);
    assert.equal(P.totalWork(g.cost, true, 6), g.totalKept, g.case);
    assert.equal(P.single(g.cost), g.single, g.case);
    assert.equal(P.trend(g.released), g.trendReleased, g.case);
    assert.equal(P.trend(g.kept), g.trendKept, g.case);
  }
});

test('repaint and pixels (H3)', () => {
  for (const g of ops('repaint')) {
    assert.equal(P.reattachPaint(g.area, P.cycleFlags(g.n)), g.released);
    assert.equal(P.reattachPaint(g.area, [false, ...Array(2 * g.n - 1).fill(true)]), g.kept);
    assert.equal(P.cyclePx(2, g.area, g.n), g.px2);
    assert.equal(P.cyclePx(3, g.area, g.n), g.px3);
  }
});

test('the pool (H4) and the visible-rect updates (H1)', () => {
  for (const g of ops('pool')) {
    assert.equal(P.realloc(P.poolCap(false), g.released), g.ios);
    assert.equal(P.realloc(P.poolCap(true), g.released), g.mac);
  }
  for (const g of ops('updates')) assert.equal(P.updatesIn(g.spanMs), g.updates);
});

test('the verdicts of H1 to H4', () => {
  for (const g of ops('h1')) assert.equal(P.h1Verdict(g), g.verdict, g.case);
  for (const g of ops('h2')) assert.equal(P.h2Verdict(g), g.verdict, g.case);
  for (const g of ops('pix')) {
    assert.equal(P.h3Verdict(g), g.h3, g.case);
    assert.equal(P.h4Verdict(g), g.h4, g.case);
  }
  for (const g of ops('trend')) assert.equal(P.trend(g.series), g.trend, JSON.stringify(g.series));
});

test('the cycle plan: lengths, windows, strokes of the golden', () => {
  const plans = ops('plan');
  assert.deepEqual(plans.map((p) => p.dwellMs), [300, 1000]);
  for (const g of plans) {
    assert.equal(P.dwellFrames(g.dwellMs), g.dwellFrames);
    assert.equal(P.cycleLen(g.dwellFrames), g.cycleLen);
    assert.equal(P.endFrame(g.n, g.dwellFrames), g.endFrame);
    assert.deepEqual(Array.from({ length: g.n }, (_, k) => P.windowOf(g.dwellFrames, k)), g.windows);
    assert.equal(g.strokes.length, g.n);
    g.strokes.forEach((s, i) => {
      assert.equal(s.f0, i * g.cycleLen);
      assert.equal(s.path.length, g.cycleLen);
      for (const [x, y] of s.path) { assert.ok(x >= 0 && x <= 430); assert.ok(y >= 0 && y <= 775); }
    });
  }
});

test('the phone replay profile equals the Lean profile', () => {
  for (const g of ops('phone')) assert.deepEqual(P.phoneProfile(P.CYCLES, g.dwellMs), g.profile);
});

test('the committed phone profiles (for phone-compose-counts) are the Lean profiles', () => {
  for (const g of ops('phone')) {
    const f = readFileSync(join(HERE, `../../../results/push-cycle-lag/phone-profile-d${g.dwellMs}.json`), 'utf8');
    assert.deepEqual(JSON.parse(f), g.profile);
  }
});

function synthetic() {
  const n = 620, t = [], y = [], o = [], ih = [], vh = [];
  let now = 0;
  for (let i = 0; i < n; i++) {
    now += i === 131 || i === 132 ? 60 : i === 400 ? 40 : 16;
    t.push(now);
    const k = Math.floor((i - 20) / 100), r = (i - 20) - 100 * k;
    o.push(i >= 20 && r >= 0 && r < 60 ? 1 : 0);
    y.push(50000 + (i % 7) + 3 * i);
    ih.push(i < 130 ? 7800 : 7000);
    vh.push(i < 130 ? 7800 : 7000);
  }
  return { t, y, mx: y.map(() => 52000), o, r: o.map(() => 0), d: o.map(() => 0), ih, vh, ca: [], rz: [130], vvr: [130], vvs: [], nav: true, frames: n, start: { scale: 1 } };
}

test('recordCycles cuts a record at the open stretches and counts slow frames near a viewport change', () => {
  const rec = synthetic();
  const cyc = P.recordCycles(rec);
  assert.equal(cyc.length, 6);
  assert.deepEqual(cyc.map((c) => c.from), [20, 120, 220, 320, 420, 520]);
  assert.equal(cyc[1].viewportChanges, 1);
  assert.equal(cyc[1].slow34, 2);
  assert.equal(cyc[1].slow50, 2);
  assert.equal(cyc[1].slowNear34, 2);
  assert.equal(cyc[1].slowFar34, 0);
  assert.equal(cyc[1].resizes, 1);
  assert.equal(cyc[1].vvResizes, 1);
  assert.equal(cyc[3].slowFar34, 1);
  assert.equal(cyc[3].slow50, 0);
  assert.equal(cyc[0].viewportChanges, 0);
  assert.equal(cyc[0].medianGap, 16);
  const v = P.verdictInputs([rec], 34);
  assert.equal(v.h1.changes, 1);
  assert.equal(v.h1.slowNear, 2);
  assert.equal(v.h1.slowFar, 1);
  assert.equal(P.h1Verdict(v.h1), 'open', 'one change is below the minimum');
  assert.deepEqual(P.indexSeries([rec, rec], 'slow34').sums, [0, 4, 0, 2, 0, 0]);
});

test('the arms: searches and the pages the site build prerenders', () => {
  assert.equal(P.searchOf('original'), null);
  assert.equal(P.searchOf('rewrite'), '');
  assert.ok(P.searchOf('user').startsWith('?fw=nav:earn-logical,'));
  assert.equal(P.searchOf('user').split(',').length, 9);
  assert.equal(P.searchOf('off-engine.scroll:unthrottle').split(',').length, 8);
  assert.ok(!P.searchOf('off-engine.scroll:unthrottle').includes('engine.scroll'));
  assert.ok(!P.searchOf('off-hero.countdown:strip').includes('countdown:strip'), 'morph.countdown:strip requires hero.countdown:strip, so both go');
  assert.ok(P.searchOf('off-morph.countdown:strip').includes('hero.countdown:strip'));
  assert.throws(() => P.searchOf('off-nothing'));
  assert.throws(() => P.searchOf('lift'));
  assert.deepEqual(P.searchesOf(['original', 'rewrite', 'user']), [P.searchOf('user')]);
  assert.deepEqual(P.searchesOf(['original', 'rewrite']), []);
});

test('the report table has one row per cycle and arm and orders off arms last', () => {
  const rec = synthetic();
  const pass = (arm) => ({ arm, round: 0, rec, drag: { code: 0 } });
  const jobs = [{ vm: 'job 1', drag: { holdMs: 300 }, passes: [pass('off-x'), pass('user'), pass('original'), pass('rewrite')] }];
  const t = armTable(jobs);
  assert.deepEqual(t.map((r) => r.arm), ['original', 'rewrite', 'user', 'off-x']);
  assert.equal(t[0].perK.length, 6);
  assert.equal(t[0].usable, 1);
  assert.equal(t[0].perK[1].slow34, 2);
  const md = reportMd(jobs);
  assert.match(md, /dwell 300 ms/);
  assert.match(md, /## user: 1 usable of 1 passes/);
  assert.match(md, /H2 \(fights per open/);
});

test('the extra recorder keys its events on the base recorder frame index', () => {
  assert.match(EXTRA_START_JS, /__fwFin/);
  assert.match(EXTRA_START_JS, /st\.t\.length/);
});

test('upload names: a colon (off-hero.countdown:strip) is replaced, plain names stay', () => {
  assert.equal(P.uploadName('1-driver-off-hero.countdown:strip-r1.log'), '1-driver-off-hero.countdown_strip-r1.log');
  assert.equal(P.uploadName('1-throttle.json'), '1-throttle.json');
  for (const a of ['user', 'off-hero.countdown:strip', 'off-morph.countdown:strip', 'off-engine.scroll:unthrottle']) assert.ok(!/[:<>|*?"\\]/.test(P.uploadName(`1-driver-${a}-r1.log`)));
});

test('cycle versus clock: constants, clock index, rest and the census reading replay the golden', () => {
  const [c] = ops('constants');
  assert.equal(P.SEP_MIN_PASSES, c.sepMinPasses);
  assert.equal(P.SEP_FULL_CYCLES, c.sepFullCycles);
  assert.equal(P.SEP_DWELL_CYCLES, c.sepDwellCycles);
  assert.deepEqual([...P.SEP_WINDOW], c.sepWindow);
  assert.ok(ops('clock').length >= 5);
  for (const g of ops('clock')) assert.deepEqual(Array.from({ length: P.SEP_FULL_CYCLES }, (_, k) => P.clockIndex(g.r, k)), g.index, `r ${g.r}`);
  assert.equal(P.clockIndex(1000, 7), 7, 'a stretch of 1 is the identity (Lean clockIndex_id)');
  assert.equal(P.stretch(60000, 30000), 2000);
  assert.equal(P.stretch(60000, 0), 0);
  assert.ok(ops('rest').length >= 5);
  for (const g of ops('rest')) assert.equal(P.restMs(g.target, g.spent, g.cap), g.rest, JSON.stringify(g));
  assert.ok(ops('census').length >= 6);
  for (const g of ops('census')) {
    assert.deepEqual(g.passes.map(P.trend), g.trends, g.case);
    assert.equal(P.readCensus(g.passes), g.across, g.case);
  }
});

test('cycle versus clock: every golden case gets the verdict, rates and stretch of the Lean rule', () => {
  const cases = ops('sep');
  assert.ok(cases.length >= 12);
  const seen = new Set(cases.map((g) => g.verdict));
  for (const v of ['cycleDriven', 'clockDriven', 'undecided:between', 'undecided:inseparable', 'undecided:fewFull', 'undecided:fewDwell',
    'undecided:noPeriod', 'undecided:noRoom', 'undecided:noObs']) assert.ok(seen.has(v), `a golden case reaches ${v}`);
  for (const g of cases) {
    const r = P.stretch(g.periodDwell, g.periodFull);
    assert.equal(r, g.r, g.case);
    assert.equal(P.rate(P.sepWindowOf(g.full, (k) => k)), g.idx, g.case);
    assert.equal(P.rate(P.sepWindowOf(g.full, (k) => P.clockIndex(r, k))), g.clock, g.case);
    assert.equal(P.rate(P.sepWindowOf(g.dwell, (k) => k)), g.dwellRate, g.case);
    assert.equal(P.sepVerdict(g), g.verdict, g.case);
  }
});

test('quiet ranges: a gap that overlaps a census or a rest is not counted, the others are', () => {
  const rec = synthetic();
  const base = P.recordCycles(rec);
  assert.equal(base[1].slow50, 2);
  const quiet = { ...rec, quiet: [[rec.t[130] - 5, rec.t[132] + 1]] };
  const cut = P.recordCycles(quiet);
  assert.equal(cut[1].slow50, 0, 'the two 60 ms gaps lie inside the quiet range');
  assert.equal(cut[3].slowFar34, base[3].slowFar34, 'a cycle outside the range keeps its count');
  assert.deepEqual(P.recordCycles({ ...rec, quiet: [] }), base);
  assert.equal(P.maskedGap(quiet, 131), true);
  assert.equal(P.maskedGap(quiet, 250), false);
  assert.equal(P.slowCounts(rec, 50).length, 6);
});

test('periodMs is the mean spacing of the first six opens; fewer opens give 0', () => {
  const rec = synthetic();
  const want = Math.round((rec.t[520] - rec.t[20]) / 5);
  assert.equal(P.periodMs(rec), want);
  assert.equal(P.periodMs({ ...rec, o: rec.o.map((x, i) => (i >= 400 ? 0 : x)) }), 0);
});
