import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BAND, MIN_ROUNDS, MIN_SEEN, WIN_RAF, rate } from '../src/sim-end-floor.mjs';
import { ARM_FLAGS, EDGES, edge, edgeOf, edgeParts, mergeRaws, overallEdge, overallTier, tableLines, tier, verdictLines } from '../src/sim-floor-attrib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/sim-floor-attrib.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  assert.deepEqual([BAND, WIN_RAF, MIN_SEEN, MIN_ROUNDS], [k.band, k.winRaf, k.minSeen, k.minRounds]);
});

test('arm flags equal the Lean flags', () => {
  assert.equal(of('arm').length, Object.keys(ARM_FLAGS).length);
  for (const l of of('arm')) assert.deepEqual(ARM_FLAGS[l.arm], l.flags, l.arm);
});

test('tier and the rate equal the Lean tier on every case', () => {
  assert.ok(of('tier').length >= 15);
  for (const l of of('tier')) {
    assert.equal(tier(l.win), l.verdict, l.name);
    assert.equal(rate(l.win), l.rate, l.name);
  }
});

test('the named edges and their delta parts equal the Lean edges', () => {
  assert.deepEqual(of('edge').map((l) => [l.arm, l.cmp, l.stages, l.parts]), EDGES.map((e) => [e.arm, e.cmp, e.stages, edgeParts(e)]));
});

test('edge verdicts equal the Lean edge on every case', () => {
  assert.ok(of('verdict').length >= 19);
  for (const l of of('verdict')) {
    assert.equal(edge(l.armBuild ?? 'b', l.cmpBuild ?? 'b', l.arm, l.cmp, l.armWin, l.cmpWin), l.verdict, l.name);
    if (!l.armBuild) assert.equal(edgeOf('b', { arm: l.arm, cmp: l.cmp }, l.armWin, l.cmpWin), l.verdict, l.name);
  }
});

test('overall lines equal the Lean overall', () => {
  assert.ok(of('overallEdge').length >= 5 && of('overallTier').length >= 4);
  for (const l of of('overallEdge')) assert.equal(overallEdge(l.verdicts), l.overall, l.name);
  for (const l of of('overallTier')) assert.equal(overallTier(l.tiers), l.overall, l.name);
});

test('report: the table and the verdicts are derived from the raw windows only', () => {
  const w = (n) => ({ raf: 360, seen: 360, recalcs: n, tally: { ScheduleStyleRecalculation: n === 720 ? 360 : 0, Layout: 360, Paint: 0 } });
  const arm = (n) => ({ end: w(n), back: w(n), paused: w(n) });
  const round = (b, v, bl, mb, c) => ({ arms: { base: arm(b), v2p: arm(v), minusT: arm(v), minusU: arm(v), blank: arm(bl), minusBoth: arm(mb), v2pCancelScroll: arm(c) } });
  const raw = (rounds) => ({ meta: { build: 'abc', runtime: 'rt', ua: 'ua' }, rounds });
  const merged = mergeRaws([raw([round(360, 720, 0, 360, 360)]), raw([round(360, 720, 0, 360, 360)]), raw([round(360, 720, 0, 360, 360)])]);
  assert.deepEqual(merged.rounds.map((r) => r.round), [1, 2, 3]);
  assert.deepEqual(merged.meta.builds, ['abc']);
  const v = verdictLines(merged);
  assert.ok(v.includes('v2pCancelScroll against v2p [scrollAnimations] paused overall: cut:scrollAnimations'));
  assert.ok(v.includes('blank against base [content] paused overall: cut:content'));
  assert.ok(v.includes('minusBoth against base [platform] paused overall: noEffect:platform'));
  assert.ok(v.includes('minusBoth against v2p [engine.scroll+hero.exit] paused overall: notAttributable'));
  assert.ok(v.includes('minusBoth against minusT [engine.scroll] end overall: cut:engine.scroll'));
  const t = tableLines(merged);
  assert.ok(t.some((l) => l.startsWith('paused v2p: rate per 100 [200, 200, 200]; recalcs/frame [2.00, 2.00, 2.00]; schedule/frame [1.00, 1.00, 1.00]')));
  assert.ok(t.some((l) => l.startsWith('paused blank') && l.endsWith('tier [zero, zero, zero] overall zero')));
  const two = mergeRaws([raw([round(360, 720, 0, 360, 360)])]);
  assert.ok(verdictLines(two).includes('blank against base [content] paused overall: inconclusive'));
});

test('builds that differ are not attributable', () => {
  const win = (n) => ({ raf: 360, seen: 360, recalcs: n });
  assert.equal(edge('b1', 'b2', 'v2pCancelScroll', 'v2p', win(360), win(720)), 'notAttributable');
});
