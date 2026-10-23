import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BUCKET_US, BUSY_BUCKET, LONG_RUN_MIN, longRuns, median2, frozenCell, sharePct, zoneVerdict } from '../src/lag/swap.mjs';
import { parseFreeze, FREEZE_CSS, FREEZE_JS, freezeStep, freezeApply, freezeProbe } from '../src/lag/freeze.mjs';
import { ZONE_JS, zoneSteps } from '../src/lag/zoneprobe.mjs';
import { freezeSession, stateOrder, alignOrder } from '../src/lag/freezesession.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/wkcost.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every freeze golden kind has lines', () => {
  for (const k of ['swapFreezeConst', 'swapRuns', 'swapMedian2', 'swapFrozen', 'swapShare', 'swapZone']) assert.ok(of(k).length > 0, k);
});

test('constants come from the golden', () => {
  const [c] = of('swapFreezeConst');
  assert.deepEqual([BUCKET_US, BUSY_BUCKET, LONG_RUN_MIN], [c.bucketUs, c.busyBucket, c.longRunMin]);
  assert.equal(LONG_RUN_MIN, c.swapBuckets + 1, 'a run longer than a swap window can touch is not a swap window');
});

test('long busy runs of a diagnostic capture (Lean longRuns)', () => {
  for (const g of of('swapRuns')) assert.equal(longRuns(g.buckets), g.longRuns, JSON.stringify(g.buckets));
});

test('twice the median (Lean median2)', () => {
  for (const g of of('swapMedian2')) assert.equal(median2(g.xs), g.median2, JSON.stringify(g.xs));
});

test('cell of a frozen swap window against the idle level (Lean frozenCell), one case per branch', () => {
  const seen = new Set();
  for (const g of of('swapFrozen')) { assert.equal(frozenCell(g.frozen, g.idle), g.cell, JSON.stringify(g)); seen.add(g.cell); }
  assert.deepEqual([...seen].sort(), ['atIdle', 'busyRemains', 'noIdleLevel', 'noSamples', 'notAtIdle']);
});

test('share of the work the freeze removed (Lean sharePct)', () => {
  for (const g of of('swapShare')) assert.equal(sharePct(g.u2, g.f2), g.pct, JSON.stringify(g));
});

test('zone verdict of the unfrozen against the frozen samples (Lean zoneVerdict)', () => {
  for (const g of of('swapZone')) assert.equal(zoneVerdict(g.off, g.on), g.verdict, JSON.stringify(g));
});

test('--freeze is off unless asked, and names one part', () => {
  assert.equal(parseFreeze(undefined), null);
  assert.equal(parseFreeze(''), null);
  assert.deepEqual(parseFreeze('hero-accent'), { part: 'hero-accent' });
  assert.throws(() => parseFreeze('nav'), /--freeze must be one of/);
});

test('premise: every rule of the freeze style sheet is scoped to the hero.accent root', () => {
  const rules = FREEZE_CSS.split('\n');
  assert.ok(rules.length >= 3);
  for (const rule of rules) {
    const sel = rule.slice(0, rule.indexOf('{'));
    for (const part of sel.split(',')) assert.ok(part.trim().startsWith('[data-fw="hero-accent"]'), part);
    assert.ok(/!important/.test(rule), rule);
  }
  assert.match(FREEZE_CSS, /animation: none/);
  assert.match(FREEZE_CSS, /transition: none/);
  assert.match(FREEZE_CSS, /stroke-dashoffset: 0/);
});

test('unset, the freeze step calls nothing', async () => {
  const c = { runAsync: () => assert.fail('called'), evaluate: () => assert.fail('called') };
  assert.equal(await freezeStep(c, null), null);
  assert.equal(await freezeStep(c, undefined), null);
});

