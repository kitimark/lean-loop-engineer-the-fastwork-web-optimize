import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { appendOnly, faultOf, handReset, isHarness, mayAttempt, recordFault, tabPlan } from '../src/device-faults.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('the golden has fault, attempt and tab lines', () => {
  for (const k of ['fault', 'attempt', 'tabs', 'reset', 'append']) assert.ok(of(k).length > 5, k);
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
  for (const c of of('tabs')) assert.deepEqual(tabPlan(c.host, c.urls), c.plan, c.urls.join(' | '));
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

test('a tab left on another port of our host is reset; another host or scheme is not ours', () => {
  const host = 'http://harness.test';
  assert.deepEqual(tabPlan(host, ['http://harness.test:3999/']), { plan: 'reset', i: 0 });
  assert.deepEqual(tabPlan(host, ['http://harness.test.evil:4100/']), { plan: 'refuse' });
  assert.deepEqual(tabPlan(host, ['https://harness.test:4100/']), { plan: 'refuse' });
});

test('a hand reset keeps the faults and the retry rule, as in Lean', () => {
  for (const c of of('reset')) {
    assert.deepEqual(handReset(c.faults), c.after, c.faults.join(','));
    assert.equal(mayAttempt(handReset(c.faults)), c.may, c.faults.join(','));
  }
  assert.equal(mayAttempt(['usbReset', 'staleTab', 'other']), false, 'visit 6 of 2026-10-25 is lost');
});

test('appendOnly and recordFault match Lean', () => {
  for (const c of of('append')) assert.equal(appendOnly(c.old, c.new), c.ok, `${c.old} -> ${c.new}`);
  assert.deepEqual(recordFault(['usbReset'], 'staleTab'), ['usbReset', 'staleTab']);
});

test('the state refuses a write that drops earlier faults, and a hand reset keeps them', async () => {
  const { saveState, loadState, markHandReset } = await import('../src/device-phone-run.mjs');
  const dir = mkdtempSync(join(tmpdir(), 'pec-state-'));
  saveState(dir, { visits: [{ index: 6, arm: 'a', status: 'failed', attempts: 2, faults: ['usbReset', 'staleTab'] }] });
  const after = markHandReset(dir, 6, 'tab returned to about:blank by hand');
  assert.deepEqual(after.visits[0].faults, ['usbReset', 'staleTab']);
  assert.equal(loadState(dir).leadReset.length, 1);
  assert.throws(() => saveState(dir, { visits: [{ index: 6, arm: 'a', status: 'failed', attempts: 3, faults: ['other'] }] }), /do not extend/);
  saveState(dir, { visits: [{ index: 6, arm: 'a', status: 'lost', attempts: 3, faults: ['usbReset', 'staleTab', 'other'] }] });
  assert.deepEqual(loadState(dir).visits[0].faults, ['usbReset', 'staleTab', 'other']);
});
