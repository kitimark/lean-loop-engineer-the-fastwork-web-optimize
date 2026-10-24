import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  CONSTS, PARTS, KEYS, EXAMPLES, ARMS, reach, predicted, rowsOf, medianGap, bandFor, excludeReason, seriesCounts, armSeries, judge, judgeCounts, judgeArm, poolOf, inDomain, MIN_K,
  seriesModel, reduceMode, partVerdict, partOf, noDataParts, noDataReason, recordedParts, summarize, summaryMd, modeOfArm,
} from '../src/throttle/parts.mjs';
import { SERIES, ANCHORS, START_JS, FETCH_JS, discoverJs, scrollToJs, anchorY } from '../src/throttle/parts-recorder.mjs';
import { anchorOf, MODES } from '../src/throttle/parts-probe.mjs';
import { tagOf, dragOf, rotate, report } from '../src/throttle/parts-cli.mjs';
import { runs, bandRuns, throttleK } from '../src/throttle/stillruns.mjs';
import { maxStep } from '../src/device-session.mjs';


test('the constants are the golden ones', () => {
  assert.equal(throttleK(CONSTS.d60), CONSTS.throttleK60);
  assert.equal(throttleK(CONSTS.d120), CONSTS.throttleK120);
  assert.equal(CONSTS.period60, CONSTS.throttleK60 + 1);
  assert.deepEqual(bandFor(CONSTS.d60), [CONSTS.bandLo, CONSTS.bandHi]);
  assert.deepEqual(bandFor(CONSTS.d120), [12, 13]);
});

test('reach agrees with the golden for all 23 parts: 9 hit, 9 harmless, 5 not hit', () => {
  assert.equal(PARTS.length, 23);
  for (const p of PARTS) assert.equal(reach(p.source, p.shape), p.reach, p.id);
  const n = (r) => PARTS.filter((p) => p.reach === r).length;
  assert.deepEqual([n('hit'), n('harmless'), n('not-hit')], [9, 9, 5]);
});

test('predicted agrees with the golden key lines in both modes', () => {
  assert.deepEqual([...KEYS.keys()].sort(), ['fade', 'hero', 'people']);
  for (const k of KEYS.values()) {
    for (const mode of ['throttled', 'lifted']) {
      const p = predicted(mode, k.source, k.shape);
      assert.equal(p.pattern, k.predicted[mode].pattern, `${k.key} ${mode}`);
      if (p.pattern === 'stills') assert.equal(p.runFrames, k.predicted[mode].runFrames);
    }
  }
});

test('the series model takes the golden key when there is one and the twin of Lean predicted otherwise', () => {
  for (const s of SERIES) {
    const m = seriesModel(s);
    assert.equal(m.part.id, s.part);
    assert.equal(m.lifted.pattern, 'no-stills', s.key);
    const viaTwin = predicted('throttled', m.part.source, m.part.shape);
    assert.deepEqual(m.throttled, s.golden ? { pattern: KEYS.get(s.golden).predicted.throttled.pattern, ...(KEYS.get(s.golden).predicted.throttled.runFrames ? { runFrames: KEYS.get(s.golden).predicted.throttled.runFrames } : {}) } : viaTwin);
  }
  assert.equal(seriesModel(SERIES.find((s) => s.key === 'hero')).throttled.pattern, 'stills');
  assert.equal(seriesModel(SERIES.find((s) => s.key === 'platform')).throttled.pattern, 'stills');
  assert.equal(seriesModel(SERIES.find((s) => s.key === 'people')).throttled.pattern, 'pulses');
  assert.equal(seriesModel(SERIES.find((s) => s.key === 'commission')).throttled.pattern, 'stills');
  assert.equal(seriesModel(SERIES.find((s) => s.key === 'fade')).throttled.pattern, 'no-stills');
});

test('runs, band and maxStep on the golden example series', () => {
  assert.equal(EXAMPLES.length, 6);
  for (const e of EXAMPLES) {
    for (const mode of ['throttled', 'lifted']) {
      const x = e[mode];
      const rows = rowsOf(x.values);
      assert.deepEqual(runs(rows).map((r) => r.k), x.runs, `${e.shape} ${mode} runs`);
      assert.equal(bandRuns(rows), x.band, `${e.shape} ${mode} band`);
      assert.equal(maxStep(rows), x.maxStep, `${e.shape} ${mode} maxStep`);
    }
  }
});