function pageWith({ matched = 1, accentAnims = 0, other = 2 } = {}) {
  const sheets = [];
  const seen = { replaced: null };
  const target = { closest: (s) => (s === '[data-fw="hero-accent"]' ? {} : null) };
  const outside = { closest: () => null };
  const anims = [...Array.from({ length: accentAnims }, () => ({ effect: { target } })), ...Array.from({ length: other }, () => ({ effect: { target: outside } }))];
  const sandbox = {
    document: {
      querySelectorAll: () => Array.from({ length: matched }, () => ({})),
      get adoptedStyleSheets() { return sheets; },
      set adoptedStyleSheets(v) { sheets.splice(0, sheets.length, ...v); },
      getAnimations: () => anims,
    },
    CSSStyleSheet: class { replaceSync(css) { seen.replaced = css; } },
    requestAnimationFrame: (cb) => setImmediate(() => cb(0)),
  };
  return { sandbox, seen, sheets };
}
const clientOf = (sandbox) => ({ runAsync: async (src) => JSON.parse(JSON.stringify(await vm.runInNewContext(src, sandbox))) });

test('freezeApply adopts the style sheet and reads the accent animations after it', async () => {
  const { sandbox, seen, sheets } = pageWith();
  const r = await freezeApply(clientOf(sandbox));
  assert.deepEqual(r, { on: true, matched: 1, sheets: 1, accentAnims: 0, otherAnims: 2 });
  assert.equal(seen.replaced, FREEZE_CSS);
  assert.equal(sheets.length, 1);
});

test('freezeApply refuses a page without the accent, or one whose accent still animates', async () => {
  await assert.rejects(freezeApply(clientOf(pageWith({ matched: 0 }).sandbox)), /no hero-accent element/);
  await assert.rejects(freezeApply(clientOf(pageWith({ accentAnims: 3 }).sandbox)), /3 hero-accent animations still exist/);
});

test('freezeProbe reads the same page without adopting a style sheet', async () => {
  const { sandbox, seen, sheets } = pageWith({ accentAnims: 3 });
  const r = await freezeProbe(clientOf(sandbox));
  assert.deepEqual([r.on, r.accentAnims, r.sheets], [false, 3, 0]);
  assert.equal(seen.replaced, null);
  assert.equal(sheets.length, 0);
  assert.ok(FREEZE_JS(false).includes('false'));
});

test('the hero-exit zone is the steps of scroll region A, from the lane schedule', () => {
  const ys = zoneSteps(800, 6000, 50);
  assert.ok(ys.length >= 2 && ys[0] === 0);
  assert.ok(ys.every((y) => y < 800));
  assert.deepEqual(zoneSteps(800, 6000, 50), ys);
});

function zonePage({ states, alignAfterMs = null }) {
  const marks = [];
  let observers = [], y = 0, cls = states[0], flipped = false;
  const em = { get className() { return cls; } };
  const set = (c) => { cls = c; observers.forEach((o) => o.cb()); };
  const sandbox = {
    document: { querySelector: (s) => (s === '[data-fw="hero-accent"]' ? em : null) },
    MutationObserver: class { constructor(cb) { this.cb = cb; } observe() { observers.push(this); } disconnect() { observers = observers.filter((o) => o !== this); } },
    performance: { mark: (m) => marks.push(m) },
    requestAnimationFrame: (cb) => setImmediate(() => { if (!flipped && alignAfterMs === null && marks.filter((m) => m.startsWith('wk:s')).length === 2) { flipped = true; set(states[1]); } cb(0); }),
    scrollTo: ({ top }) => { y = top; },
    get scrollY() { return y; },
    setTimeout, clearTimeout,
  };
  if (alignAfterMs !== null) setTimeout(() => set(states[1]), alignAfterMs);
  return { sandbox, marks };
}

test('the zone scroll marks every step and the end, and reads the accent class at the start and each change', async () => {
  const { sandbox, marks } = zonePage({ states: ['x idle', 'x drawingOut'] });
  const r = JSON.parse(JSON.stringify(await vm.runInNewContext(ZONE_JS([0, 50, 100, 150], 2, false), sandbox)));
  assert.deepEqual(marks, ['wk:begin', 'wk:s0', 'wk:s1', 'wk:s2', 'wk:s3', 'wk:end']);
  assert.deepEqual([r.start, r.changes, r.y, r.aligned], ['idle', [[1, 'out']], 150, false]);
});

