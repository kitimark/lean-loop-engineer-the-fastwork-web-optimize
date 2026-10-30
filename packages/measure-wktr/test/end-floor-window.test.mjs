import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MIN_REPS, PIN_N, PIN_REPS, armVerdict, classRate, factsText, overall, pinOf, repClass, repsOfRow, startupLen, tickOf, windowFacts } from '../src/end-floor-window.mjs';
import { probeSource } from '../src/mid-page.mjs';
import { accelHarnessSource } from '../src/accel-page.mjs';
import { FLOOR_OPTS } from '../src/end-floor.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/end-floor-window.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);
const ticks = (a) => a.map(tickOf);

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  assert.equal(PIN_N, k.pinN);
  assert.equal(PIN_REPS, k.pinReps);
  assert.equal(MIN_REPS, k.minReps);
});

test('pin lines', () => {
  assert.ok(of('pin').length >= 7);
  for (const l of of('pin')) assert.equal(pinOf(l.wins), l.pin, l.name);
});

test('rep lines: class and start-up length', () => {
  assert.ok(of('rep').length >= 11);
  for (const l of of('rep')) {
    const ts = ticks(l.ticks);
    assert.equal(repClass(ts), l.class, l.name);
    assert.equal(startupLen(ts), l.startup, l.name);
  }
});

test('arm lines: verdict and the three class rates', () => {
  assert.ok(of('arm').length >= 7);
  for (const l of of('arm')) {
    const reps = l.reps.map(ticks);
    assert.equal(armVerdict(reps), l.verdict, l.name);
    assert.equal(classRate('tick', reps), l.tickRate, l.name);
    assert.equal(classRate('quiet', reps), l.quietRate, l.name);
    assert.equal(classRate('idle', reps), l.idleRate, l.name);
  }
});

test('overall lines', () => {
  assert.ok(of('overall').length >= 5);
  for (const l of of('overall')) assert.equal(overall(l.verdicts), l.overall, l.name);
});

const frame = (r, m, q, d, a = 0, t = 0, h = 0) => ({ r, k: [], u: [m, q, d, a], t, h });
const rowOf = (reps) => ({ arm: 'rs-flip-nat', rs: { frames: reps.flat(), wins: reps.map((x) => x.length) } });

test('repsOfRow splits the frames by the window lengths and refuses a row without the probe', () => {
  const rep = [frame(2, 3, 0, 0), frame(0, 0, 2, 0), frame(0, 0, 0, 2)];
  const row = rowOf([rep, rep]);
  const reps = repsOfRow(row);
  assert.equal(reps.length, 2);
  assert.deepEqual(reps[0].map((t) => t.r), [2, 0, 0]);
  assert.equal(repClass(reps[0]), 'transient');
  assert.deepEqual(repsOfRow({ arm: 'x', rs: { frames: [{ r: 1, k: [] }], wins: [1] } }), []);
});

test('windowFacts carries pin, class, start-up range, first-frame phase and window length', () => {
  const rep = (n) => Array.from({ length: PIN_N }, (_, i) => (i < n ? frame(1, 2, 0, 0, 0, i * 16, 10 + i) : frame(0, 0, 2, 0, 2, i * 16, 50 + i)));
  const row = rowOf(Array.from({ length: PIN_REPS }, (_, i) => rep(1 + (i % 2))));
  const x = windowFacts(row);
  assert.equal(x.pin, 'pinned');
  assert.equal(x.verdict, 'transient');
  assert.deepEqual([Math.min(...x.startup), Math.max(...x.startup)], [1, 2]);
  assert.equal(x.ms.every((m) => m === (PIN_N - 1) * 16), true);
  assert.match(factsText(x), /pin pinned \(12 reps\), class transient,/);
  assert.match(factsText(x), /first-frame phase 10 to 10 per mille/);
});

test('an arm below the minimum rep count is unread', () => {
  const rep = [frame(1, 2, 0, 0), frame(0, 0, 2, 0), frame(0, 0, 0, 2)];
  assert.equal(windowFacts(rowOf([rep, rep])).verdict, 'unread');
});

test('the page probe stops at a fixed frame count and reads the tick hooks only with the tk option', () => {
  const src = probeSource({ mode: 'timed', rsWin: PIN_N, tk: true });
  assert.match(src, /frames\.length >= P\.rsWin/);
  assert.match(src, /timeToNextAnimationTick/);
  assert.match(src, /acceleratedAnimationsForElement/);
  const h = accelHarnessSource({ mode: 'timed', ...FLOOR_OPTS });
  assert.ok(h.includes(`"rsWin":${PIN_N}`) && h.includes('"tk":true'));
  assert.ok(accelHarnessSource({ mode: 'timed' }).includes('"rsWin":0'));
});