test('every golden part is a series or a named no-data, and the series are parts of the golden', () => {
  const rec = recordedParts();
  for (const id of rec) assert.ok(PARTS.some((p) => p.id === id), id);
  const nd = noDataParts();
  assert.equal(nd.length + rec.size, PARTS.length);
  for (const p of nd) assert.ok(p.reason.length > 10, p.id);
  assert.match(noDataReason(PARTS.find((p) => p.id === 'hero.exit:threaded')), /flag/);
  assert.match(noDataReason(PARTS.find((p) => p.id === 'pain.dark')), /compositor/);
  assert.match(noDataReason(PARTS.find((p) => p.id === 'morph.mount')), /reversal/);
  assert.match(noDataReason(PARTS.find((p) => p.id === 'nav')), /flip/);
  assert.match(noDataReason(PARTS.find((p) => p.id === 'hero.cue')), /nothing to record/);
});

test('the arms: originals and the rewrite are throttled, the lifted flag and unthrottle are lifted', () => {
  assert.deepEqual(ARMS.map(modeOfArm), ['throttled', 'throttled', 'lifted', 'lifted']);
});


test('the band follows the frame gap: 5-6 at 60 Hz, 2-3 at a 35 ms gap', () => {
  const ts = (g, n) => Array.from({ length: n }, (_, i) => i * g);
  assert.equal(medianGap(ts(16.67, 50)), 1667);
  assert.equal(medianGap([]), 1667);
  assert.deepEqual(bandFor(medianGap(ts(16.67, 50))), [5, 6]);
  assert.deepEqual(bandFor(medianGap(ts(35, 50))), [2, 3]);
});


function partsRecord(n, series, gap = 16.67) {
  const t = Array.from({ length: n }, (_, i) => Math.round(i * gap * 100) / 100);
  const v = {}, found = {};
  for (const s of SERIES) { v[s.key] = series[s.key] ? Array.from({ length: n }, (_, i) => series[s.key](i)) : Array(n).fill(0); found[s.key] = Boolean(series[s.key]); }
  return { start: { vh: 8000, y: 0, scale: 1 }, found, frames: n, t, y: Array.from({ length: n }, (_, i) => i * 10), vh: Array.from({ length: n }, (_, i) => 8000 + (i % 2) * 40), v, total: n };
}
const pass = (arm, parts, extra = {}) => ({ arm, round: 1, vm: '1', drag: { code: 0 }, rec: { parts }, ...extra });
const stairs = (period, from = 100) => (i) => from + Math.floor(i / period) * 5;

test('a pass counts only with touches that worked, travel, enough frames and no zoom', () => {
  const ok = partsRecord(300, { hero: stairs(6) });
  assert.equal(excludeReason(pass('rewrite', ok)), null);
  assert.equal(excludeReason(pass('rewrite', ok, { drag: { code: 65 } })), 'touch driver failed');
  assert.equal(excludeReason(pass('rewrite', ok, { drag: { code: null, timedOut: true } })), 'touch driver timed out');
  assert.equal(excludeReason({ arm: 'rewrite', skipped: 'anchor people not found' }), 'anchor people not found');
  assert.match(excludeReason(pass('rewrite', partsRecord(30, { hero: stairs(6) }))), /fewer than/);
  assert.match(excludeReason(pass('rewrite', { ...ok, y: ok.y.map(() => 5) })), /moved less than/);
  assert.match(excludeReason(pass('rewrite', { ...ok, start: { ...ok.start, scale: 1.5 } })), /zoomed/);
  assert.equal(excludeReason({ arm: 'rewrite', drag: { code: 0 }, rec: {} }), 'no parts record');
});

test('a series that holds its value for 6 frames has one band run per hold; the same series moving every frame has none', () => {
  const throttled = seriesCounts(partsRecord(300, { hero: stairs(6) }), 'hero');
  assert.equal(throttled.found, true);
  assert.equal(throttled.band, 49);
  assert.equal(throttled.band56, 49);
  assert.equal(throttled.midMoving, 300);
  assert.equal(throttled.moving, 300);
  const lifted = seriesCounts(partsRecord(300, { hero: stairs(1) }), 'hero');
  assert.equal(lifted.band, 0);
  assert.equal(seriesCounts(partsRecord(300, {}), 'hero').found, false);
});

