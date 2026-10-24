import test from 'node:test';
import assert from 'node:assert/strict';
import { flipIndex, motion, transitionsSeen, cadence, eventCounts, analyse, frameTable, spread, summarise, summaryText, SERIES, SEQUENCES, selectorsFor, variantCss, styleInit, VARIANTS } from '../src/trajectory/transitions.mjs';

const row = (t, nav, pad, w, an = []) => ({
  t, read: t, y: 0, lbl: null, earn: [800, 10, w, 40], lang: [900 - (w - 100), 10, 40, 40], act: [800, 10, 140, 40], nav,
  cs: { pl: `${pad}px`, pr: `${pad}px`, mw: '176px', op: '1', ne: '1', eo: '0', el: '1', tr: 'all' }, gap: '8px', an,
});

const snap = [row(0, '000', 24, 148), row(16, '000', 24, 148), row(100, '100', 0, 100), row(116, '100', 0, 100), row(132, '100', 0, 100)];
const ease = [row(0, '000', 24, 148), row(16, '000', 24, 148), row(100, '100', 24, 148, [['earn', 'padding-left', 7, 0, 'running']]),
  row(116, '100', 18, 136, [['earn', 'padding-left', 7, 16, 'running']]), row(132, '100', 9, 118, [['earn', 'padding-left', 7, 32, 'running']]),
  row(148, '100', 0, 100, [['earn', 'padding-left', 7, 48, 'running']])];

test('flipIndex: the first row whose nav flags differ from the first row; none without flags or without a change', () => {
  assert.equal(flipIndex(snap), 2);
  assert.equal(flipIndex(ease), 2);
  assert.equal(flipIndex([row(0, '000', 24, 148), row(16, '000', 24, 148)]), null);
  assert.equal(flipIndex([{ t: 0, earn: [0, 0, 1, 1] }, { t: 1, earn: [0, 0, 1, 1] }]), null);
  assert.equal(flipIndex([]), null);
});

test('motion: a snap is one jump with no frame between the values; an ease has frames between', () => {
  const a = motion(snap, 2, SERIES.padL);
  assert.deepEqual([a.start, a.end, a.maxJump, a.between, a.arriveMs, a.leaveMs], [24, 0, 24, 0, 0, 0]);
  const b = motion(ease, 2, SERIES.padL);
  assert.deepEqual([b.start, b.end, b.between, b.arriveMs, b.leaveMs, b.maxJump], [24, 0, 2, 48, 16, 9]);
  const wa = motion(snap, 2, SERIES.earnW);
  assert.equal(wa.change, -48);
  assert.equal(wa.maxJump, 48);
});

test('motion: no value before the flip, or a flip at the first row, has no motion', () => {
  assert.equal(motion(snap, 0, SERIES.padL), null);
  assert.equal(motion(snap, null, SERIES.padL), null);
  assert.equal(motion([{ t: 0 }, { t: 1 }], 1, SERIES.padL), null);
});

test('transitionsSeen: one animation per id, the frames it lived and the offset it first showed', () => {
  assert.deepEqual(transitionsSeen(ease, 2), { 'earn:padding-left': { animations: 1, frames: 4, firstMs: 0 } });
  assert.deepEqual(transitionsSeen(snap, 2), {});
  const restart = [row(0, '000', 1, 1, [['earn', 'max-width', 1, 0, 'running']]), row(10, '000', 1, 1, [['earn', 'max-width', 2, 0, 'running']])];
  assert.equal(transitionsSeen(restart, null)['earn:max-width'].animations, 2);
});

test('cadence and eventCounts', () => {
  assert.deepEqual(cadence([{ t: 0 }, { t: 16 }, { t: 33 }, { t: 80 }]), { frames: 4, medianMs: 17, long: 1 });
  assert.deepEqual(eventCounts([{ type: 'transitionrun', node: 'earn', prop: 'opacity' }, { type: 'transitionrun', node: 'earn', prop: 'opacity' }]), { 'transitionrun:earn:opacity': 2 });
});

