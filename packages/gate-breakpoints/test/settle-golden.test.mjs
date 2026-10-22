import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { GATE_POLICY, cell, fold, idlePolicy, nextStable, quiet, rendered, report, runCount, settled, spent, view, viewCell, viewFor, waitTrace } from '../src/settle.mjs';
import { settleInPage } from '../src/page.mjs';
import { maskNotRendered } from '../src/summary.mjs';
import { PKG } from '../src/serve.mjs';
import { SETTLE_GOLDEN, settlegen } from '../scripts/settlegen.mjs';

const ROOT = resolve(PKG, '../..');
const lines = readFileSync(SETTLE_GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

function fromPage(tag) {
  const src = settleInPage.toString();
  const m = new RegExp(`// <${tag}>\\s*([\\s\\S]*?)\\s*// </${tag}>`).exec(src);
  assert.ok(m, `marker ${tag} not found in settleInPage`);
  return (0, eval)(`(${m[1].replace(/^const \w+ = /, '').replace(/;\s*$/, '')})`);
}

test('settle.jsonl is the bytes Lean generates', { skip: !existsSync(resolve(ROOT, 'lean/.lake/build')) && 'lean not built' }, () => {
  const r = settlegen(['--check', SETTLE_GOLDEN]);
  assert.equal(r.status, 0, r.stderr);
});

test('the gate policy is the one the golden file is written with', () => {
  for (const l of of('settled')) assert.deepEqual(l.policy, GATE_POLICY, l.name);
});

test('settled: every golden observation', () => {
  assert.ok(of('settled').length >= 10);
  for (const l of of('settled')) assert.equal(settled(l.policy, l.obs), l.settled, l.name);
});

test('settled: the copy inside the page function gives the same answers', () => {
  const pageSettled = fromPage('settled');
  for (const l of of('settled')) assert.equal(pageSettled(l.policy, l.obs), l.settled, l.name);
});

test('quiet and nextStable: every golden pair of frames, node copy and page copy', () => {
  const pageQuiet = fromPage('quiet');
  assert.ok(of('quiet').length >= 8);
  for (const l of of('quiet')) {
    assert.equal(quiet(l.eps, l.prev, l.cur), l.quiet, l.name);
    assert.equal(pageQuiet(l.eps, l.prev, l.cur), l.quiet, l.name);
    assert.equal(nextStable(l.eps, 2, l.prev, l.cur), l.next, l.name);
  }
});

test('wait: every golden trace gives Lean outcome', () => {
  assert.ok(of('wait').length >= 8);
  for (const l of of('wait')) assert.equal(waitTrace(l.policy, l.trace), l.outcome, l.name);
});

test('the page loop stops where Lean has decided: truncating at its stop keeps the outcome (scan_decided_by)', () => {
  const pageSettled = fromPage('settled');
  const pageSpent = fromPage('spent');
  for (const l of of('wait')) {
    const stop = l.trace.findIndex((o) => pageSettled(l.policy, o) || pageSpent(l.policy, o));
    for (const o of l.trace) assert.equal(pageSpent(l.policy, o), spent(l.policy, o), l.name);
    const seen = stop < 0 ? l.trace : l.trace.slice(0, stop + 1);
    assert.equal(waitTrace(l.policy, seen), l.outcome, l.name);
  }
});

test('frame budget: the gate policy ends a wait after maxFrames real frames, the idle policy is Lean idlePolicy', () => {
  assert.equal(GATE_POLICY.maxFrames, 60);
  const byName = (n) => of('wait').find((l) => l.name === n);
  assert.equal(byName('a lerp that never stops spends the frame budget long before the timeout').outcome, 'unsettled');
  assert.equal(byName('settles exactly at the frame budget').outcome, 'settled@2');
  assert.equal(byName('settles one frame after the frame budget').outcome, 'unsettled');
  const idle = of('wait').filter((l) => l.name.startsWith('idle:'));
  assert.ok(idle.length >= 4);
  for (const l of idle) assert.deepEqual(l.policy, idlePolicy(GATE_POLICY, l.policy.timeoutMs), l.name);
});

test('fold: a sample is unsettled when any of its waits is (golden)', () => {
  assert.ok(of('fold').length >= 5);
  for (const l of of('fold')) assert.equal(fold(l.first, l.extra), l.outcome, l.name);
});

test('view: bring bit picks the second reading, and the cell follows (Fw.Gate.Settle.viewCell)', () => {
  assert.ok(of('view').length >= 8);
  for (const l of of('view')) assert.equal(viewCell(l.bringO, l.bringR, l.firstO, l.againO, l.firstR, l.againR, l.a, l.b), l.cell, l.name);
  const f = { skipped: true, val: 0 }, g = { skipped: false, val: 132 };
  assert.deepEqual(view(true, f, g), g);
  assert.deepEqual(view(false, f, g), f);
});

test('viewFor: every golden switch and engine gives the Lean bring flag (Chromium on, WebKit off, the switch overrides)', () => {
  assert.ok(of('viewFor').length >= 8);
  for (const l of of('viewFor')) assert.equal(viewFor(l.switch ?? undefined, l.engine), l.view, l.name);
});

test('report: an unsettled arm is never a pass or a fail', () => {
  assert.ok(of('report').length >= 5);
  for (const l of of('report')) assert.equal(report(l.a, l.b, l.equal), l.report, l.name);
  for (const e of [true, false]) {
    assert.equal(report('unsettled', 'settled@1', e), 'unsettled');
    assert.equal(report('settled@1', 'unsettled', e), 'unsettled');
  }
});

test('the three misreads of run 39067170911 are unsettled in the golden file', () => {
  const byName = (n) => of('settled').find((l) => l.name.startsWith(n));
  for (const n of ['pain.notes', 'hero.orbit: parked', 'overlays.signup']) assert.equal(byName(n).settled, false, n);
  assert.equal(byName('hero.orbit after parking').settled, true);
  assert.equal(of('quiet').find((l) => l.name.startsWith('people.deck')).quiet, false);
});

test('maskNotRendered: an item under a skipping ancestor in either arm is equal on both sides, and listed', () => {
  const it = (m, skipped) => ({ rect: null, style: { 'margin-inline': m }, ...(skipped ? { skipped: true } : {}) });
  const arm = (items) => ({ settle: {}, raw: { parts: { commission: { inner: { count: items.length, declared: [], items } } } } });
  const state = { orig: arm([it('96px', false), it('8px', true)]), rewrite: arm([it('0px', false), it('0px', false)]) };
  const { state: out, masked } = maskNotRendered(state);
  assert.deepEqual(masked, [{ part: 'commission', role: 'inner', idx: 1, orig: true, rewrite: false }]);
  const [o, r] = [out.orig.raw.parts.commission.inner.items, out.rewrite.raw.parts.commission.inner.items];
  assert.deepEqual(o[1], r[1], 'masked item: same values both sides, so it can neither fail nor pass');
  assert.equal(o[1].skipped, undefined);
  assert.notDeepEqual(o[0], r[0], 'a rendered item is left alone');
  assert.equal(maskNotRendered({ orig: arm([it('1px', false)]), rewrite: arm([it('2px', false)]) }).masked.length, 0);
});

test('rendered and cell: a node in a skipped subtree is notRendered, never pass or fail (golden)', () => {
  assert.ok(of('rendered').length >= 4 && of('cell').length >= 6);
  for (const l of of('rendered')) assert.equal(rendered(l.skips), l.rendered, l.name);
  for (const l of of('cell')) assert.equal(cell(l.renderedA, l.renderedB, l.a, l.b, l.equal), l.cell, l.name);
  for (const e of [true, false]) {
    assert.equal(cell(false, true, 'settled@1', 'settled@1', e), 'notRendered');
    assert.equal(cell(true, false, 'unsettled', 'settled@1', e), 'notRendered');
  }
});

test('runs: the node twin and the page copy count document-timeline animations only (golden)', () => {
  const pageCounts = fromPage('counts');
  assert.ok(of('runs').length >= 6);
  for (const l of of('runs')) {
    assert.equal(runCount(l.anims), l.running, l.name);
    const inPage = l.anims.filter((a) => pageCounts({ onDocument: a.onDocument, finite: true, state: a.elapsed < a.dur ? 'running' : 'finished' })).length;
    assert.equal(inPage, l.running, l.name);
  }
});

test('runs: a scroll-driven animation was counted by the old rule and is not by the new one (the unsettled arms of run 39769627588)', () => {
  const l = of('runs').find((x) => x.name.startsWith('hero.exit:threaded'));
  assert.equal(l.before, 2, 'the old rule counted the two view-timeline animations');
  assert.equal(l.running, 0);
  assert.equal(settled(GATE_POLICY, { running: l.running, frames: 5, stable: 5, hoverInside: false, t: 100 }), true);
  assert.equal(settled(GATE_POLICY, { running: l.before, frames: 5, stable: 5, hoverInside: false, t: 100 }), false);
});

test('runs: no counting site in page.mjs lets a non-document animation through', () => {
  const src = readFileSync(resolve(PKG, 'src/page.mjs'), 'utf8');
  const sites = src.split('\n').filter((l) => /Number\.isFinite\(t\.iterations\)/.test(l) && /playState/.test(l));
  assert.equal(sites.length, 4, 'the three filters that read playState and the call of `counts` in the settle probe');
  for (const l of sites) assert.match(l, /a\.timeline instanceof DocumentTimeline/, l.trim());
});
