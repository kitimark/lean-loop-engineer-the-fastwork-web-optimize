import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BAND, MIN_ROUNDS, MIN_SEEN, WIN_RAF, ARM_SETS as SETS, armsOf, buildSearches, endFloorJs, rowLines } from '../src/sim-end-floor.mjs';
import { armTrees, rotate } from '../src/sim-end-floor-run.mjs';
import { canonSearch } from '../../contracts/src/flag-key.mjs';
import { mergeRaws, overallTier } from '../src/sim-floor-attrib.mjs';
import {
  ARM_FLAGS, ARM_IDS, ARM_SETS, CENSUS_CAP, EDGES, FLAGS, PRED_TIER, active, candidateOf, complete, edgeOf, edgeParts, edgeRealParts, edgeTier, edgeTook, effectName, gate,
  held, heldGated, kindOf, overallEffect, overallPred, predEdge, predEdgeFor, predTierFor, scrollDriven, sourceRemains, stillTicks, sweepOnly, tableLines, verdictLines, viewDriven,
} from '../src/sim-end-cut.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/sim-end-cut.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);
const toC = (c) => ({ byKey: c.by, running: c.running, paused: c.paused, parked: c.parked, ut: c.ut, utParked: c.utParked, sweepHidden: c.sweepHidden });

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  assert.deepEqual([BAND, WIN_RAF, MIN_SEEN, MIN_ROUNDS, CENSUS_CAP], [k.band, k.winRaf, k.minSeen, k.minRounds, k.censusCap]);
});

test('arm sets, flags, active flags and the predicted tier equal the Lean arms', () => {
  assert.deepEqual(of('arm').map((l) => l.arm), ARM_IDS);
  for (const l of of('arm')) {
    assert.deepEqual(ARM_SETS[l.arm], l.sets, l.arm);
    assert.deepEqual(ARM_FLAGS[l.arm], l.flags, l.arm);
    assert.deepEqual(active(l.arm).map((f) => f.name), l.active, l.arm);
    assert.equal(PRED_TIER[l.arm], l.predTier, l.arm);
  }
});

test('edges: one named set differs, its real parts, and the prediction equal the Lean edges', () => {
  assert.deepEqual(of('edge').map((l) => [l.arm, l.cmp, l.stages, l.parts, l.realParts, l.predicted]),
    EDGES.map((e) => [e.arm, e.cmp, e.stages, edgeParts(e), edgeRealParts(e), predEdge(e)]));
  assert.ok(EDGES.every((e) => edgeParts(e).length === 1));
});

test('edge verdicts equal the Lean edge on every case', () => {
  assert.ok(of('verdict').length >= 16);
  for (const l of of('verdict')) {
    if (l.armBuild) assert.equal(edgeTier(l.armBuild, l.cmpBuild, ARM_SETS[l.arm], ARM_SETS[l.cmp], 'one', 'two'), l.verdict, l.name);
    else assert.equal(edgeOf('b', { arm: l.arm, cmp: l.cmp }, l.armWin, l.cmpWin), l.verdict, l.name);
  }
});

test('held, kindOf, census effects, still-ticking and the overall lines equal the Lean ones', () => {
  for (const l of of('held')) assert.equal(held(l.overall, l.predicted), l.verdict, l.name);
  assert.ok(of('heldGated').length >= 6);
  for (const l of of('heldGated')) assert.equal(heldGated(l.overall, l.predicted, l.took), l.verdict, l.name);
  assert.ok(of('edgeTook').length >= 7);
  for (const l of of('edgeTook')) assert.equal(edgeTook({ arm: l.arm, cmp: l.cmp }, l.rounds.map(([a, c]) => [a && toC(a), c && toC(c)])), l.took, l.name);
  for (const l of of('kindOf')) assert.equal(kindOf(l.name), l.verdict, l.name);
  assert.ok(of('census').length >= 11);
  for (const l of of('census')) {
    const c = toC(l.census);
    assert.equal(viewDriven(c), l.viewDriven, l.name);
    assert.equal(scrollDriven(c), l.scrollDriven, l.name);
    assert.equal(complete(c), l.complete, l.name);
    for (const id of ARM_IDS) assert.equal(effectName(id, c), l.effects[id], `${l.name} ${id}`);
    assert.deepEqual(stillTicks(c), l.stillTicks, l.name);
    assert.deepEqual(Object.fromEntries(FLAGS.map((f) => [f.name, f.took(c)])), l.flags, l.name);
    assert.equal(sourceRemains(c), l.sourceRemains, l.name);
    assert.equal(sweepOnly(c), l.sweepOnly, l.name);
    assert.equal(candidateOf(c), l.candidate, l.name);
  }
  assert.ok(of('gate').length >= 5);
  for (const l of of('gate')) assert.equal(gate(l.verdict, l.took), l.gated, l.name);
  assert.ok(of('predFor').length >= 6);
  for (const l of of('predFor')) assert.equal(predTierFor(l.arm, l.census && toC(l.census)), l.tier, l.name);
  assert.ok(of('predEdgeFor').length >= 7);
  for (const l of of('predEdgeFor')) {
    assert.equal(predEdgeFor({ arm: l.arm, cmp: l.cmp }, l.armCensus && toC(l.armCensus), l.cmpCensus && toC(l.cmpCensus)), l.predicted, l.name);
  }
  assert.ok(of('overallPred').length >= 4);
  for (const l of of('overallPred')) assert.equal(overallPred({ arm: l.arm, cmp: l.cmp }, l.rounds.map(([a, c]) => [a && toC(a), c && toC(c)])), l.predicted, l.name);
  for (const l of of('overallEffect')) assert.equal(overallEffect(l.effects), l.overall, l.name);
  for (const l of of('overallTier')) assert.equal(overallTier(l.tiers), l.overall, l.name);
  assert.equal(FLAGS.length, 7);
});

