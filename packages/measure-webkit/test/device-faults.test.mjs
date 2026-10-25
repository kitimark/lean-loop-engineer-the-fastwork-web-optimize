import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { faultOf, isHarness, mayAttempt, tabPlan } from '../src/device-faults.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('the golden has fault, attempt and tab lines', () => {
  for (const k of ['fault', 'attempt', 'tabs']) assert.ok(of(k).length > 5, k);
});

test('faultOf and harness match Lean', () => {
  for (const c of of('fault')) {
    assert.equal(faultOf(c.text), c.fault, c.text);
    assert.equal(isHarness(c.fault), c.harness, c.text);
  }
});

test('mayAttempt matches Lean: a third attempt only after harness faults only', () => {
  for (const c of of('attempt')) assert.equal(mayAttempt(c.faults), c.may, c.faults.join(','));
});

test('tabPlan matches Lean', () => {
  for (const c of of('tabs')) assert.deepEqual(tabPlan(c.origin, c.urls), c.plan, c.urls.join(' | '));
});

test('a state without fault names counts each failed attempt as another fault (no free retry)', () => {
  assert.equal(mayAttempt(['other', 'other']), false);
  assert.equal(mayAttempt(['usbReset', 'staleTab']), true);
});

test('a state entry gives one fault per failed attempt; an entry written before the names counts as other', async () => {
  const { faultsOfVisit } = await import('../src/device-phone-run.mjs');
  assert.deepEqual(faultsOfVisit(undefined), []);
  assert.deepEqual(faultsOfVisit({ attempts: 2, faults: ['usbReset', 'staleTab'] }), ['usbReset', 'staleTab']);
  assert.deepEqual(faultsOfVisit({ attempts: 2 }), ['other', 'other']);
  assert.deepEqual(faultsOfVisit({ attempts: 2, faults: ['usbReset'] }), ['usbReset', 'other']);
  assert.equal(mayAttempt(faultsOfVisit({ attempts: 2, faults: ['usbReset', 'staleTab'] })), true);
  assert.equal(mayAttempt(faultsOfVisit({ attempts: 2 })), false);
});
