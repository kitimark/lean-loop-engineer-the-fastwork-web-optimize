// The settle decisions (src/settle.mjs, and the copies inside page.mjs settleInPage) against the golden file Lean generates
// (packages/contracts/golden/gate/settle.jsonl, lean/Fw/Gate/Settle.lean). Nothing is decided here.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { GATE_POLICY, nextStable, quiet, report, settled, waitTrace } from '../src/settle.mjs';
import { settleInPage } from '../src/page.mjs';
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
