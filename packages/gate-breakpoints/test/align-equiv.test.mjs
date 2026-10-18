// Replays the Lean golden vectors of Fw.Gate.AlignEquiv (packages/contracts/golden/gate/align-equiv.jsonl;
// regenerate: cd lean && lake env lean --run scripts/AlignEquivGolden.lean) against the JS mirror.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  alignEquiv, equivSpec, modeOf, eligible, contentFill, canonParts, attachAlignFacts, collectAlignFacts,
} from '../src/align-equiv.mjs';

const golden = join(dirname(fileURLToPath(import.meta.url)), '../../contracts/golden/gate/align-equiv.jsonl');
const rows = readFileSync(golden, 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('golden: at least the 38 Lean cases, unique names', () => {
  assert.ok(rows.length >= 38);
  assert.equal(new Set(rows.map((r) => r.name)).size, rows.length);
});

for (const { name, request: { orig: o, rewrite: r }, response: want } of rows) {
  test(`golden ${name}`, () => {
    assert.deepEqual({
      equiv: alignEquiv(o, r), spec: equivSpec(o, r),
      modeOrig: modeOf(o), modeRewrite: modeOf(r),
      eligibleOrig: eligible(o), eligibleRewrite: eligible(r),
      fillsOrig: contentFill(o), fillsRewrite: contentFill(r),
    }, want);
    assert.equal(alignEquiv(r, o), want.equiv, 'symmetric (Lean alignEquiv_symm)');
  });
}

test('canonParts: only judged pairs change, only align-self, boxes kept (Lean canonItem, geometry_still_compared)', () => {
  const stage = rows.find((x) => x.name === 'stage-stretch-vs-start-fills').request;
  const short = rows.find((x) => x.name === 'stage-start-does-not-fill').request;
  const rect = { x: 0, y: 100, w: 375, h: 300 };
  const orig = { p: { stage: { count: 2, items: [
    { rect, style: { 'align-self': 'auto', width: '375px' }, align: stage.orig },
    { rect, style: { 'align-self': 'auto' }, align: short.orig }] } } };
  const rew = { p: { stage: { count: 2, items: [
    { rect: { ...rect, h: 299 }, style: { 'align-self': 'start', width: '375px' }, align: stage.rewrite },
    { rect, style: { 'align-self': 'start' }, align: short.rewrite }] } } };
  const out = canonParts(orig, rew);
  assert.deepEqual(out.p.stage.items[0].style, { 'align-self': 'auto', width: '375px' });
  assert.deepEqual(out.p.stage.items[0].rect, { ...rect, h: 299 });
  assert.equal(out.p.stage.items[1], rew.p.stage.items[1]);
  assert.equal(rew.p.stage.items[0].style['align-self'], 'start', 'input not mutated');
  const noAlign = canonParts({ p: { stage: { items: [{ rect, style: {} }] } } }, { p: { stage: { items: [{ rect, style: { 'align-self': 'start' }, align: stage.rewrite }] } } });
  assert.deepEqual(noAlign.p.stage.items[0].style, { 'align-self': 'start' }, 'no facts on the original: unchanged');
});

test('attachAlignFacts puts facts on items by index', () => {
  const rec = { parts: { p: { stage: { items: [{ style: {} }, { style: {} }] } } } };
  attachAlignFacts(rec, { p: { stage: [{ alignSelf: 'start' }, null] } });
  assert.deepEqual(rec.parts.p.stage.items[0].align, { alignSelf: 'start' });
  assert.equal(rec.parts.p.stage.items[1].align, undefined);
});

test('collectAlignFacts is self-contained (serialisable for page.evaluate)', () => {
  const src = collectAlignFacts.toString();
  const fn = new Function(`return (${src});`)();
  assert.equal(typeof fn, 'function');
  globalThis.document = { styleSheets: [], querySelectorAll: () => [] };
  try {
    assert.deepEqual(fn({ parts: { p: [{ role: 'stage', selector: '.x' }] }, props: { p: { stage: ['align-self'] } } }), { p: { stage: [] } });
    assert.deepEqual(fn({ parts: { p: [{ role: 'stage', selector: '.x' }] }, props: { p: { stage: ['width'] } } }), {});
  } finally { delete globalThis.document; }
});
