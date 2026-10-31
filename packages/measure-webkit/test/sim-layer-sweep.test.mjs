import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BAND, WIN_RAF, ARM_SETS as SETS, LAYER_LOOPS_JS, PIN_JS, armsOf, buildSearches, endFloorJs, rowLines, roundName } from '../src/sim-end-floor.mjs';
import { armTrees } from '../src/sim-end-floor-run.mjs';
import { canonSearch } from '../../contracts/src/flag-key.mjs';
import { mergeRaws } from '../src/sim-floor-attrib.mjs';
import { complete, overallEffect, stillTicks } from '../src/sim-end-cut.mjs';
import {
  LARM_FLAGS, LARM_IDS, LAYER_PREFIX, SWEEP_ITER_MS, SWEEP_LOOP_COUNT, WINDOW_MS_MAX, edgeOfL, edgeTookL, effectNameL, effectDemand, effectTicks, foreignRunning, iterRate, larmActive,
  layerEvidence, layerOnly, layerReadOf, layerRunning, layerSweepTook, overallPredL, predEdgeL, predTierL, reasonOf, readEffect, shareFull, sweepDocLoops, tableLines, verdictLines,
} from '../src/sim-layer-sweep.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/sim-layer-sweep.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);
const toC = (c) => ({ byKey: c.by, running: c.running, paused: c.paused, parked: c.parked, ut: c.ut, utParked: c.utParked, sweepHidden: c.sweepHidden });
const stageC = ([a, r, c]) => [a && toC(a), r, c && toC(c)];

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  assert.deepEqual([BAND, WIN_RAF, LAYER_PREFIX, SWEEP_ITER_MS, SWEEP_LOOP_COUNT, WINDOW_MS_MAX], [k.band, k.winRaf, k.layerPrefix, k.sweepIterMs, k.sweepLoopCount, k.windowMsMax]);
  assert.ok(iterRate(SWEEP_LOOP_COUNT, WINDOW_MS_MAX, SWEEP_ITER_MS, WIN_RAF) <= k.iterRateMax);
});

test('arms: flags, active flags and the one part that differs equal the Lean arms', () => {
  assert.deepEqual(of('arm').map((l) => l.arm), LARM_IDS);
  for (const l of of('arm')) {
    assert.deepEqual(LARM_FLAGS[l.arm], l.flags, l.arm);
    assert.deepEqual(larmActive(l.arm).map((f) => f.name), l.active, l.arm);
  }
  const parts = (id) => new Set(LARM_FLAGS[id].map(([p, v]) => `${p}:${v}`));
  const diff = [...parts('bothL')].filter((x) => !parts('both').has(x)).map((x) => x.split(':')[0]);
  assert.deepEqual(diff, of('delta')[0].parts);
});

test('the tick demand of an effect, a layer read and the inspector reason equal the Lean ones', () => {
  assert.ok(of('effect').length >= 8);
  for (const l of of('effect')) {
    assert.equal(effectTicks(l.effect), l.ticks, l.name);
    assert.equal(shareFull(l.effect.props), l.shareFull, l.name);
    assert.equal(effectDemand(l.effect, true), l.demandListener, l.name);
    assert.equal(effectDemand(l.effect, false), l.demandNone, l.name);
  }
  assert.ok(of('read').length >= 6);
  for (const l of of('read')) {
    assert.equal(layerEvidence(l.read), l.evidence, l.name);
    assert.equal(effectTicks(readEffect(l.read, null)), l.ticksCore, l.name);
    assert.equal(effectTicks(readEffect(l.read, false)), l.ticksRep, l.name);
  }
  assert.ok(of('reason').length >= 4);
  for (const l of of('reason')) assert.equal(reasonOf(l.layers, l.animation), l.reason, l.name);
});

test('layer census, the took-check and the effect names equal the Lean ones', () => {
  assert.ok(of('census').length >= 8);
  for (const l of of('census')) {
    const c = toC(l.census);
    assert.equal(layerRunning(c), l.layerRunning, l.name);
    assert.equal(foreignRunning(c), l.foreignRunning, l.name);
    assert.equal(sweepDocLoops(c), l.sweepDocLoops, l.name);
    assert.equal(layerOnly(c), l.layerOnly, l.name);
    assert.equal(layerSweepTook(c), l.layerSweepTook, l.name);
    assert.equal(complete(c), l.complete, l.name);
    assert.equal(stillTicks(c).length > 0, l.sourceRemains, l.name);
    for (const id of LARM_IDS) assert.equal(effectNameL(id, c), l.effects[id], `${l.name} ${id}`);
  }
  for (const l of of('overallEffect')) assert.equal(overallEffect(l.effects), l.overall, l.name);
});

