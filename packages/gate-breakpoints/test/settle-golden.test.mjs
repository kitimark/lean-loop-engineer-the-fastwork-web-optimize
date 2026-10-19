// The settle decisions (src/settle.mjs, and the copies inside page.mjs settleInPage) against the golden file Lean generates
// (packages/contracts/golden/gate/settle.jsonl, lean/Fw/Gate/Settle.lean). Nothing is decided here.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { GATE_POLICY, cell, flagSweeps, fold, idlePolicy, keyCell, keyMasked, keyPair, layoutOutputKey, nextStable, quiet, rendered, report, settled, spent, view, viewCell, viewFor, waitTrace } from '../src/settle.mjs';
import { settleInPage } from '../src/page.mjs';
import { maskKeys, maskNotRendered } from '../src/summary.mjs';
import { PKG } from '../src/serve.mjs';
import { SETTLE_GOLDEN, settlegen } from '../scripts/settlegen.mjs';

const ROOT = resolve(PKG, '../..');
const lines = readFileSync(SETTLE_GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

/** The predicate texts between markers in settleInPage, rebuilt as functions: the very text that runs in the page. */
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

test('keymask: every golden pair of a layout-output key of a flagged node is masked, every other is as read (golden)', () => {
  assert.ok(of('keymask').length >= 9);
  for (const l of of('keymask')) {
    assert.equal(keyMasked(l.skippedO, l.skippedR, l.key), l.masked, l.name);
    assert.deepEqual(keyPair(l.skippedO, l.skippedR, l.key, l.a, l.b), [l.seenA, l.seenB], l.name);
    assert.equal(keyCell(l.skippedO, l.skippedR, l.key, l.a, l.b, 'settled@1', 'settled@2'), l.cell, l.name);
    // Lean keyPair_differs_iff: the pair a comparison sees differs exactly when the values differ and the pair is not masked
    assert.equal(l.seenA !== l.seenB, l.a !== l.b && !l.masked, l.name);
  }
  assert.equal(layoutOutputKey('margin-inline'), true);
  assert.equal(layoutOutputKey('width'), false);
});

test('flagSweeps: every golden switch and engine gives the Lean flag (the same as the bring flag)', () => {
  assert.ok(of('flagSweeps').length >= 8);
  for (const l of of('flagSweeps')) {
    assert.equal(flagSweeps(l.switch ?? undefined, l.engine), l.flag, l.name);
    assert.equal(l.flag, of('viewFor').find((v) => v.name === l.name).view, l.name);
  }
});

test('maskKeys: a flagged node loses only its margin keys, in either arm; a real difference of any other key stays', () => {
  const it = (style, skipped, rect = { x: 0, y: 0, w: 10, h: 10 }) => ({ rect, style, ...(skipped ? { skipped: true } : {}) });
  const arm = (items) => ({ settle: {}, raw: { parts: { commission: { rows: { count: items.length, declared: [], items } } } } });
  const items = (st) => st.raw.parts.commission.rows.items;
  // the commission rows of run 39333030506: the original reads the zero strut while its subtree is skipped
  const state = {
    orig: arm([it({ 'margin-inline': '0px', 'margin-top': '0px', width: '100px', color: 'red' }, true), it({ 'margin-inline': '0px' }, false)]),
    rewrite: arm([it({ 'margin-inline': '8px', 'margin-top': '8px', width: '120px', color: 'red' }, false), it({ 'margin-inline': '8px' }, false)]),
  };
  const { state: out, masked } = maskKeys(state);
  assert.deepEqual(masked, [{ part: 'commission', role: 'rows', idx: 0, orig: true, rewrite: false, keys: ['margin-inline', 'margin-top'] }]);
  const [o, r] = [items(out.orig), items(out.rewrite)];
  assert.equal(o[0].style['margin-inline'], r[0].style['margin-inline'], 'masked key: same value both sides');
  assert.equal(o[0].style['margin-top'], r[0].style['margin-top']);
  assert.notEqual(o[0].style.width, r[0].style.width, 'a real width difference of the flagged node is kept');
  assert.deepEqual(o[0].rect, r[0].rect);
  assert.equal(o[0].skipped, undefined);
  assert.notEqual(o[1].style['margin-inline'], r[1].style['margin-inline'], 'a rendered node is left alone, its margin difference stays');
  assert.equal(maskKeys({ orig: arm([it({ 'margin-top': '1px' }, false)]), rewrite: arm([it({ 'margin-top': '2px' }, false)]) }).masked.length, 0);
  const rect = maskKeys({ orig: arm([it({ 'margin-top': '1px' }, true, { x: 0, y: 0, w: 1, h: 1 })]), rewrite: arm([it({ 'margin-top': '2px' }, false, { x: 0, y: 0, w: 2, h: 1 })]) });
  assert.notDeepEqual(items(rect.state.orig)[0].rect, items(rect.state.rewrite)[0].rect, 'the rect of a flagged node stays compared');
  // a bare pair (the hysteresis pair: no .raw wrapper)
  const bare = maskKeys({ orig: state.orig.raw, rewrite: state.rewrite.raw });
  assert.equal(bare.masked.length, 1);
});
