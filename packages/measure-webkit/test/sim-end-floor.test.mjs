import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ARMS, BAND, BUILD_SEARCHES, MIN_RENDERED, MIN_ROUNDS, STAGES, WIN_RAF, cmp, endFloorJs, flagV, overallFlag, overallPair, pair, rate, rowLines, verdictLines, windowOf,
} from '../src/sim-end-floor.mjs';
import { armTrees, rotate } from '../src/sim-end-floor-run.mjs';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/sim-end-floor.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  assert.equal(BAND, k.band);
  assert.equal(WIN_RAF, k.winRaf);
  assert.equal(MIN_RENDERED, k.minRendered);
  assert.equal(MIN_ROUNDS, k.minRounds);
});

test('flag verdicts and the full-arm rate equal the Lean flagV on every case', () => {
  assert.ok(of('flag').length >= 14);
  for (const l of of('flag')) {
    assert.equal(flagV(l.full, l.minusF, l.base), l.verdict, l.name);
    assert.equal(rate(l.full), l.rate, l.name);
  }
});

test('pair and cmp equal the Lean pair and cmp', () => {
  assert.ok(of('pair').length >= 12 && of('cmp').length >= 8);
  for (const l of of('pair')) assert.equal(pair(l.threaded, l.unthrottle), l.verdict, l.name);
  for (const l of of('cmp')) assert.equal(cmp(l.pair), l.verdict, l.pair);
});

test('overall lines equal the Lean overall', () => {
  assert.ok(of('overallFlag').length >= 4 && of('overallPair').length >= 4);
  for (const l of of('overallFlag')) assert.equal(overallFlag(l.verdicts), l.overall, l.name);
  for (const l of of('overallPair')) assert.equal(overallPair(l.verdicts), l.overall, l.name);
});

test('arms: the base, the v2-proved preset and one removal each, canonical searches', () => {
  assert.deepEqual(ARMS.map((a) => a.id), ['base', 'v2p', 'minusT', 'minusU']);
  const preset = JSON.parse(readFileSync(join(here, '../../contracts/golden/preset/v2-proved.json'), 'utf8')).fw;
  const parts = (fw) => new Set(fw === '' ? [] : fw.split(','));
  const v2p = parts(ARMS[1].fw);
  assert.deepEqual([...v2p].sort(), Object.entries(preset).map(([k, v]) => `${k}:${v}`).sort());
  assert.deepEqual([...parts(ARMS[2].fw)], [...v2p].filter((p) => p !== 'hero.exit:threaded'));
  assert.deepEqual([...parts(ARMS[3].fw)], [...v2p].filter((p) => p !== 'engine.scroll:unthrottle'));
  for (const a of ARMS) assert.equal(canonSearch(a.search), a.search, a.id);
  assert.equal(ARMS[0].search, '');
  assert.deepEqual(BUILD_SEARCHES, ARMS.slice(1).map((a) => a.search));
  assert.deepEqual(Object.keys(armTrees('x')), ARMS.map((a) => a.id));
});

test('rotate: every arm is first once over four rounds', () => {
  const firsts = [0, 1, 2, 3].map((r) => rotate(ARMS, r)[0].id);
  assert.deepEqual([...firsts].sort(), ['base', 'minusT', 'minusU', 'v2p']);
});

test('windowOf counts only rows between the two marks of the stage', () => {
  const rows = [
    ['RecalculateStyles', 0.5, 0.51, null],
    ['TimeStamp', 1, null, 'ef:a-end'],
    ['RecalculateStyles', 1.1, 1.11, null], ['RenderingFrame', 1.1, 1.12, null],
    ['RecalculateStyles', 1.2, 1.21, null], ['RenderingFrame', 1.2, 1.22, null], ['Layout', 1.2, 1.21, null],
    ['TimeStamp', 2, null, 'ef:b-end'],
    ['RecalculateStyles', 2.1, 2.11, null],
  ];
  const w = windowOf(rows, 'end', 360);
  assert.equal(w.recalcs, 2);
  assert.equal(w.rendered, 2);
  assert.equal(w.tally.Layout, 1);
  assert.equal(w.raf, 360);
  assert.equal(w.marks, true);
  assert.equal(w.spanMs, 1000);
  const none = windowOf(rows, 'back', 360);
  assert.equal(none.marks, false);
  assert.equal(none.recalcs, 0);
});

test('endFloorJs is a well-formed async expression that reads both stages', () => {
  const src = endFloorJs();
  assert.doesNotThrow(() => new Function(`return ${src};`));
  for (const s of STAGES) assert.match(src, new RegExp(`win\\('${s}'\\)`));
  assert.match(src, new RegExp(`n < ${WIN_RAF}`));
});

test('report lines: rows and verdicts are derived from the raw windows only', () => {
  const w = (rendered, recalcs, raf = WIN_RAF) => ({ raf, rendered, recalcs, marks: true, spanMs: 6000, cls: 'x', y: 7, tally: { Layout: 0, Paint: 0, Composite: 0, ScheduleStyleRecalculation: 0, FireAnimationFrame: raf } });
  const arms = (b, v, t, u) => Object.fromEntries([['base', b], ['v2p', v], ['minusT', t], ['minusU', u]].map(([id, n]) => [id, { end: w(360, n), back: w(360, n), anims: null }]));
  const raw = { meta: { runtime: 'rt', ua: 'ua' }, rounds: [{ round: 1, arms: arms(0, 360, 360, 360) }, { round: 2, arms: arms(0, 360, 360, 360) }] };
  const verdict = verdictLines(raw);
  assert.ok(verdict.some((l) => l === 'end overall pair: sharedOrOther'));
  assert.ok(verdict.some((l) => l === 'end overall vs WKTR: same'));
  assert.ok(verdict.some((l) => l === 'back overall hero.exit:threaded: none'));
  assert.equal(rowLines(raw).length, 2 * STAGES.length * ARMS.length);
  const cut = { rounds: [{ round: 1, arms: arms(0, 360, 0, 360) }, { round: 2, arms: arms(0, 360, 0, 360) }] };
  const v2 = verdictLines(cut);
  assert.ok(v2.some((l) => l === 'end overall pair: threaded'));
  assert.ok(v2.some((l) => l === 'end overall vs WKTR: different'));
  const short = { rounds: [{ round: 1, arms: arms(0, 360, 0, 360) }] };
  assert.ok(verdictLines(short).some((l) => l === 'end overall pair: inconclusive'));
});
