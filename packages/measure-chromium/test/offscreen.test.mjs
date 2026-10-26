import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  SETTLE, MIN_RUNS, SLACK, KEYS, hidden, steady, sumWhere, blockSums, windowVec, cmp, reduction, verdict, verdictAll, noDataWhy,
  extraTraceCounts, reduceRun, summarize, markdown, parseLine,
} from '../src/offscreen.mjs';
import { parseProfile } from '../src/profile.mjs';
import './offscreen-windows.test.mjs';
const golden = readFileSync(new URL('../../contracts/golden/measure/offscreen.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);

test('offscreen: constants match Lean', () => {
  const c = ops('constants')[0];
  assert.equal(SETTLE, c.settle);
  assert.equal(MIN_RUNS, c.minRuns);
  assert.equal(SLACK, c.slack);
  assert.deepEqual(KEYS, c.keys);
});

test('offscreen: the hidden rule matches every golden rect', () => {
  assert.ok(ops('hidden').length >= 9);
  for (const g of ops('hidden')) assert.equal(hidden({ top: g.top, height: g.height, vh: g.vh }), g.hidden, g.case);
});

test('offscreen: settle mask, window sums and blocks match the golden windows', () => {
  assert.equal(ops('window').length, 3);
  for (const g of ops('window')) {
    const recs = g.tops.map((top) => ({ top, height: g.height, vh: g.vh }));
    assert.deepEqual(steady(g.settle, recs.map(hidden)), g.mask, `mask settle ${g.settle}`);
    const [firstKey, firstCol] = Object.entries(g.cols)[0];
    assert.deepEqual(blockSums(g.mask, firstCol), g.blocks, firstKey);
    assert.deepEqual(windowVec(g.settle, recs, g.cols), g.vec, `vec settle ${g.settle}`);
    assert.equal(blockSums(g.mask, firstCol).reduce((a, b) => a + b, 0), sumWhere(g.mask, firstCol), 'blocks partition the sum');
  }
});

test('offscreen: spread comparison and guaranteed reduction match the golden cases', () => {
  assert.ok(ops('cmp').length >= 7);
  for (const g of ops('cmp')) {
    assert.equal(cmp(g.slack, g.base, g.flag), g.cmp, g.case);
    assert.equal(reduction(g.base[0], g.flag[1]), g.reduction, g.case);
    assert.equal(g.cmp === 'less', g.slack < g.reduction, `${g.case}: less iff the guaranteed reduction exceeds the slack`);
  }
});

test('offscreen: every golden verdict case matches Lean, and each no-data reason is named', () => {
  const vs = ops('verdict');
  assert.deepEqual([...new Set(vs.map((g) => g.verdict))].sort(), ['gain', 'noData', 'noGain']);
  for (const g of vs) {
    assert.equal(verdict(g.base, g.flag), g.verdict, g.case);
    assert.equal(noDataWhy(g.base, g.flag) !== null, g.verdict === 'noData', `${g.case}: a reason exactly when there is no data`);
  }
  const why = Object.fromEntries(vs.map((g) => [g.case, noDataWhy(g.base, g.flag)]));
  assert.equal(why['few base runs'], 'fewBase(2)');
  assert.equal(why['few flag runs'], 'fewFlag(2)');
  assert.equal(why['empty window'], 'emptyWindow');
  assert.equal(why['windows differ'], 'windowDiffers');
  assert.equal(why['counter missing'], 'missingKey');
  assert.equal(why['no base runs'], 'fewBase(0)');
  assert.equal(why['no flag runs'], 'fewFlag(0)');
});

test('offscreen: each flag is decided on its own', () => {
  const g = ops('all')[0];
  assert.deepEqual(verdictAll(g.base, g.flags), g.verdicts);
  assert.deepEqual(g.verdicts, ['gain', 'noGain']);
  assert.deepEqual(verdictAll(g.base, [g.flags[1], g.flags[0]]), ['noGain', 'gain']);
});

const ev = (o) => ({ pid: 1, tid: 1, ts: 0, ph: 'X', dur: 0, ...o });
function synthTrace() {
  const events = [
    { pid: 1, tid: 1, ph: 'M', name: 'thread_name', args: { name: 'CrRendererMain' } },
    { pid: 1, tid: 2, ph: 'M', name: 'thread_name', args: { name: 'Compositor' } },
  ];
  for (let n = 0; n < 3; n++) {
    const t = 1000 * (n + 1);
    events.push(ev({ ts: t, ph: 'I', name: 'TimeStamp', args: { data: { message: `F${n}` } } }));
    events.push(ev({ ts: t + 1, name: 'RunTask', dur: 100 * (n + 1) }));
    events.push(ev({ ts: t + 2, name: 'ProxyMain::BeginMainFrame' }));
    events.push(ev({ ts: t + 3, name: 'PageAnimator::serviceScriptedAnimations' }));
    if (n !== 1) events.push(ev({ ts: t + 4, name: 'AnimationHost::TickAnimations' }));
    events.push(ev({ pid: 1, tid: 2, ts: t + 5, name: 'Scheduler::BeginImplFrame' }));
    if (n === 0) {
      events.push(ev({ tid: 2, ts: t + 6, ph: 'I', name: 'NeedsTickAnimations' }));
      events.push(ev({ tid: 2, ts: t + 7, name: 'AnimationHost::TickAnimations' }));
    }
  }
  events.push(ev({ ts: 9000, ph: 'I', name: 'ProxyMain::BeginMainFrame' }));
  return events;
}

test('offscreen: extra trace counts attribute main events by F marks and compositor events by BeginImplFrame windows', () => {
  const { perFrame, seen, beginImplFrames } = extraTraceCounts(synthTrace(), 3);
  assert.equal(beginImplFrames, 3);
  assert.deepEqual(perFrame[0], { 'trace.cc.BeginMainFrame': 1, 'trace.blink.ServiceScriptedAnimations': 1, 'trace.cc.TickAnimations': 2, 'busy.mainUs': 100, 'trace.cc.NeedsTick': 1 });
  assert.deepEqual(perFrame[1], { 'trace.cc.BeginMainFrame': 1, 'trace.blink.ServiceScriptedAnimations': 1, 'busy.mainUs': 200 });
  assert.equal(perFrame[2]['trace.cc.TickAnimations'], 1);
  assert.equal(seen['main.AnimationHost::TickAnimations'], 2);
  assert.equal(seen['compositor.NeedsTickAnimations'], 1);
});

function synthCounts(tops, over = {}) {
  const frames = tops.map((_, n) => ({ n, phase: n < 4 ? 'top' : 'near', scrollY: 0, vt: n, counts: { 'metric.LayoutCount': 1, 'trace.Paint': 2, ...over } }));
  return {
    meta: { target: 'rewrite', search: '?fw=x', viewport: { width: 430, height: 932 } }, frames,
    cardProbe: { selector: '#platform', frames: tops.map((top, n) => ({ n, found: true, rect: [0, top, 430, 800.4] })) },
  };
}

test('offscreen: a run record keeps the steady offscreen frames only and fills absent counters with zero', () => {
  const counts = synthCounts([1200.5, 1200.5, 1200.5, 1200.5, 1200.5, 300, 300, 1200.5, 1200.5]);
  const extra = { perFrame: counts.frames.map(() => ({ 'trace.cc.NeedsTick': 1 })), seen: {}, beginImplFrames: 9 };
  const r = reduceRun(counts, extra, { label: 'rewrite', run: '1' });
  assert.equal(r.hiddenFrames, 7);
  assert.deepEqual(r.mask, [false, false, false, true, true, false, false, false, false]);
  assert.equal(r.vec.n, 2);
  assert.equal(r.vec.vals['trace.Paint'], 4);
  assert.equal(r.vec.vals['trace.Layout'], 0);
  assert.equal(r.vec.vals['trace.cc.NeedsTick'], 2);
  assert.deepEqual(r.blocks['trace.Paint'], [4]);
});

test('offscreen: a probe that lost the element is refused', () => {
  const counts = synthCounts([1200, 1200]);
  counts.cardProbe.frames[1] = { n: 1, found: false };
  assert.throws(() => reduceRun(counts, null), /no element #platform/);
  assert.throws(() => reduceRun({ ...synthCounts([1]), cardProbe: { error: 'x' } }, null), /no section rects/);
});

test('offscreen: the summary decides each flag arm against the rewrite base and keeps the original as reference', () => {
  const rec = (label, run, tickSum, n = 100) => ({ label, run, vec: { n, vals: Object.fromEntries(KEYS.map((k) => [k, k === 'trace.cc.NeedsTick' ? tickSum : 10])) }, hiddenFrames: n + 3, info: {} });
  const recs = [
    ...[1, 2, 3].map((i) => rec('rewrite', i, 100 + i)), ...[1, 2, 3].map((i) => rec('f1', i, 0)), ...[1, 2, 3].map((i) => rec('f2', i, 100 + i)),
    ...[1, 2, 3].map((i) => rec('original', i, 90 + i, 80)),
  ];
  const sum = summarize(recs);
  assert.deepEqual(Object.fromEntries(Object.entries(sum.flags).map(([k, v]) => [k, v.verdict])), { f1: 'gain', f2: 'noGain' });
  assert.equal(sum.flags.f1.keys['trace.cc.NeedsTick'].cmp, 'less');
  assert.equal(sum.reference.window, '80');
  assert.match(markdown(sum), /### f1 vs rewrite: gain/);
  const few = summarize(recs.filter((r) => !(r.label === 'f1' && r.run === 3)));
  assert.equal(few.flags.f1.verdict, 'noData');
  assert.equal(few.flags.f2.verdict, 'noGain');
});

test('offscreen: the commit line is read key by key and refuses other text', () => {
  assert.deepEqual(parseLine('x [ci:chromium-counts]\n\n[counts profile=offscreen-v1 runs=3 target=both arms=platform.sweep:offscreen-pause|platform.glint:offscreen-pause]'),
    { profile: 'offscreen-v1', runs: '3', target: 'both', arms: 'platform.sweep:offscreen-pause|platform.glint:offscreen-pause' });
  assert.deepEqual(parseLine('no line here'), {});
  assert.throws(() => parseLine('[counts profile=a;b]'), /bad value/);
  assert.throws(() => parseLine('[counts evil=1]'), /unknown key/);
  assert.throws(() => parseLine('[counts profile]'), /not key=value/);
});

test('offscreen: profile offscreen-v1 is a valid counts profile with a rect probe without screenshots', () => {
  const p = JSON.parse(readFileSync(fileURLToPath(new URL('../profiles/offscreen-v1.json', import.meta.url)), 'utf8'));
  const { profile, kind } = parseProfile(p);
  assert.equal(kind, 'counts');
  assert.deepEqual(profile.cardProbe, { selector: '#platform', screenshots: false });
  assert.deepEqual(profile.segments.map((s) => s.name), ['top', 'near', 'back']);
  assert.ok(profile.segments.every((s) => s.anchor && s.frames > SETTLE));
});

test('host.mjs mounts packages/contracts/src when a driver file imports it (the container sees only /driver)', () => {
  const host = readFileSync(new URL('../src/host.mjs', import.meta.url), 'utf8');
  const server = readFileSync(new URL('../src/server.mjs', import.meta.url), 'utf8');
  if (server.includes('../../contracts/src/')) assert.ok(host.includes(':/contracts/src:ro'));
});