test('the cut arm set: v2p first, canonical searches of the flag sets, one build per search', () => {
  const arms = armsOf('cut');
  assert.deepEqual(arms.map((a) => a.id), ARM_IDS);
  assert.equal(arms[0], SETS.attrib.find((a) => a.id === 'v2p'));
  for (const a of arms) {
    assert.equal(canonSearch(a.search), a.search, a.id);
    assert.deepEqual(a.fw.split(',').sort(), ARM_FLAGS[a.id].map(([p, v]) => `${p}:${v}`).sort(), a.id);
  }
  assert.deepEqual(buildSearches('cut'), arms.map((a) => a.search));
  assert.deepEqual(Object.keys(armTrees('x', arms)), ARM_IDS);
  assert.equal(new Set([0, 1, 2].map((r) => rotate(arms, r)[0].id)).size, 3);
  assert.deepEqual(buildSearches('attrib'), buildSearches());
  assert.throws(() => armsOf('nope'));
});

test('the page census lists the paused infinite loops and the parked hero targets', () => {
  const src = endFloorJs();
  assert.doesNotThrow(() => new Function(`return ${src};`));
  assert.match(src, /getComputedTiming\(\)\.iterations === Infinity/);
  assert.match(src, /data-exit-parked/);
});

const w = (n) => ({ raf: 360, seen: 360, recalcs: n, tally: { ScheduleStyleRecalculation: 0, Layout: 360, Paint: 0 } });
const loops = [['document', 'accent-module_idle0_x', 'svg'], ['document', 'cue-module_scrollFloat_x', 'span'], ['document', 'sweep-module_sweepDoc_x', 'span'], ['document', 'sweep-module_sweepDoc_x', 'span']];
const sweepRun = [['p', 'running', false, false, true], ['p', 'running', false, false, true]];
const sweepRows = (hiddenState) => [...sweepRun, ['h', hiddenState, false, false, false], ['h', hiddenState, false, false, false]];
const sweepOnlyRunning = loops.slice(2);
/** The census of an arm in a state: `park` (parks on), `pause` (pauses on), `inView` (in-view sweep loops run), `missPark` (park flags without effect). */
const census = ({ park, pause, missPark = false }) => ({
  total: 40,
  by: { 'document:finished': 20, ...(park && !missPark ? {} : { 'view:finished': 13, 'scroll:finished': 1 }) },
  running: pause ? sweepOnlyRunning : [...loops, ...loops.slice(2)],
  paused: pause ? [...loops, ...loops.slice(2)] : [],
  parked: park && !missPark ? 1 : 0,
  ut: 1,
  utParked: park && !missPark ? 1 : 0,
});
const sweepOf = (pause) => sweepRows(pause ? 'paused' : 'running');
const arm = (n, c, pause) => ({ end: w(n), back: w(n), paused: w(360), anims: c, animsBack: c, animsPaused: c, sweepEnd: sweepOf(pause), sweepBack: sweepOf(pause) });
const roundOf = ({ bothRate, missPark = false }) => ({ arms: {
  v2p: arm(720, census({ park: false, pause: false }), false), parks: arm(720, census({ park: true, pause: false, missPark }), false),
  pauses: arm(720, census({ park: false, pause: true }), true), both: arm(bothRate, census({ park: true, pause: true, missPark }), true) } });
const rawOf = (o) => ({ meta: { build: 'abc', runtime: 'rt', ua: 'ua', armSet: 'cut' }, rounds: [roundOf(o)] });
const three = (o) => mergeRaws([rawOf(o), rawOf(o), rawOf(o)]);