test('verdicts and predictions equal the Lean ones', () => {
  assert.ok(of('verdict').length >= 6);
  for (const l of of('verdict')) assert.equal(edgeOfL('b', l.armWin, l.cmpWin), l.verdict, l.name);
  assert.ok(of('predTierL').length >= 9);
  for (const l of of('predTierL')) assert.equal(predTierL(l.read, l.rep, toC(l.census)), l.tier, l.name);
  assert.ok(of('predEdgeL').length >= 5);
  for (const l of of('predEdgeL')) {
    assert.equal(predEdgeL(l.rep, stageC(l.stage)), l.predicted, l.name);
  }
  assert.ok(of('edgeTookL').length >= 4);
  for (const l of of('edgeTookL')) assert.equal(edgeTookL(l.stages.map(stageC)), l.took, l.name);
  assert.ok(of('overallPredL').length >= 3);
  for (const l of of('overallPredL')) assert.equal(overallPredL(l.rep, l.stages.map(stageC)), l.predicted, l.name);
});

test('the layer arm set: both first, canonical searches, one build per search', () => {
  const arms = armsOf('layer');
  assert.deepEqual(arms.map((a) => a.id), LARM_IDS);
  assert.equal(arms[0], SETS.cut.find((a) => a.id === 'both'));
  for (const a of arms) {
    assert.equal(canonSearch(a.search), a.search, a.id);
    assert.deepEqual(a.fw.split(',').sort(), LARM_FLAGS[a.id].map(([p, v]) => `${p}:${v}`).sort(), a.id);
  }
  assert.equal(arms[1].layer, true);
  assert.deepEqual(buildSearches('layer'), arms.map((a) => a.search));
  assert.deepEqual(Object.keys(armTrees('x', arms)), LARM_IDS);
});

test('the page script pins the end windows and lists the layer loops; the pin loop reaches the end', () => {
  const src = endFloorJs({ layer: true });
  assert.doesNotThrow(() => new Function(`return ${src};`));
  assert.match(src, /layerLoops\(\)/);
  assert.match(src, /pin\(\)/);
  assert.doesNotMatch(endFloorJs(), /layerLoops\(\)/);
  assert.match(LAYER_LOOPS_JS, /sweepLayerX/);
  assert.match(PIN_JS, /scrollHeight - innerHeight/);
  assert.match(src, /maxY/);
});

test('merged separate jobs are named job N, a single raw keeps round N', () => {
  const raw = (n) => ({ meta: { build: 'abc', armSet: 'layer' }, rounds: [{ round: 1, arms: {} }], n });
  const m = mergeRaws([raw(1), raw(2), raw(3)]);
  assert.deepEqual(m.rounds.map(roundName), ['job 1', 'job 2', 'job 3']);
  assert.equal(roundName({ round: 2 }), 'round 2');
});

const w = (n, y = 5267) => ({ raf: 360, seen: 360, recalcs: n, tally: { ScheduleStyleRecalculation: n, Layout: 0, Paint: 0 }, y, maxY: 5267 });
const accent = [['document', 'accent-module_idle0_x', 'svg'], ['document', 'cue-module_scrollFloat_x', 'span']];
const layerN = (k) => Array.from({ length: k }, () => ['document', `${LAYER_PREFIX}_h`, 'i']);
const docN = (k) => Array.from({ length: k }, () => ['document', 'sweep-module_sweepDoc_x', 'span']);
const base = { total: 30, by: { 'document:finished': 20 }, parked: 1, ut: 1, utParked: 1 };
const censusBoth = { ...base, running: docN(2), paused: [...accent, ...docN(3)] };
const censusLayer = { ...base, running: layerN(5), paused: accent };
const docRows = [['p', 'running', false, false, true], ['p', 'running', false, false, true], ['h', 'paused', false, false, false]];
const layerRows = [...Array.from({ length: 5 }, () => ['d', 'running', false, false, true, ['transform']])];
const probe = { nodes: 5, layers: 5, animation: 5, willChange: 5 };
const armBoth = (n) => ({ end: w(n), back: w(n), paused: w(360), anims: censusBoth, animsBack: censusBoth, animsPaused: censusBoth, sweepEnd: docRows, sweepBack: docRows, pinEnd: 0, pinBack: 0 });
const armLayer = (n, extra = {}) => ({ end: w(n), back: w(n), paused: w(360), anims: censusLayer, animsBack: censusLayer, animsPaused: censusLayer, sweepEnd: [], sweepBack: [], layerEnd: layerRows, layerBack: layerRows, layerProbe: probe, pinEnd: 0, pinBack: 0, ...extra });
const rawOf = (nL, nB, extra) => ({ meta: { build: 'abc', runtime: 'rt', ua: 'ua', armSet: 'layer' }, rounds: [{ round: 1, arms: { both: armBoth(nB), bothL: armLayer(nL, extra) } }] });
const three = (nL, nB, extra) => mergeRaws([rawOf(nL, nB, extra), rawOf(nL, nB, extra), rawOf(nL, nB, extra)]);

