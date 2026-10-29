import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CAUSE, CATS, EW, V, above, cellNums, causeOf, atFloor, decideJobE, judge, mechNext, mechOf, numsBand, overall, overallNames, catRate, jobLinesE } from '../src/end-wktr.mjs';
import { decideDirsE } from '../src/end-wktr-cli.mjs';
import { accelHarnessSource } from '../src/accel-page.mjs';
import { probeSource } from '../src/mid-page.mjs';
import { END_ARMS, END_OPTS, MODES, headerOf, isEnd, THREADED_OFF } from '../src/accel-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/end-wktr.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);
const mech = (m) => ({ r: m[0], written: m[1] === 1, elems: m[2] === 1, keys: [] });

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  for (const key of Object.keys(EW)) assert.equal(EW[key], k[key], key);
});

test('judge lines replay the Lean golden (edges of every branch)', () => {
  assert.ok(of('judge').length >= 12);
  for (const l of of('judge')) {
    assert.equal(numsBand(l.nums), l.band, `${l.name} band`);
    assert.equal(atFloor(l.nums), l.atFloor, `${l.name} at floor`);
    assert.equal(judge(l.minF, l.minS, l.nums), l.verdict, l.name);
  }
  assert.deepEqual(new Set(of('judge').map((l) => l.verdict)), new Set(Object.values(V)));
});

test('cell lines replay the Lean golden (nums from the frames, verdict)', () => {
  assert.ok(of('cell').length >= 7);
  for (const l of of('cell')) {
    const x = cellNums(l.cell);
    for (const k of Object.keys(l.nums)) assert.equal(x[k], l.nums[k], `${l.name} ${k}`);
    assert.equal(numsBand(x), l.band, `${l.name} band`);
    assert.equal(atFloor(x), l.atFloor, `${l.name} at floor`);
    assert.equal(judge(l.minF, l.minS, x), l.verdict, l.name);
  }
  assert.deepEqual(new Set(of('cell').map((l) => l.verdict)), new Set(Object.values(V)));
});

test('overall lines replay the Lean golden', () => {
  assert.ok(of('overall').length >= 7);
  for (const l of of('overall')) assert.equal(overall(l.verdicts), l.overall, l.name);
});

test('cause lines replay the Lean golden, every cause appears', () => {
  for (const l of of('cause')) assert.equal(causeOf(l), l.cause, l.name);
  assert.deepEqual(new Set(of('cause').map((l) => l.cause)), new Set(Object.values(CAUSE)));
  for (const l of [...of('overallCause'), ...of('overallMech')]) assert.equal(overallNames(l.causes ?? l.mechs), l.overall, l.name);
});

test('mech lines replay the Lean golden (rates per category, mechanism, next candidate)', () => {
  assert.ok(of('mech').length >= 7);
  for (const l of of('mech')) {
    const live = l.live.map(mech);
    const paused = l.paused.map(mech);
    assert.deepEqual(CATS.map((c) => catRate(c, live)), l.rates, `${l.name} rates`);
    assert.deepEqual(CATS.map((c) => catRate(c, paused)), l.pausedRates, `${l.name} paused rates`);
    assert.equal(mechOf(l.band, live, paused), l.mech, l.name);
    assert.equal(mechNext(l.band, live, paused), l.next, l.name);
  }
  assert.equal(new Set(of('mech').map((l) => l.mech)).size, 5);
  assert.ok(above(6, [], []).length === 0);
});

const rowOf = (arm, series, extra = {}) => ({ arm, rs: { frames: series.map((n) => ({ r: n, y: [0, 0, 0], k: [], z: [] })), kt: [], ...extra } });
const rep = (rows) => ({ rows });