test('stalls are frame pairs in which the page moved and the mid-transition value stood still (the phone summary count)', () => {
  const c = seriesCounts(partsRecord(300, { hero: stairs(6) }), 'hero');
  assert.equal(c.pairs, 299);
  assert.equal(c.stalls, 299 - 49 - 1);
  assert.equal(seriesCounts(partsRecord(300, { hero: stairs(1) }), 'hero').stalls, 0);
  const a = armSeries([pass('rewrite', partsRecord(300, { hero: stairs(6) }))], 'hero');
  assert.equal(a.stallsPer1000, 832.8);
});

test('values at 0 or 1000 are not runs of the mid-transition, and a still toolbar is not moving', () => {
  const flat = seriesCounts(partsRecord(300, { hero: (i) => (i < 150 ? 0 : 1000) }), 'hero');
  assert.equal(flat.band, 0);
  assert.equal(flat.midMoving, 0);
  const still = partsRecord(300, { hero: stairs(6) });
  still.vh = still.vh.map(() => 8000);
  const c = seriesCounts(still, 'hero');
  assert.equal(c.moving, 0);
  assert.equal(c.band, 0);
  assert.equal(c.midMoving, 0);
});

test('at a 35 ms frame gap the cadence band counts the 3-frame holds the fixed 5-6 band misses', () => {
  const c = seriesCounts(partsRecord(300, { hero: stairs(3) }, 35), 'hero');
  assert.equal(c.lo, 2);
  assert.equal(c.hi, 3);
  assert.equal(c.band, 99);
  assert.equal(c.band56, 0);
});

const hero = (rows) => rows.find((s) => s.key === 'hero');

test('hero: rewrite and original show stills, lift and unthrottle do not: predicted stills agrees, verdict lifted', () => {
  const passes = [];
  for (const arm of ['original', 'rewrite']) passes.push(pass(arm, partsRecord(300, { hero: stairs(6) })), pass(arm, partsRecord(300, { hero: stairs(6) }), { vm: '2' }));
  for (const arm of ['lift', 'unthrottle']) passes.push(pass(arm, partsRecord(300, { hero: stairs(1) })));
  const h = hero(reduceMode(passes));
  assert.equal(h.rows.rewrite.band, 98);
  assert.equal(h.rows.rewrite.midMoving, 600);
  assert.equal(h.verdicts.lift, 'lifted');
  assert.equal(h.verdicts.unthrottle, 'lifted');
  for (const a of ARMS) assert.equal(h.match[a].match, 'agree', a);
  assert.equal(h.perJob.length, 2);
  assert.equal(partOf(reduceMode(passes).filter((s) => s.part === 'hero.exit')), 'agree');
});

test('hero: a lift arm that keeps the stills is not-lifted and disagrees with the prediction', () => {
  const passes = [pass('rewrite', partsRecord(300, { hero: stairs(6) })), pass('lift', partsRecord(300, { hero: stairs(6) })), pass('unthrottle', partsRecord(300, { hero: stairs(1) }))];
  const h = hero(reduceMode(passes));
  assert.equal(h.verdicts.lift, 'not-lifted');
  assert.equal(h.match.lift.match, 'disagree');
  assert.equal(h.match.unthrottle.match, 'agree');
  assert.equal(partOf([h]), 'disagree');
});

test('a throttled arm predicted to show stills but showing none disagrees; a base without stills leaves the lifted arms no-data', () => {
  const passes = [pass('rewrite', partsRecord(300, { hero: stairs(1) })), pass('lift', partsRecord(300, { hero: stairs(1) }))];
  const h = hero(reduceMode(passes));
  assert.equal(h.match.rewrite.match, 'disagree');
  assert.equal(h.verdicts.lift, 'no-data');
  assert.equal(h.match.lift.match, 'no-data');
});