test('an aligned zone scroll waits for the accent to start a draw, and gives up after the wait', async () => {
  const { sandbox, marks } = zonePage({ states: ['x idle', 'x drawingIn'], alignAfterMs: 20 });
  const r = await vm.runInNewContext(ZONE_JS([0, 50], 1, true), sandbox);
  assert.deepEqual([r.start, r.aligned, marks.at(-1)], ['in', true, 'wk:end']);
  const done = vm.runInNewContext(ZONE_JS([0, 50], 1, true).replace('4000', '30'), zonePage({ states: ['x idle', 'x idle'] }).sandbox);
  const r2 = await done;
  assert.deepEqual([r2.start, r2.aligned], ['idle', false]);
});

test('the freeze session alternates the state order and the aligned order by pass', () => {
  assert.deepEqual([0, 1, 2, 3].map(stateOrder), [['free', 'frozen'], ['frozen', 'free'], ['free', 'frozen'], ['frozen', 'free']]);
  for (const i of [0, 1]) {
    const firsts = [0, 1].map((j) => alignOrder(i, j)[0]);
    assert.notEqual(firsts[0], firsts[1], 'the two states do not both start aligned');
    for (const j of [0, 1]) assert.deepEqual([...alignOrder(i, j)].sort(), [false, true]);
  }
});

function stubs() {
  const calls = [];
  const arms = { crop: { id: 'crop', search: 'q' }, faithful: { id: 'faithful', search: '' } };
  const swap = { arms, home: arms.crop };
  const ctx = { setArm: (a) => calls.push(['arm', a]), c: { evaluate: async () => 1 }, check: async () => {} };
  const deps = {
    retrying: async (_c, _n, _l, fn) => fn(),
    swapPass: async (_c, o) => { calls.push(['swap', o.pass, o.freeze.on, o.flip, o.diagArms.join('+')]); return { schema: 'x', captures: {}, freeze: o.freeze }; },
    zoneCapture: async (_c, arm, o) => { calls.push(['zone', arm.id, o.freeze.on, o.align]); return { layout: 4, paint: 9, accentStart: 'idle', accentChanges: 1, align: o.align, drew: true }; },
  };
  return { calls, swap, ctx, deps, base: { passes: 2, clock: 'pinned', settleMs: 1, step: 50, framesPerStep: 2, log: () => {} } };
}

test('the freeze session runs both states of both arms in every pass, with diagnostics on both arms, then the zone scroll', async () => {
  const { calls, swap, ctx, deps, base } = stubs();
  const res = await freezeSession(ctx, { ...base, swap }, deps);
  assert.equal(res.schema, 'fw.webkit.lag/1');
  assert.equal(res.passes.length, 2);
  const swaps = calls.filter((c) => c[0] === 'swap');
  assert.deepEqual(swaps, [['swap', 1, false, false, 'crop+faithful'], ['swap', 1, true, false, 'crop+faithful'], ['swap', 2, true, true, 'crop+faithful'], ['swap', 2, false, true, 'crop+faithful']]);
  for (const p of res.passes) {
    assert.deepEqual([!!p.cost.swap, !!p.cost.swapFrozen, p.cost.zone.free.length, p.cost.zone.frozen.length], [true, true, 2, 2]);
    assert.deepEqual(p.cost.zone.free.map((z) => z.align).sort(), [false, true]);
    assert.ok(p.cost.zone.frozen.every((z) => z.job.pass >= 1));
  }
  assert.ok(calls.filter((c) => c[0] === 'zone').every((c) => c[1] === 'crop'));
});

test('the freeze session needs the swap setup, and a zone failure is recorded without losing the pass', async () => {
  const { ctx, deps, base, swap } = stubs();
  await assert.rejects(freezeSession(ctx, { ...base, swap: null }, deps), /needs the swap setup/);
  const bad = { ...deps, zoneCapture: async () => { throw new Error('marks missing'); } };
  const res = await freezeSession(ctx, { ...base, passes: 1, swap }, bad);
  assert.equal(res.passes.length, 1);
  assert.equal(res.failed.length, 4);
  assert.match(res.failed[0], /pass 1 zone free: marks missing/);
});