test('analyse: the flip, the series and the transitions of a recording', () => {
  const a = analyse({ rows: snap, events: [] });
  assert.equal(a.flipFrame, 2);
  assert.equal(a.flipT, 100);
  assert.equal(a.series.padL.maxJump, 24);
  assert.deepEqual(a.transitions, {});
  const b = analyse({ rows: ease, events: [{ type: 'transitionrun', node: 'earn', prop: 'padding-left' }] });
  assert.equal(b.series.padL.between, 2);
  assert.equal(b.transitions['earn:padding-left'].animations, 1);
  assert.equal(b.events['transitionrun:earn:padding-left'], 1);
});

test('frameTable: header plus the rows around the flip; no flip, no table', () => {
  const t = frameTable(snap, 2, 1, 1);
  assert.equal(t.length, 4);
  assert.match(t[2], /^ {5}0 +0 +0/);
  assert.deepEqual(frameTable(snap, null), []);
});

test('spread: min, median and max over the repeats that have the value', () => {
  assert.deepEqual(spread([{ v: 1 }, { v: 3 }, { v: null }, { v: 2 }], (x) => x.v), { n: 3, min: 1, median: 2, max: 3 });
  assert.equal(spread([], (x) => x), null);
});

test('summarise: one cell per width, arm and sequence; the light page apart', () => {
  const seqs = (rows) => Object.fromEntries(SEQUENCES.map((s) => [s, { rows, events: [] }]));
  const head = { engine: 'playwright-webkit', version: 'v', reps: 2, runs: [
    { width: 1280, role: 'faithful', mode: 'full', rep: 0, identity: 'ok', sequences: seqs(snap) },
    { width: 1280, role: 'faithful', mode: 'full', rep: 1, identity: 'ok', sequences: seqs(snap) },
    { width: 1280, role: 'faithful', mode: 'light', rep: 2, identity: 'ok', sequences: seqs(snap.map(({ cs, an, nav, ...r }) => r)) },
  ] };
  const s = summarise(head);
  assert.equal(s.cells.length, SEQUENCES.length);
  const c = s.cells.find((x) => x.seq === 'hero-entry');
  assert.equal(c.full, 2);
  assert.equal(c.light, 1);
  assert.equal(c.series.padL.maxJump.median, 24);
  assert.deepEqual(c.transitions, {});
  assert.match(summaryText(head, s), /padL +change -24/);
});

test('variantCss: only the property list changes, important, per candidate; no variant adds nothing', () => {
  const sel = '[data-fw="nav-earn"]';
  assert.equal(variantCss(null, sel), null);
  assert.equal(variantCss('logical', sel), '[data-fw="nav-earn"] { transition-property: max-width, opacity, padding-inline-start, padding-inline-end !important; }');
  assert.match(variantCss('physical', sel), /padding-left, padding-right !important/);
  assert.match(variantCss('padding', sel), /opacity, padding !important/);
  assert.throws(() => variantCss('nope', sel), /unknown variant/);
  assert.deepEqual(Object.keys(VARIANTS), ['logical', 'physical', 'padding']);
});

test('styleInit: empty for no css; otherwise a script that carries the css as a JSON string', () => {
  assert.equal(styleInit(null), '');
  const s = styleInit('a { b: "c"; }');
  assert.match(s, /createElement\('style'\)/);
  assert.ok(s.includes(JSON.stringify('a { b: "c"; }')));
  new Function(s);
});

test('selectorsFor: both arms resolve earn, lang, actions and nav from the anchor registry', () => {
  for (const site of ['orig', 'rewrite']) {
    const sel = selectorsFor(site);
    for (const k of ['nav', 'actions', 'earn', 'lang', 'langBtn']) assert.equal(typeof sel[k], 'string', `${site} ${k}`);
  }
  assert.equal(selectorsFor('rewrite').earn, '[data-fw="nav-earn"]');
});
