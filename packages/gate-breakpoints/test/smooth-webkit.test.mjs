// The schedule shared by the Chromium cadence lane and the two WebKit legs: one definition, a fair rotation of the arms.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HERO_BURST, END_PUSH, orderFor } from '../src/smooth/schedule.mjs';
import * as cadence from '../src/smooth/cadence.mjs';

test('the cadence lane re-exports the one schedule', () => {
  assert.equal(cadence.HERO_BURST, HERO_BURST);
  assert.equal(cadence.END_PUSH, END_PUSH);
  assert.equal(cadence.orderFor, orderFor);
});

test('orderFor rotates the arms: every arm leads once per lap and no arm is dropped', () => {
  const arms = ['orig', 'base', 'aa', 'look'];
  const leads = new Set();
  for (let rep = 0; rep < arms.length; rep++) {
    const o = orderFor(arms, rep);
    assert.deepEqual([...o].sort(), [...arms].sort());
    leads.add(o[0]);
  }
  assert.equal(leads.size, arms.length);
  assert.deepEqual(orderFor(arms, arms.length), arms);
});

test('the hero burst scrolls 60 x 42 px in about a second', () => {
  assert.equal(HERO_BURST.count * HERO_BURST.dy, 2520);
  assert.ok(HERO_BURST.count * HERO_BURST.everyMs >= 900 && HERO_BURST.count * HERO_BURST.everyMs <= 1100);
  assert.equal(END_PUSH.dy, 120);
});
