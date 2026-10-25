import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { GUARDED_PORTS, USB_WAIT_S, appendOnly, classify, faultOf, handReset, isHarness, mayAttempt, proxiesClear, proxyVerdict, recordFault, resetPlan, specAttaches, tabPlan, usbLine, usbVerdict, usbWait, writeOk } from '../src/device-faults.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('the golden has fault, attempt and tab lines', () => {
  for (const k of ['fault', 'attempt', 'tabs', 'reset', 'append', 'write', 'handreset']) assert.ok(of(k).length > 5, k);
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

test('writeOk matches Lean: a visit with faults is never removed, its faults only grow', () => {
  for (const c of of('write')) assert.equal(writeOk(c.old, c.new), c.ok, JSON.stringify([c.old, c.new]));
});

test('resetPlan matches Lean: bad index, no reason, no visit, or a note', () => {
  assert.deepEqual([...new Set(of('handreset').map((c) => c.n))], [16, 4]);
  for (const c of of('handreset')) assert.deepEqual(resetPlan(c.state, c.index, c.reason, c.n), c.plan, `${c.index} ${c.reason}`);
});

test('the state refuses a write that removes a visit with faults, and allows removing one without', async () => {
  const { saveState, loadState } = await import('../src/device-phone-run.mjs');
  const dir = mkdtempSync(join(tmpdir(), 'pec-state-'));
  saveState(dir, { visits: [{ index: 6, arm: 'a', status: 'failed', attempts: 2, faults: ['usbReset', 'staleTab'] }, { index: 2, arm: 'b', status: 'done', attempts: 0 }] });
  assert.throws(() => saveState(dir, { visits: [{ index: 2, arm: 'b', status: 'done', attempts: 0 }] }), /visit 6: removed with faults/);
  assert.throws(() => saveState(dir, { visits: [] }), /removed with faults/);
  saveState(dir, { visits: [{ index: 6, arm: 'a', status: 'lost', attempts: 3, faults: ['usbReset', 'staleTab', 'other'] }] });
  assert.equal(loadState(dir).visits.length, 1);
});

test('a legacy entry without fault names is protected by its attempts', async () => {
  const { saveState } = await import('../src/device-phone-run.mjs');
  const dir = mkdtempSync(join(tmpdir(), 'pec-state-'));
  saveState(dir, { visits: [{ index: 4, arm: 'a', status: 'failed', attempts: 2 }] });
  assert.throws(() => saveState(dir, { visits: [] }), /visit 4: removed with faults \[other,other\]/);
});

test('arms-run --hand-reset notes the reset and keeps the faults; bad arguments are refused with the Lean plan name', async () => {
  const { saveState, loadState, handResetCommand } = await import('../src/device-phone-run.mjs');
  const dir = mkdtempSync(join(tmpdir(), 'pec-state-'));
  saveState(dir, { visits: [{ index: 6, arm: 'a', status: 'failed', attempts: 2, faults: ['usbReset', 'staleTab'] }] });
  assert.throws(() => handResetCommand(dir, '6', '  '), /noReason/);
  assert.throws(() => handResetCommand(dir, 'x', 'why'), /badIndex/);
  assert.throws(() => handResetCommand(dir, '9', 'why'), /noVisit/);
  assert.equal(loadState(dir).leadReset, undefined);
  const st = handResetCommand(dir, '6', 'tab returned to about:blank by hand');
  assert.deepEqual(st.leadReset, [{ index: 6, reason: 'tab returned to about:blank by hand' }]);
  assert.deepEqual(loadState(dir).visits[0].faults, ['usbReset', 'staleTab']);
});

test('usb verdict, log lines, classify and the wait match Lean', () => {
  assert.equal(of('usb').length, 8);
  for (const c of of('usb')) assert.equal(usbVerdict(c), c.verdict, JSON.stringify(c));
  for (const c of of('usbline')) assert.equal(usbLine(c.text), c.is, c.text);
  assert.equal(of('classify').length, 12);
  for (const c of of('classify')) assert.equal(classify(c.text, c.usb), c.fault, `${c.text} ${c.usb}`);
  const [w] = of('usbwait');
  assert.equal(w.waitS, USB_WAIT_S);
  for (const c of w.cases) assert.equal(usbWait(c.listed, c.waitedS), c.wait, JSON.stringify(c));
});

test('proxy verdicts match Lean', () => {
  assert.equal(of('spec').length, 12);
  for (const c of of('spec')) assert.equal(specAttaches(c.udid, c.spec), c.attaches, c.spec);
  assert.equal(of('proxy').length, 14);
  for (const c of of('proxy')) assert.equal(proxyVerdict(c.proxy, c.udid), c.verdict, JSON.stringify(c));
  const [g] = of('proxies');
  assert.deepEqual(g.guarded, GUARDED_PORTS);
  for (const c of g.cases) assert.equal(proxiesClear(c.proxies, g.udid), c.clear, JSON.stringify(c));
});

test('a foreign proxy is a named harness fault', () => {
  assert.equal(faultOf('another ios_webkit_debug_proxy holds port 9221'), 'foreignProxy');
  assert.equal(isHarness('foreignProxy'), true);
});