test('report: the in-view sweep loops are a source, so both is predicted at tier two and a cut to 100 reads missed', () => {
  const merged = three({ bothRate: 360 });
  assert.equal(merged.meta.armSet, 'cut');
  const v = verdictLines(merged);
  const has = (l) => assert.ok(v.includes(l), l);
  has('parks against v2p [parks] end overall: noEffect:parks (rate reading noEffect:parks); predicted noEffect:parks; held');
  has('pauses against v2p [pauses] back overall: noEffect:pauses (rate reading noEffect:pauses); predicted noEffect:pauses; held');
  has('both against parks [pauses] end overall: cut:pauses (rate reading cut:pauses); predicted noEffect:pauses; missed');
  has('both against pauses [parks] back overall: cut:parks (rate reading cut:parks); predicted noEffect:parks; missed');
  has('tier both end: [one, one, one] overall one; predicted two; missed');
  has('tier both paused: [one, one, one] overall one (reference)');
  has('tier v2p end: [two, two, two] overall two; predicted two; held');
  has('effect both end overall: took');
  has('effect v2p end overall: took');
  has('answer both end: tiers [one, one, one] overall one; reaches 100 per 100: yes');
  has('answer parks back: tiers [two, two, two] overall two; reaches 100 per 100: no');
  assert.ok(v.some((l) => l.startsWith('sources both end round 1: platform sweep running 2; sweep loops running 2, hidden 0; owners sweep-module_sweepDoc_x on span x2; candidate platform.sweep:layer-sweep')));
  const same = verdictLines(three({ bothRate: 720 }));
  assert.ok(same.includes('both against parks [pauses] end overall: noEffect:pauses (rate reading noEffect:pauses); predicted noEffect:pauses; held'));
  assert.ok(same.includes('tier both end: [two, two, two] overall two; predicted two; held'));
  assert.ok(same.includes('answer both end: tiers [two, two, two] overall two; reaches 100 per 100: no'));
});

test('report: a flag that did not take reads untested, never noEffect', () => {
  const un = verdictLines(three({ bothRate: 720, missPark: true }));
  assert.ok(un.includes('parks against v2p [parks] end overall: untested (rate reading noEffect:parks); predicted noEffect:parks; untested'));
  assert.ok(un.includes('both against parks [pauses] back overall: untested (rate reading noEffect:pauses); predicted noEffect:pauses; untested'));
  assert.ok(un.includes('tier both end: [two, two, two] overall two; predicted two; untested'));
  assert.ok(un.includes('tier v2p end: [two, two, two] overall two; predicted two; held'));
  assert.ok(un.includes('pauses against v2p [pauses] end overall: noEffect:pauses (rate reading noEffect:pauses); predicted noEffect:pauses; held'));
  assert.ok(un.some((l) => l.startsWith('effect parks end round 1: missing:hero.exit:threaded-park,engine.scroll:unthrottle-park;')));
});

test('report: a hidden sweep loop that still runs, or a missing sweep read, leaves the sweep pause untested', () => {
  const hiddenRuns = { ...rawOf({ bothRate: 720 }) };
  hiddenRuns.rounds[0].arms.pauses.sweepEnd = sweepRows('running');
  const v = verdictLines(mergeRaws([hiddenRuns, rawOf({ bothRate: 720 }), rawOf({ bothRate: 720 })]));
  assert.ok(v.some((l) => l.startsWith('effect pauses end round 1: missing:platform.sweep:offscreen-pause;')));
  assert.ok(v.includes('pauses against v2p [pauses] end overall: untested (rate reading noEffect:pauses); predicted noEffect:pauses; untested'));
  const noRead = rawOf({ bothRate: 720 });
  delete noRead.rounds[0].arms.both.sweepEnd;
  const v2 = verdictLines(mergeRaws([noRead, rawOf({ bothRate: 720 }), rawOf({ bothRate: 720 })]));
  assert.ok(v2.some((l) => l.startsWith('effect both end round 1: missing:platform.sweep:offscreen-pause;')));
});

test('report: nothing remains in both, so the prediction is tier one', () => {
  const clear = rawOf({ bothRate: 360 });
  Object.assign(clear.rounds[0].arms.both, { anims: { ...census({ park: true, pause: true }), running: [] }, animsBack: { ...census({ park: true, pause: true }), running: [] } });
  const v = verdictLines(mergeRaws([clear, clear, clear]));
  assert.ok(v.includes('tier both end: [one, one, one] overall one; predicted one; held'));
  assert.ok(v.includes('both against parks [pauses] end overall: cut:pauses (rate reading cut:pauses); predicted cut:pauses; held'));
});

test('report: the table and the rows', () => {
  const merged = three({ bothRate: 360 });
  const t = tableLines(merged);
  assert.equal(t.length, 2 * 4 + 2);
  assert.ok(t.every((l) => !l.startsWith('paused parks') && !l.startsWith('paused pauses')));
  const rows = rowLines(merged, armsOf('cut'));
  assert.equal(rows.length, 3 * (3 * 4 + 3 * 4 + 4));
  assert.ok(rows.some((l) => l.includes('pausedLoops') && l.includes('unthrottle parked')));
});
