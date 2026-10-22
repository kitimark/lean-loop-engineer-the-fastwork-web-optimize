import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { BOUND_CSS, BOUND_JS, KNOWN_ARMS, parseArms, endPushFor } from '../src/smooth/bound.mjs';
import { END_PUSH } from '../src/smooth/schedule.mjs';

test('parseArms: a list of known ids, undefined for none, a throw for an unknown or repeated id', () => {
  assert.equal(parseArms(undefined), undefined);
  assert.equal(parseArms(''), undefined);
  assert.deepEqual(parseArms('base,aa,bound'), ['base', 'aa', 'bound']);
  assert.deepEqual(parseArms(' base , bound '), ['base', 'bound']);
  assert.throws(() => parseArms('base,nope'), /unknown arm "nope"/);
  assert.throws(() => parseArms('base,base'), /twice/);
  for (const id of ['orig', 'base', 'aa', 'look', 'v2', 'bound']) assert.ok(KNOWN_ARMS.includes(id));
});

test('endPushFor: the shared push, or the same push with each half held longer', () => {
  assert.equal(endPushFor(undefined), END_PUSH);
  assert.equal(endPushFor(''), END_PUSH);
  assert.deepEqual(endPushFor('1400'), { dy: END_PUSH.dy, holdMs: 1400 });
  assert.equal(END_PUSH.holdMs, 1000);
});

test('the bound stylesheet switches off the transitions of the earn button only, found by the hook the nav part sets', () => {
  assert.match(BOUND_CSS, /\[data-fw="nav-earn"\][^{]*\{ transition: none !important; \}/);
  assert.doesNotMatch(BOUND_CSS.replaceAll('[data-fw="nav-earn"]', ''), /\.|#/);
  assert.match(BOUND_JS, /fw-bound/);
  const nav = readFileSync(new URL('../../../apps/site/src/parts/nav/index.tsx', import.meta.url), 'utf8');
  assert.match(nav, /data-fw="nav-earn"/);
});

test('the bound arm is not a flag: the nav part has no variant for it', () => {
  const part = JSON.parse(readFileSync(new URL('../../../apps/site/src/parts/nav/part.json', import.meta.url), 'utf8'));
  assert.ok(!Object.keys(part.variants).some((v) => /bound/.test(v)));
});
