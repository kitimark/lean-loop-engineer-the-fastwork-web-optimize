// The view stage brings the union over both arms (src/view.mjs; Lean Fw.Gate.Settle.viewCell with one bring flag for both arms,
// Fw.Gate.Freeze.viewRank / both_arms_same_instant): tested with the mock frozen session of freeze.test.mjs and a fake page.
import test from 'node:test';
import assert from 'node:assert/strict';
import { READY_TO_MS, SLOT_MS, instant, newRec, observeAt, stopBase, viewRank } from '../src/freeze.mjs';
import { makeViewBarrier, skippedParts, viewStage, viewUnion } from '../src/view.mjs';
import { view as keep } from '../src/settle.mjs';

function mockSession() {
  let elapsed = 0;
  return {
    advance: async (ms) => { elapsed += ms; },
    holdTo: async (abs) => { elapsed += Math.max(0, abs - elapsed); },
    clockMs: () => elapsed,
    evaluate: async () => true,
  };
}
const noop = () => true;
const PLAIN = ['commission', 'hero.exit', 'nav.hitTest', 'footer'];
const NOV = 1;
const item = (skipped, val) => ({ skipped, val });
/** First reading of an arm: the parts in `skippedIds` have one skipped node (value 'stale'), the others a rendered one. */
const firstOf = (skippedIds) => Object.fromEntries(PLAIN.map((pid) => [pid, { box: { items: [item(skippedIds.includes(pid), skippedIds.includes(pid) ? 'stale' : 'v')] } }]));

/** One arm: its work before the view stage differs (`extraMs`), the stage reads at the Lean view instants of a stop at `base`. */
async function arm(site, skippedIds, extraMs, barrier) {
  const s = mockSession();
  await s.holdTo(READY_TO_MS);
  await s.advance(extraMs);
  const rec = newRec();
  const base = stopBase(0, NOV + PLAIN.length);
  const raw = { parts: firstOf(skippedIds) };
  const read = [];
  const scrolled = [];
  const mine = skippedParts(raw.parts, PLAIN);
  const ids = barrier ? await barrier.post(site, mine) : mine;
  await viewStage({
    roots: (pid) => [`#${pid}`],
    bring: async (roots) => { scrolled.push(roots[0]); return { skippedBefore: skippedIds.length, scrollY: 100 }; },
    settle: async () => ({ outcome: 'settled@3', observations: 3, waitedMs: 48, parked: true }),
    at: async (pid) => { await observeAt(s, instant(base, viewRank(NOV, PLAIN.indexOf(pid))), noop, rec, `view ${pid}`); read.push([pid, s.clockMs()]); },
    again: async (pid) => ({ [pid]: { box: { items: [item(false, 'v')] } } }),
    keep,
    log: () => {},
  }, raw, ids);
  return { ids, read, scrolled, rec, raw };
}

test('viewUnion: the plain parts that any arm lists, in plain order, whichever arm lists them', () => {
  assert.deepEqual(viewUnion(PLAIN, [['nav.hitTest'], ['commission']]), ['commission', 'nav.hitTest']);
  assert.deepEqual(viewUnion(PLAIN, [['commission'], ['nav.hitTest']]), viewUnion(PLAIN, [['nav.hitTest'], ['commission']]));
  assert.deepEqual(viewUnion(PLAIN, [[], []]), []);
  assert.deepEqual(viewUnion(PLAIN, [['nope'], []]), []);
  assert.deepEqual(skippedParts(firstOf(['footer', 'commission']), PLAIN), ['commission', 'footer']);
});

test('arms that read different parts skipped bring the same set and read each part at the same fake instant', async () => {
  const barrier = makeViewBarrier(PLAIN, ['orig', 'rewrite']);
  const [o, r] = await Promise.all([arm('orig', ['commission'], 4 * 16, barrier), arm('rewrite', ['nav.hitTest'], 0, barrier)]);
  assert.deepEqual(o.ids, ['commission', 'nav.hitTest']);
  assert.deepEqual(r.ids, o.ids);
  assert.deepEqual(o.scrolled, r.scrolled);
  assert.deepEqual(o.read, r.read);
  assert.deepEqual(o.read.map(([, t]) => t), o.ids.map((pid) => instant(stopBase(0, NOV + PLAIN.length), viewRank(NOV, PLAIN.indexOf(pid)))));
  assert.ok(o.rec.misses.length === 0 && r.rec.misses.length === 0);
  // the part the arm did not read skipped is read again too, and the kept reading is the second one
  assert.equal(r.raw.viewed.commission.skippedBefore, 1);
  assert.deepEqual(r.raw.viewFirst.commission.box.items, [item(false, 'v')]);
  assert.deepEqual(r.raw.parts.commission.box.items, [item(false, 'v')]);
  assert.deepEqual(o.raw.parts['nav.hitTest'].box.items, [item(false, 'v')]);
  assert.deepEqual(o.raw.viewed.commission.settle, 'settled@3');
  // without the union, an arm brings only its own parts: the sets differ and the instants of the other part are never visited
  const alone = await arm('orig', ['commission'], 0, null);
  assert.deepEqual(alone.ids, ['commission']);
  assert.notDeepEqual(alone.read, o.read);
});

test('no part skipped in either arm: no view reading, nothing recorded, the first reading is kept', async () => {
  const barrier = makeViewBarrier(PLAIN, ['orig', 'rewrite']);
  const [o, r] = await Promise.all([arm('orig', [], 0, barrier), arm('rewrite', [], 16, barrier)]);
  assert.deepEqual(o.ids, []);
  assert.deepEqual(r.read, []);
  assert.equal(o.raw.viewed, undefined);
  assert.equal(o.raw.viewFirst, undefined);
});

test('a view instant is in a slot of its own: the view readings of one stop are SLOT_MS apart', async () => {
  const barrier = makeViewBarrier(PLAIN, ['orig', 'rewrite']);
  const [o] = await Promise.all([arm('orig', PLAIN, 0, barrier), arm('rewrite', [], 0, barrier)]);
  assert.deepEqual(o.ids, PLAIN);
  const ts = o.read.map(([, t]) => t);
  for (let i = 1; i < ts.length; i++) assert.equal(ts[i] - ts[i - 1], SLOT_MS);
});

test('a barrier whose arm failed rejects the arm that waits; an arm cannot post twice or from an unknown site', async () => {
  const b = makeViewBarrier(PLAIN, ['orig', 'rewrite']);
  const waiting = b.post('orig', ['commission']);
  b.fail(new Error('rewrite load failed'));
  await assert.rejects(waiting, /rewrite load failed/);
  const c = makeViewBarrier(PLAIN, ['orig', 'rewrite']);
  c.post('orig', []);
  assert.throws(() => c.post('orig', []), /posted twice/);
  assert.throws(() => c.post('elsewhere', []), /unknown arm/);
});
