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
  ARM_FLAGS, ARM_IDS, ARM_SETS, CENSUS_CAP, EDGES, FLAGS, PRED_TIER, active, complete, edgeOf, edgeParts, edgeRealParts, edgeTier, effectName, held, kindOf,
  overallEffect, predEdge, scrollDriven, stillTicks, tableLines, verdictLines, viewDriven,
} from '../src/sim-end-cut.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/sim-end-cut.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);
const toC = (c) => ({ byKey: c.by, running: c.running, paused: c.paused });

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
  for (const l of of('kindOf')) assert.equal(kindOf(l.name), l.verdict, l.name);
  assert.ok(of('census').length >= 11);
  for (const l of of('census')) {
    const c = toC(l.census);
    assert.equal(viewDriven(c), l.viewDriven, l.name);
    assert.equal(scrollDriven(c), l.scrollDriven, l.name);
    assert.equal(complete(c), l.complete, l.name);
    for (const id of ARM_IDS) assert.equal(effectName(id, c), l.effects[id], `${l.name} ${id}`);
    assert.deepEqual(stillTicks(c), l.stillTicks, l.name);
  }
  for (const l of of('overallEffect')) assert.equal(overallEffect(l.effects), l.overall, l.name);
  for (const l of of('overallTier')) assert.equal(overallTier(l.tiers), l.overall, l.name);
  assert.equal(FLAGS.length, 5);
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

test('report: rows follow the arm set of the run, the table and the verdicts come from the raw windows only', () => {
  const w = (n) => ({ raf: 360, seen: 360, recalcs: n, tally: { ScheduleStyleRecalculation: 0, Layout: 360, Paint: 0 } });
  const loops = [['document', 'accent-module_idle0_x', 'svg'], ['document', 'cue-module_scrollFloat_x', 'span'], ['document', 'sweep-module_sweepDoc_x', 'span']];
  const census = (park, pause) => ({
    total: 40,
    by: { 'document:finished': 20, ...(park ? {} : { 'view:finished': 13, 'scroll:finished': 1 }) },
    running: pause ? [] : loops,
    paused: pause ? loops : [],
  });
  const arm = (n, park, pause) => ({ end: w(n), back: w(n), paused: w(360), anims: census(park, pause), animsBack: census(park, pause), animsPaused: census(park, pause) });
  const round = (bothRate) => ({ arms: { v2p: arm(720, false, false), parks: arm(720, true, false), pauses: arm(720, false, true), both: arm(bothRate, true, true) } });
  const raw = (bothRate) => ({ meta: { build: 'abc', runtime: 'rt', ua: 'ua', armSet: 'cut' }, rounds: [round(bothRate)] });
  const merged = mergeRaws([raw(360), raw(360), raw(360)]);
  assert.equal(merged.meta.armSet, 'cut');
  const v = verdictLines(merged);
  const has = (l) => assert.ok(v.includes(l), l);
  has('parks against v2p [parks] end overall: noEffect:parks; predicted noEffect:parks; held');
  has('pauses against v2p [pauses] back overall: noEffect:pauses; predicted noEffect:pauses; held');
  has('both against parks [pauses] end overall: cut:pauses; predicted cut:pauses; held');
  has('both against pauses [parks] back overall: cut:parks; predicted cut:parks; held');
  has('tier both end: [one, one, one] overall one; predicted one; held');
  has('tier both paused: [one, one, one] overall one (reference)');
  has('effect both end overall: took');
  has('effect parks back overall: took');
  has('effect v2p end overall: inconclusive');
  const missed = verdictLines(mergeRaws([raw(720), raw(720), raw(720)]));
  assert.ok(missed.includes('both against parks [pauses] end overall: noEffect:pauses; predicted cut:pauses; missed'));
  assert.ok(missed.includes('effect both end round 1: took; still ticks: nothing; complete true'));
  assert.ok(missed.includes('effect v2p end round 1: none; still ticks: view-driven 13, scroll-driven 1, accent idle running 1, cue float running 1, platform sweep running 1; complete true'));
  const t = tableLines(merged);
  assert.equal(t.length, 2 * 4 + 2);
  assert.ok(t.every((l) => !l.startsWith('paused parks') && !l.startsWith('paused pauses')));
  const rows = rowLines(merged, armsOf('cut'));
  assert.equal(rows.length, 3 * (3 * 4 + 3 * 4));
  assert.ok(rows.some((l) => l.includes('pausedLoops')));
});