test('an arm without frames of the series in transition is no-data, not agreement', () => {
  const h = hero(reduceMode([pass('rewrite', partsRecord(300, {}))]));
  assert.equal(h.match.rewrite.match, 'no-data');
  assert.equal(h.match.original.match, 'no-data');
  assert.equal(partOf([h]), 'no-data');
});

test('the fade (time source) is predicted no stills in every arm; a throttle-like series disagrees', () => {
  const calm = reduceMode([pass('rewrite', partsRecord(300, { fade: stairs(1) })), pass('lift', partsRecord(300, { fade: stairs(1) }))]);
  const fade = calm.find((s) => s.key === 'fade');
  assert.equal(fade.match.rewrite.match, 'agree');
  assert.equal(fade.match.lift.match, 'agree');
  const bad = reduceMode([pass('rewrite', partsRecord(300, { fade: stairs(6) }))]).find((s) => s.key === 'fade');
  assert.equal(bad.match.rewrite.match, 'disagree');
});

test('judgeArm: pulses and no-stills need fewer than 10 band runs; exactly 10 disagrees', () => {
  const row = (band, midMoving = 300, k = 5) => ({ midMoving, band, found: 1, exercised: 1, domain: { passes: 1 }, detail: [{ gapMs: 17 }], passList: [{ k, runs: band, frames: midMoving }] });
  const pulses = { pattern: 'pulses' };
  assert.equal(judgeArm(pulses, 'rewrite', row(3), row(3)).match, 'agree');
  assert.equal(judgeArm(pulses, 'rewrite', row(10), row(10)).match, 'disagree');
  assert.equal(judgeArm(pulses, 'rewrite', row(12), row(12)).match, 'disagree');
  assert.equal(judgeArm({ pattern: 'no-stills' }, 'lift', row(0), row(40)).match, 'agree');
  assert.equal(judgeArm({ pattern: 'stills', runFrames: 5 }, 'rewrite', row(10), row(10)).match, 'agree');
});