test('glue: rows by arm name to the cells the golden judges, cause and mechanism from the instrumented arms', () => {
  const c = of('cell').find((l) => l.name === 'cuts partly').cell;
  const flat = (a) => a.flat();
  const base = rep([rowOf('rs-flip-nat', flat(c.base[0])), rowOf('rs-flip', flat(c.base[0])), rowOf('rs-flip-pall', c.floor), rowOf('rs-flip', flat(c.base[1])), rowOf('rs-flip-nat', flat(c.base[1]))]);
  const fp = rep([rowOf('rs-flip-nat', c.var)]);
  const comp = rep([rowOf('rs-flip-nat', c.var), rowOf('rs-flip', c.var), rowOf('rs-flip-pall', c.floor), rowOf('rs-flip-obsf', c.var), rowOf('rs-flip-pallf', c.floor)]);
  const d = decideJobE({ base, fp, comp, both: rep([rowOf('rs-flip-nat', c.base[0])]) });
  assert.equal(d.cells['fp/recalc'].verdict, V.cuts);
  assert.equal(d.cells['both/recalc'].verdict, V.noChange);
  assert.equal(d.cells['comp-iso/recalc'].verdict, V.cuts);
  assert.equal(d.cells['fp/layout'].verdict, V.noContrast);
  assert.equal(d.cause.name, CAUSE.running);
  assert.equal(d.mech.name, 'one category: empty');
  assert.match(jobLinesE('j', { base, fp, comp, both: rep([]) }).lines.join('\n'), /compositor flip mechanism/);
});

test('glue: frames without the layout counts are unread for those metrics, not zero', () => {
  const flat = Array.from({ length: 40 }, () => 1);
  const noY = (arm) => ({ arm, rs: { frames: flat.map((n) => ({ r: n, k: [], z: [] })), kt: [] } });
  const base = rep([noY('rs-flip-nat'), noY('rs-flip-pall'), noY('rs-flip-nat')]);
  const d = decideJobE({ base, fp: rep([noY('rs-flip-nat')]), comp: rep([]), both: rep([]) });
  assert.equal(d.cells['fp/layout'].verdict, V.unread);
  assert.equal(d.cause, null);
  assert.equal(d.mech, null);
});

test('end modes: the base page plus one flag set each, pref OFF header, the arms and the probe options', () => {
  const base = MODES['end-base-thr-off'];
  assert.equal(MODES['end-fp-thr-off'], `${base},platform:faded-pause`);
  assert.equal(MODES['end-comp-thr-off'], `${base},platform.glint:compositor`);
  assert.equal(MODES['end-both-thr-off'], `${base},platform:faded-pause,platform.glint:compositor`);
  for (const m of ['base', 'fp', 'comp', 'both']) {
    assert.ok(isEnd(`end-${m}-thr-off`));
    assert.ok(headerOf(`end-${m}-thr-off`, 'H').endsWith(THREADED_OFF));
    assert.ok(END_ARMS[m].every((a) => /^rs-flip(-(nat|pall|obsf|pallf))?$/.test(a)));
  }
  assert.ok(!isEnd('glint-comp-thr-off'));
  assert.deepEqual(END_ARMS.base.filter((a) => a === 'rs-flip-pall'), ['rs-flip-pall']);
  assert.equal(END_ARMS.base.filter((a) => a === 'rs-flip-nat').length, 2);
  assert.equal(END_ARMS.base.filter((a) => a === 'rs-flip').length, 2);
  assert.ok(END_ARMS.comp.includes('rs-flip-obsf') && END_ARMS.comp.includes('rs-flip-pallf'));
  const src = accelHarnessSource({ mode: 'timed', arms: END_ARMS.comp, ...END_OPTS });
  assert.match(src, /"lay":true/);
  assert.match(src, /"gk":true/);
  assert.match(probeSource({ mode: 'timed', arms: ['rs-flip-nat'], lay: true, gk: true }), /rs-\(warm\|idle\|flip\)/);
});

test('probe arms: nat pauses nothing, pall pauses the glint too and the SMIL, pallf records', () => {
  const src = probeSource({ mode: 'timed', arms: ['rs-flip-nat'] });
  assert.match(src, /vv === 'nat' \? \[\]/);
  assert.match(src, /keepGlint = P\.gk && vv !== 'pall' && vv !== 'pallf'/);
  assert.match(src, /vv === 'smil' \|\| vv === 'pall' \|\| vv === 'pallf'/);
  assert.match(src, /v === 'obsf' \|\| v === 'pallf'/);
});

test('decideDirsE reports missing result files instead of a verdict', () => {
  const r = decideDirsE(['/nonexistent-end-dir']);
  assert.match(r.lines[0], /result files missing/);
  assert.equal(r.overall.cause, 'inconclusive');
});