test('layer read from raw rows and the inspector probe', () => {
  assert.deepEqual(layerReadOf(armLayer(360), 'end'), { loops: 5, props: ['transform'], reason: true });
  assert.deepEqual(layerReadOf(armLayer(360, { layerProbe: { error: 'no' } }), 'back'), { loops: 5, props: ['transform'], reason: null });
  assert.deepEqual(layerReadOf(armLayer(360, { layerProbe: { nodes: 5, layers: 5, animation: 0, willChange: 5 } }), 'end').reason, false);
  assert.equal(layerReadOf(armBoth(360), 'end'), null);
});

test('report: bothL at tier one against both at tier two is a cut of platform.sweep, held', () => {
  const v = verdictLines(three(360, 720));
  const has = (l) => assert.ok(v.includes(l), l);
  has('bothL against both [platform.sweep] end overall: cut:platform.sweep (rate reading cut:platform.sweep); predicted cut:platform.sweep; held');
  has('bothL against both [platform.sweep] back overall: cut:platform.sweep (rate reading cut:platform.sweep); predicted cut:platform.sweep; held');
  has('tier bothL end: [one, one, one] overall one; predicted one; held');
  has('tier both end: [two, two, two] overall two; predicted two; held');
  has('effect bothL end overall: took');
  has('effect both back overall: took');
  has('answer bothL end: tiers [one, one, one] overall one; reaches 100 per 100: yes');
  has('answer both end: tiers [two, two, two] overall two; reaches 100 per 100: no');
  has('pinned windows: 6 of 6 end windows read at the end of the page (y equals maxY)');
  assert.ok(v.some((l) => l.startsWith('bothL against both [platform.sweep] end job 1:')));
  assert.ok(v.some((l) => l.startsWith('layer census end job 1: 5 loops, 5 running, 5 in view, properties ["transform"]') && l.includes('evidence inspector') && l.includes('window y 5267 of 5267')));
  assert.ok(v.some((l) => l.startsWith('effect bothL end job 1: took; layer loops running 5, sweepDoc loops 0, other running 0')));
  assert.ok(v.every((l) => !l.includes('round 1')));
});

test('report: a layer that still ticks (rate stays two) misses the prediction; a missing layer census leaves it untested', () => {
  const missed = verdictLines(three(720, 720));
  assert.ok(missed.includes('bothL against both [platform.sweep] end overall: noEffect:platform.sweep (rate reading noEffect:platform.sweep); predicted cut:platform.sweep; missed'));
  assert.ok(missed.includes('tier bothL end: [two, two, two] overall two; predicted one; missed'));
  const noLayer = rawOf(360, 720);
  noLayer.rounds[0].arms.bothL.anims = censusBoth;
  const v = verdictLines(mergeRaws([noLayer, rawOf(360, 720), rawOf(360, 720)]));
  assert.ok(v.some((l) => l.startsWith('effect bothL end job 1: missing:platform.sweep:layer-sweep;')));
  assert.ok(v.includes('bothL against both [platform.sweep] end overall: untested (rate reading cut:platform.sweep); predicted mixed; untested'));
});

test('report: the inspector contradicting the animation reason predicts tier two', () => {
  const contra = three(720, 720, { layerProbe: { nodes: 5, layers: 5, animation: 0, willChange: 5 } });
  const v = verdictLines(contra);
  assert.ok(v.includes('tier bothL end: [two, two, two] overall two; predicted two; held'));
  assert.ok(v.some((l) => l.includes('evidence contradicted')));
});

test('report: a window that stopped short of the end is counted as not pinned', () => {
  const r = rawOf(360, 720);
  r.rounds[0].arms.both.end = w(720, 5231);
  const v = verdictLines(mergeRaws([r, rawOf(360, 720), rawOf(360, 720)]));
  assert.ok(v.includes('pinned windows: 5 of 6 end windows read at the end of the page (y equals maxY)'));
});

test('report: the table and the rows', () => {
  const merged = three(360, 720);
  const t = tableLines(merged);
  assert.equal(t.length, 3 * 2);
  assert.ok(t[0].startsWith('end both: rate per 100 [200, 200, 200]'));
  assert.ok(t[1].includes('end bothL: rate per 100 [100, 100, 100]'));
  const rows = rowLines(merged, armsOf('layer'));
  assert.ok(rows.some((l) => l.startsWith('job 1 layer loops bothL: end 5 running of 5')));
  assert.ok(rows.some((l) => l.startsWith('job 1 pin bothL: end 0')));
  assert.ok(rows.some((l) => l.includes('y 5267 of 5267')));
});