const goldenOf = (kind) => readFileSync(new URL('../../contracts/golden/device/throttle-parts.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l)).filter((l) => l.kind === kind);

test('judgeCounts returns the golden match on every judgeCounts vector (Fw.Device.ThrottleParts.judgeCounts)', () => {
  const vs = goldenOf('judgeCounts');
  assert.equal(vs.length, 240);
  const seen = new Set();
  for (const v of vs) {
    assert.equal(judgeCounts(v.pred, v.mode, v.base, v.arm), v.match, JSON.stringify(v));
    seen.add(v.match);
  }
  assert.deepEqual([...seen].sort(), ['agree', 'disagree', 'no-data']);
});

test('judge returns the golden match on every pass vector (Fw.Device.ThrottleParts.judge)', () => {
  const vs = goldenOf('judge');
  assert.equal(vs.length, 468);
  const seen = new Set();
  for (const v of vs) {
    assert.equal(judge(v.pred, v.mode, v.base, v.arm), v.match, JSON.stringify(v));
    seen.add(v.match);
  }
  assert.deepEqual([...seen].sort(), ['agree', 'disagree', 'no-data']);
});

test('judge: a pass at K below the domain counts for nothing, K is per pass', () => {
  assert.equal(MIN_K, CONSTS.minK);
  assert.equal(MIN_K, 3);
  const vs = goldenOf('judge');
  const only = (arm) => vs.filter((v) => v.arm.length === arm.length && v.arm.every((q, i) => q.k === arm[i].k && q.runs === arm[i].runs && q.frames === arm[i].frames));
  for (const v of only([{ k: 1, runs: 10, frames: 1000 }, ])) assert.equal(v.match, 'no-data', JSON.stringify(v));
  assert.ok(only([{ k: 1, runs: 10, frames: 1000 }]).length > 0);
  const mixed = only([{ k: 5, runs: 9, frames: 500 }, { k: 1, runs: 30, frames: 500 }]);
  assert.ok(mixed.length > 0);
  for (const v of mixed) assert.deepEqual(poolOf(v.arm), { runs: 9, frames: 500 });
  assert.deepEqual(poolOf([{ k: 2, runs: 5, frames: 7 }, { k: 3, runs: 1, frames: 2 }]), { runs: 1, frames: 2 });
  assert.equal(inDomain(2), false);
  assert.equal(inDomain(3), true);
});

test('judge: the golden holds the boundary at exactly 10 band runs', () => {
  const at = (pattern, mode, runs) => goldenOf('judgeCounts').find((v) => v.pred.pattern === pattern && v.mode === mode && v.base.runs === 40 && v.arm.runs === runs && v.arm.frames === 1000);
  assert.equal(at('stills', 'throttled', 10).match, 'agree');
  assert.equal(at('stills', 'throttled', 9).match, 'disagree');
  assert.equal(at('pulses', 'throttled', 10).match, 'disagree');
  assert.equal(at('pulses', 'throttled', 9).match, 'agree');
  assert.equal(at('no-stills', 'lifted', 10).match, 'disagree');
  assert.equal(at('stills', 'lifted', 8).match, 'agree');
  assert.equal(at('stills', 'lifted', 9).match, 'disagree');
});

test('partVerdict returns the golden verdict on every list of up to three matches (Fw.Device.ThrottleParts.partVerdict)', () => {
  const vs = goldenOf('partVerdict');
  assert.equal(vs.length, 40);
  for (const v of vs) assert.equal(partVerdict(v.matches), v.verdict, JSON.stringify(v));
});

test('bandFor returns the golden band on every bandFor vector (Fw.Device.ThrottleParts.bandFor)', () => {
  const vs = goldenOf('bandFor');
  assert.ok(vs.some((v) => v.d === 1667 && v.lo === 5 && v.hi === 6));
  for (const v of vs) {
    assert.deepEqual(bandFor(v.d), [v.lo, v.hi], String(v.d));
    assert.equal(inDomain(v.lo), v.inDomain, String(v.d));
    assert.equal(v.lo >= CONSTS.bandLo && v.lo <= CONSTS.bandHi, v.fixed, String(v.d));
  }
  const gap = (d) => vs.find((v) => v.d === d);
  assert.deepEqual([5900, 2300, 2000, 3300, 3333, 3334].map((d) => gap(d).lo), [1, 4, 4, 3, 3, 2]);
  assert.deepEqual(vs.filter((v) => v.fixed).map((v) => v.d), [1429, 1600, 1667, 1700, 1999]);
});

test('armSeries sums the usable passes only and keeps the pass counts', () => {
  const a = armSeries([pass('rewrite', partsRecord(300, { hero: stairs(6) })), pass('rewrite', partsRecord(300, { hero: stairs(6) }), { drag: { code: 1 } })], 'hero');
  assert.equal(a.passes, 2);
  assert.equal(a.usable, 1);
  assert.equal(a.band, 49);
  assert.equal(a.per1000Mid, 163.3);
});

test('armSeries: the gap and K are per exercised pass; a pass outside the domain stays in the table and out of the verdict pool', () => {
  const a = armSeries([
    pass('original', partsRecord(300, { hero: stairs(6) }), { vm: '1', round: 2 }),
    pass('original', partsRecord(300, { hero: stairs(1) }, 60), { vm: '2', round: 1 }),
    pass('original', partsRecord(300, { hero: () => 0 }, 25), { vm: '3', round: 1 }),
  ], 'hero');
  assert.equal(a.found, 3);
  assert.equal(a.exercised, 2);
  assert.deepEqual(a.gaps, [1667, 6000]);
  assert.deepEqual(a.detail.map((d) => [d.vm, d.round, d.gapMs, d.k, d.bandRuns, d.midMoving, d.inDomain]), [['1', 2, 16.67, 5, 49, 300, true], ['2', 1, 60, 1, 0, 180, false]]);
  assert.deepEqual(a.domain, { passes: 1, band: 49, midMoving: 300, per1000Mid: 163.3 });
  assert.equal(a.band, 49);
  assert.equal(a.midMoving, 480);
  const only = armSeries([pass('original', partsRecord(300, { hero: stairs(1) }, 60))], 'hero');
  assert.deepEqual(only.domain, { passes: 0, band: 0, midMoving: 0, per1000Mid: null });
  assert.equal(judgeCounts({ pattern: 'stills' }, 'throttled', { runs: 0, frames: 0 }, { runs: only.domain.band, frames: only.domain.midMoving }), 'no-data');
});

test('the summary median gap is taken over the exercised passes only, and a K-1 original arm is no-data with its gap named', () => {
  const mk = (arm, parts, extra) => ({ arm, round: 1, vm: '1', attempt: 1, info: {}, where: {}, drag: { code: 0 }, rec: { parts }, ...extra });
  const jobs = [{ vm: '1', mode: 'drags', drag: {}, failed: [], passes: [
    mk('original', partsRecord(300, { hero: stairs(1) }, 60)),
    mk('original', partsRecord(300, { hero: () => 0 }, 16.67), { round: 2 }),
    mk('rewrite', partsRecord(300, { hero: stairs(6) })),
    mk('lift', partsRecord(300, { hero: stairs(1) })),
    mk('unthrottle', partsRecord(300, { hero: stairs(1) })),
  ] }];
  const sm = summarize('drags', jobs, '9');
  const s = sm.series.find((x) => x.key === 'hero');
  assert.equal(s.arms.original.medianGapMs, 60);
  assert.equal(s.arms.original.exercisedPasses.length, 1);
  assert.equal(s.match.original.match, 'no-data');
  assert.match(s.match.original.why, /K below 3/);
  assert.match(s.match.original.why, /60/);
  assert.equal(s.arms.rewrite.medianGapMs, 16.67);
});

function heroJobs() {
  const mk = (arm, period) => ({ arm, round: 1, vm: '1', attempt: 1, info: {}, where: {}, drag: { code: 0 }, rec: { parts: partsRecord(300, { hero: stairs(period) }) } });
  return [{ vm: '1', mode: 'drags', drag: {}, failed: [], passes: [mk('original', 6), mk('rewrite', 6), mk('lift', 1), mk('unthrottle', 1)] }];
}

test('the summary and its table carry the run id, every arm and the Lean verdicts', () => {
  const sm = summarize('drags', heroJobs(), '123');
  const s = sm.series.find((x) => x.key === 'hero');
  assert.equal(s.verdicts.lift, 'lifted');
  assert.equal(s.arms.rewrite.medianGapMs, 16.67);
  assert.equal(sm.lost.find((l) => l.arm === 'lift').usable, 1);
  const md = summaryMd(sm);
  assert.match(md, /### drags \(run 123, 1 jobs\)/);
  assert.match(md, /\| hero \(hero\.exit\) \| unthrottle \| 1\/1 \| 1 \(1\) \| 16\.67 \| 0 \/ 180 \| 0 \/ 180 \|/);
  assert.match(md, /\| hero\.exit \| agree/);
  assert.equal(JSON.stringify(sm).includes('"gaps"'), false);
});

test('report reads job files and writes the md and the json', () => {
  const dir = mkdtempSync(join(tmpdir(), 'parts-'));
  const f = join(dir, 'a.json');
  writeFileSync(f, JSON.stringify(heroJobs()[0]));
  const out = { md: join(dir, 'a.md'), json: join(dir, 'a.json.out') };
  const sm = report({ in: f, md: out.md, json: out.json, run: '9' });
  assert.equal(sm.mode, 'drags');
  assert.match(readFileSync(out.md, 'utf8'), /run 9/);
  assert.equal(JSON.parse(readFileSync(out.json, 'utf8')).runId, '9');
  writeFileSync(join(dir, 'b.json'), JSON.stringify({ ...heroJobs()[0], mode: 'finish' }));
  assert.throws(() => report({ in: `${f},${join(dir, 'b.json')}` }), /different modes/);
});


test('a retry never reuses the result bundle tag of the first attempt', () => {
  assert.equal(tagOf('lift', 2, 1), 'lift-r2');
  assert.notEqual(tagOf('lift', 2, 1), tagOf('lift', 2, 2));
  assert.deepEqual(rotate(['a', 'b', 'c'], 1), ['b', 'c', 'a']);
  assert.equal(dragOf('finish', { cycles: '4', hold: '600', target: 't' }).dragPt, 480);
  assert.equal(dragOf('rest', { cycles: '4', hold: '600', target: 't' }).mode, 'drags');
  assert.deepEqual([...MODES], ['drags', 'finish', 'rest']);
  assert.deepEqual([1, 2, 3, 4].map(anchorOf), ['people', 'commissionEnter', 'platform', 'people']);
  assert.equal(anchorY(null), null);
  assert.equal(anchorY(500), 440);
  assert.equal(anchorY(20), 0);
  assert.ok(ANCHORS.every((k) => SERIES.some((s) => s.key === k)));
});


function page(values) {
  const q = [], listeners = [];
  const g = { scrollY: 0, innerHeight: 800, document: { documentElement: { scrollHeight: 1800 }, querySelector: (sel) => {
    const prop = Object.keys(values).find((p) => sel.includes(p));
    return prop === undefined || values[prop] === null ? null : { isConnected: true, style: { getPropertyValue: (p) => String(values[p]) } };
  } }, addEventListener: (type, fn) => listeners.push([type, fn]), requestAnimationFrame: (cb) => q.push(cb), scrollTo: (o) => { g.scrollY = o.top; } };
  g.window = g;
  vm.createContext(g);
  const frame = (ts) => { const cbs = q.splice(0); for (const cb of cbs) cb(ts); };
  const scrolled = () => listeners.filter(([t]) => t === 'scroll').forEach(([, fn]) => fn());
  return { g, frame, scrolled };
}

test('the recorder stores per-mille values from the first scroll on and stops at the last change', () => {
  const values = { '--exit-opacity': 0.5, '--future-shrink': null, '--commission-enter-shrink': null, '--commission-shrink': null, '--platform-shrink': null, '--morph-fade': 0.25 };
  const p = page(values);
  assert.equal(vm.runInContext(START_JS, p.g), 'started');
  p.frame(1); p.frame(2);
  p.g.scrollY = 10; p.scrolled();
  p.frame(3);
  values['--exit-opacity'] = 0.6; p.g.scrollY = 20; p.frame(4);
  p.frame(5); p.frame(6);
  const rec = JSON.parse(vm.runInContext(FETCH_JS, p.g));
  assert.equal(rec.total, 4);
  assert.equal(rec.frames, 2);
  assert.deepEqual(rec.v.hero, [500, 600]);
  assert.deepEqual(rec.v.fade, [250, 250]);
  assert.deepEqual(rec.v.people, [0, 0]);
  assert.deepEqual(rec.found, { hero: true, people: false, commissionEnter: false, commission: false, platform: false, fade: true });
  assert.deepEqual(rec.y, [100, 200]);
  assert.deepEqual(rec.vh, [8000, 8000]);
});

test('the recorder counts a value change as movement (the fade runs on after the scroll stops)', () => {
  const values = { '--morph-fade': 0.1 };
  const p = page(values);
  vm.runInContext(START_JS, p.g);
  p.g.scrollY = 10; p.scrolled(); p.frame(1);
  values['--morph-fade'] = 0.2; p.frame(2);
  values['--morph-fade'] = 0.3; p.frame(3);
  p.frame(4);
  const rec = JSON.parse(vm.runInContext(FETCH_JS, p.g));
  assert.equal(rec.frames, 3);
  assert.deepEqual(rec.v.fade, [100, 200, 300]);
});

test('the recorder fetch before a start reports an error', () => {
  assert.match(JSON.parse(vm.runInContext(FETCH_JS, page({}).g)).err, /not started/);
});

test('discover finds the first scrollY at which each series is in transition', async () => {
  const p = page({});
  const ramp = (a, b) => () => { const y = p.g.scrollY; return y <= a ? 0 : y >= b ? 1 : (y - a) / (b - a); };
  const val = { '--exit-opacity': ramp(200, 400), '--commission-shrink': null };
  p.g.document.querySelector = (sel) => {
    const prop = Object.keys(val).find((k) => sel.includes(k));
    return prop === undefined || val[prop] === null ? null : { style: { getPropertyValue: () => String(val[prop]()) } };
  };
  p.g.requestAnimationFrame = (cb) => setTimeout(() => cb(0), 0);
  const out = JSON.parse(await vm.runInContext(discoverJs(40), p.g));
  assert.equal(out.maxY, 1000);
  assert.equal(out.at.hero, 240);
  assert.equal(out.at.commission, null);
  assert.equal(p.g.scrollY, 0);
  assert.equal(JSON.parse(vm.runInContext(scrollToJs(333.4), p.g)).y, 333);
});
