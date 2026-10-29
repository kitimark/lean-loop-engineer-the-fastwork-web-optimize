import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GH_C, V, cellNums, decideJob, judge, numsBand, numsPred, overall, rowArm, ticks } from '../src/glint-hold.mjs';
import { decideDirs } from '../src/glint-cli.mjs';
import { accelHarnessSource } from '../src/accel-page.mjs';
import { GLINT_BASE_ARMS, GLINT_HOLD_ARMS, GLINT_OPTS, MODES, headerOf, isGlint, THREADED_OFF } from '../src/accel-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/glint-hold.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  for (const key of Object.keys(GH_C)) assert.equal(GH_C[key], k[key], key);
});

test('ticks lines replay the Lean golden (base and hold frames after a tick)', () => {
  assert.ok(of('ticks').length >= 7);
  for (const l of of('ticks')) {
    assert.equal(ticks(true, l.frames), l.hold, `${l.name} hold`);
    assert.equal(ticks(false, l.frames), l.base, `${l.name} base`);
  }
});

test('judge lines replay the Lean golden (edges of every branch)', () => {
  assert.ok(of('judge').length >= 12);
  for (const l of of('judge')) {
    assert.equal(numsPred(l.nums), l.pred, `${l.name} pred`);
    assert.equal(numsBand(l.nums), l.band, `${l.name} band`);
    assert.equal(judge(l.minF, l.nums), l.verdict, l.name);
  }
});

test('cell lines replay the Lean golden (nums from the frames, prediction, verdict)', () => {
  assert.ok(of('cell').length >= 11);
  for (const l of of('cell')) {
    const x = cellNums(l.cell);
    assert.deepEqual(x, l.nums, `${l.name} nums`);
    assert.equal(numsPred(x), l.pred, `${l.name} pred`);
    assert.equal(numsBand(x), l.band, `${l.name} band`);
    assert.equal(judge(l.minF, x), l.verdict, l.name);
  }
  assert.deepEqual(new Set(of('cell').map((l) => l.verdict)), new Set(Object.values(V)));
});

test('overall lines replay the Lean golden', () => {
  assert.ok(of('overall').length >= 6);
  for (const l of of('overall')) assert.equal(overall(l.verdicts), l.overall, l.name);
});

const asRow = (arm, a) => ({ arm, rs: { frames: a.flat().map(([r, l, e]) => ({ r, g: [l, e] })), wins: a.map((w) => w.length) } });
test('reportToCells glue: rows by arm name to the cell the golden judges', () => {
  const c = of('cell').find((l) => l.name === 'as predicted');
  const base = { rows: [asRow('rs-idle', c.cell.baseOn[0]), asRow('rs-idle-smil', c.cell.baseOff), asRow('rs-idle', c.cell.baseOn[1])] };
  const hold = { rows: [asRow('rs-idle', c.cell.holdOn)] };
  const d = decideJob(base, hold);
  assert.deepEqual(d.idle.nums, c.nums);
  assert.equal(d.idle.verdict, c.verdict);
  assert.equal(d.flip.verdict, V.unread);
  assert.deepEqual(rowArm(asRow('x', [[[1, 0, 0]], [[2, 5, 5], [3, 6, 6]]])).map((w) => w.length), [1, 2]);
});

test('glint modes: hold page adds platform.glint:hold-freeze, pref OFF header, 5 s idle, 16 flips, probe reads SMIL time', () => {
  assert.ok(MODES['glint-hold-thr-off'].startsWith(MODES['glint-base-thr-off']) && MODES['glint-hold-thr-off'].endsWith('platform.glint:hold-freeze'));
  assert.ok(isGlint('glint-base-thr-off') && isGlint('glint-hold-thr-off') && !isGlint('bisect-thr-off'));
  assert.ok(headerOf('glint-hold-thr-off', 'H').endsWith(THREADED_OFF));
  assert.deepEqual(GLINT_BASE_ARMS, ['rs-idle', 'rs-idle-smil', 'rs-idle', 'rs-flip', 'rs-flip-smil', 'rs-flip']);
  assert.deepEqual(GLINT_HOLD_ARMS, ['rs-idle', 'rs-flip']);
  const src = accelHarnessSource({ mode: 'timed', arms: GLINT_BASE_ARMS, ...GLINT_OPTS });
  assert.match(src, /"gh":true/);
  assert.match(src, /"rsIdleMs":5000/);
  assert.match(src, /"rsReps":16/);
  assert.match(src, /SVGAnimationElement\.prototype\.beginElement/);
  assert.doesNotMatch(accelHarnessSource({ mode: 'timed', arms: ['rs-idle'] }), /"gh":true/);
});

test('decideDirs reports missing result files instead of a verdict', () => {
  const r = decideDirs(['/nonexistent-glint-dir']);
  assert.match(r.lines[0], /result files missing/);
  assert.equal(r.overall.idle, 'inconclusive');
});
