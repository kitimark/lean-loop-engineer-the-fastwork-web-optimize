import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CAP, blinks, captureOf, closeCause, jointSession, jointText, longCount, measured, flagOf, reversals, summaryOf, topZone, medianOf, CAUSE_TEXT } from '../src/device-feel-cap.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/feel.jsonl', import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const of = (k) => GOLDEN.filter((l) => l.kind === k);

test('capture reducer follows the Lean golden', () => {
  assert.ok(of('capture').length >= 9);
  for (const c of of('capture')) assert.deepEqual(captureOf(c), c.result, c.name);
});

test('blink detector follows the Lean golden', () => {
  assert.ok(of('blinks').length >= 10);
  for (const b of of('blinks')) assert.equal(blinks(b.series), b.count, JSON.stringify(b.series));
});

test('close cause follows the Lean golden and has a text for every cause', () => {
  for (const c of of('closeCause')) {
    assert.equal(closeCause(c.selfClosed, c.usb), c.cause, c.name);
    assert.ok(CAUSE_TEXT[c.cause]);
  }
  assert.match(CAUSE_TEXT.phoneNotOnUsb, /not on USB/);
});

test('joint rating and capture follows the Lean golden', () => {
  const lines = of('joint');
  assert.ok(lines.length >= 5);
  for (const j of lines) {
    const got = jointSession(j.seed, [...j.ratings, ...j.look], [...j.captures, ...j.lookCaptures]);
    assert.deepEqual(got.same.map(({ id, ...r }) => r), j.same, `seed ${j.seed}`);
    assert.deepEqual(got.look.map(({ id, ...r }) => r), j.lookJoint, `seed ${j.seed} look`);
  }
  assert.ok(lines.some((j) => j.same.some((r) => r.flag === 'felt worse, measured lighter')));
});

test('small reducers: long frames count only while moving; margin and flag rules', () => {
  assert.equal(longCount(CAP.long17Cs, [0, 1667, 5000, 6667], [0, 0, 0, 0]), 0);
  assert.equal(reversals([0, 10, 0, 10]), 2);
  assert.equal(topZone([0, 0]), null);
  assert.equal(topZone([1, 5, 5]), 1);
  assert.equal(medianOf([1, 9, 3, 7]), 7);
  assert.equal(summaryOf([]), null);
  const lo = { score: 1 }, hi = { score: 3 };
  assert.equal(measured(lo, hi), 'lighter');
  assert.equal(measured(hi, lo), 'heavier');
  assert.equal(measured({ score: 2 }, hi), 'same');
  assert.equal(flagOf('better', 'heavier'), 'felt better, measured heavier');
  assert.equal(flagOf('same', 'heavier'), 'none');
});

test('jointText prints a row per arm and marks a disagreement', () => {
  const j = of('joint').find((x) => x.same.some((r) => r.flag !== 'none'));
  const text = jointText(j.seed, [...j.ratings, ...j.look], [...j.captures, ...j.lookCaptures]);
  assert.match(text, /DISAGREE: felt worse, measured lighter/);
  assert.match(text, /base: /);
  assert.match(text, /morph\.stage: /);
});
