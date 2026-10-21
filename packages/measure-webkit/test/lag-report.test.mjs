// The lag report joins records to boxes and ranks counters (reduce.mjs is the twin of Fw.Measure.WebKitLag, lag-reduce.test.mjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import { clipRect, clipsPerStep, scrollSteps, stepRows, analyzeArm, reportMd, COLUMNS, MORPH_PHASES } from '../src/lag/report.mjs';
import { fillBlock, blockOf, BEGIN, END } from '../src/lag/note.mjs';
import { MORPH_FRAMES, scanSteps } from '../src/lag/probe.mjs';
import { COUNT_TYPES, reduceSteps } from '../src/reduce.mjs';

const quad = (x0, y0, x1, y1) => [x0, y0, x1, y0, x1, y1, x0, y1];
const info = { vw: 100, vh: 100, maxY: 1000 };

/** n steps, 1 s apart; step k holds the paint rows `paints[k]` (clip quads) and `extra[k]` Layout rows. */
function run(n, paints, extra = () => 0) {
  const rows = [], marks = [];
  for (let k = 0; k < n; k++) {
    marks.push(k);
    rows.push(['TimeStamp', k, null, `wk:s${k}`]);
    for (const q of paints(k)) rows.push(['Paint', k + 0.5, null, q]);
    for (let i = 0; i < extra(k); i++) rows.push(['Layout', k + 0.6, null, null]);
  }
  rows.push(['TimeStamp', n, null, 'wk:end']);
  return { rows, marks, endTime: n };
}

const boxes = [{ name: 'hero-deck', rect: [0, 0, 400, 400] }, { name: 'hero', rect: [0, 0, 400, 1600] }, { name: 'platform', rect: [0, 2000, 400, 4000] }];

/** `layoutA` Layout rows per step in region A (the first three steps), so two sessions can differ. */
function session(layoutA = 4) {
  const ys = [0, 50, 100, 150, 300, 500, 800, 900, 1000];
  const r = run(ys.length, (k) => (k < 3 ? [quad(0, ys[k], 90, ys[k] + 90)] : [quad(0, 500 + ys[k], 10, 520 + ys[k])]), (k) => (k < 3 ? layoutA : 1));
  const scroll = { info, ys, marks: r.marks, endTime: r.endTime, records: r.rows, reduced: reduceSteps(r.rows, r.marks, r.endTime) };
  const n = MORPH_FRAMES.idle + MORPH_FRAMES.open + MORPH_FRAMES.close;
  const m = run(n, (k) => (k >= MORPH_FRAMES.idle ? [quad(0, 500, 12, 515)] : []), (k) => (k >= MORPH_FRAMES.idle ? 3 : 0));
  const morph = { info, marks: m.marks, endTime: m.endTime, records: m.rows, reduced: reduceSteps(m.rows, m.marks, m.endTime), taken: [true, true], scrollTo: 7, before: { morph: '0' }, after: { morph: '0' }, platform: null };
  const geometry = {
    info, ys, census: [{ scrollY: 0, layerCount: 3, memoryBytes: 1e6, filterLayers: [] }],
    scroll: ys.map(() => ({ boxes, filters: [{ kind: 'backdrop', radius: 8, rect: [0, 0, 100, 100], part: 'hero', tag: 'div' }] })),
    morph: { before: { morph: '0' }, after: { morph: '0' }, samples: Array.from({ length: n }, () => ({ boxes, filters: [] })) },
  };
  return { geometry, passes: [{ scroll, morph }, { scroll, morph }] };
}

test('clipRect is the bounding box in quarter px', () => {
  assert.deepEqual(clipRect(quad(1, 2, 3.25, 5)), [4, 8, 13, 20]);
});

test('clips are joined to steps by the step marks', () => {
  const s = session();
  const clips = clipsPerStep(s.passes[0].scroll);
  assert.equal(clips.length, s.passes[0].scroll.ys.length);
  assert.deepEqual(clips[0], [[0, 0, 360, 360]]);
  assert.deepEqual(clips[4], [[0, 3200, 40, 3280]]);
  // the quad is in document coordinates: the scroll position of the step moves it into the viewport
  const inView = clipsPerStep(s.passes[0].scroll, s.passes[0].scroll.ys);
  assert.deepEqual(inView[4], [[0, 2000, 40, 2080]]);
  assert.deepEqual(inView[2], [[0, 0, 360, 360]]);
});

test('step rows carry the counts, the extra record types and the durations from the raw records', () => {
  const rows = [['TimeStamp', 0, null, 'wk:s0'], ['Layout', 0.1, 0.3, null], ['RequestAnimationFrame', 0.2, null, null], ['Paint', 0.4, 0.45, quad(0, 0, 10, 10)], ['TimeStamp', 1, null, 'wk:end']];
  const [row] = stepRows({ records: rows, marks: [0], endTime: 1, reduced: reduceSteps(rows, [0], 1) });
  const at = (n) => row[COLUMNS.indexOf(n)];
  assert.equal(at('Layout'), 1);
  assert.equal(at('RequestAnimationFrame'), 1);
  assert.equal(at('LayoutUs'), 200000);
  assert.equal(at('PaintUs'), 50000);
  assert.equal(at('paintArea'), 100);
  assert.equal(COLUMNS.length, COUNT_TYPES.length + 3 + 5 + 1);
});

test('region A is ranked by ratio to the calm baseline; its paints go to the smallest covering part', () => {
  const a = analyzeArm([session()]);
  const layout = a.scroll.A.table.rows.find((r) => r.name === 'Layout');
  assert.equal(layout.perFrame, 4);
  assert.equal(layout.baseFrame, 1);
  assert.deepEqual(layout.ratio, [4, 1]);
  const ranks = a.scroll.A.table.rows.filter((r) => r.rank).sort((x, y) => x.rank - y.rank).map((r) => r.ratio[0] / r.ratio[1]);
  assert.deepEqual(ranks, [...ranks].sort((x, y) => y - x));
  assert.deepEqual(a.scroll.A.parts, [{ name: 'hero', perPass: [16200, 16200], mean: 16200, share: 1 }]);
  assert.equal(a.scroll.A.top[0].part, 'hero-deck');
});

test('morph phases are ranked against the calm baseline and shown against the idle page tail', () => {
  const m = analyzeArm([session()]).morph;
  const open = m.phases.open;
  const layout = open.table.rows.find((r) => r.name === 'Layout');
  assert.equal(layout.perFrame, 3);
  assert.equal(layout.ratio[0] / layout.ratio[1], 3 / (1 / 2));
  assert.equal(open.tableIdle.rows.find((r) => r.name === 'Layout').ratio, null);
  assert.ok(open.tableIdle.unranked.includes('Layout'));
  assert.equal(m.idle.frames, MORPH_FRAMES.idle);
  assert.deepEqual(MORPH_PHASES.close, [70, 130]);
});

test('an arm difference needs separated per-pass ranges', () => {
  const same = reportMd([['x', analyzeArm([session(4)])], ['y', analyzeArm([session(4)])]]);
  assert.ok(same.includes('no difference shown (ranges overlap)'));
  assert.ok(!same.includes('faithful lower') && !same.includes('faithful higher'));
  const lower = reportMd([['x', analyzeArm([session(8)])], ['y', analyzeArm([session(2)])]]);
  const row = lower.split('\n').find((l) => l.startsWith('| Layout | 8.00 / 2.00'));
  assert.ok(row?.endsWith('| faithful lower |'), row);
});

test('the markdown has a section per region and a layer census', () => {
  const md = reportMd([['x', analyzeArm([session()])]]);
  for (const h of ['Region A (scroll)', 'Region B (scroll)', 'Region B morph, open', 'Region B morph, close', 'Idle page tail', 'Layer census', 'Top 5 steps of Region A']) assert.ok(md.includes(h), h);
});

test('a geometry load of another height joins each step to the nearest geometry y', () => {
  const s = session();
  const g = s.geometry, ys = g.ys.slice(0, -1);
  const shorter = { ...s, geometry: { ...g, ys, scroll: g.scroll.slice(0, -1), info: { ...info, maxY: 900 } } };
  const steps = scrollSteps(shorter, shorter.passes[0]);
  assert.equal(steps.length, s.passes[0].scroll.ys.length);
  assert.equal(steps.at(-1).boxes, shorter.geometry.scroll.at(-1).boxes);
  assert.ok(analyzeArm([shorter]).scroll.A.stepsPerPass > 0);
});

test('a session that stopped early still counts its completed runs', () => {
  const s = session();
  const partial = { ...s, passes: [s.passes[0], { scroll: s.passes[1].scroll }], failed: ['pass 2 morph: timed out'] };
  const a = analyzeArm([partial]);
  assert.equal(a.scrollPasses, 2);
  assert.equal(a.morph.passes, 1);
  const md = reportMd([['x', a]]);
  assert.ok(md.includes('2 scroll passes, 1 morph passes'));
  assert.ok(md.includes('stopped early: session 1: pass 2 morph: timed out'));
});

test('the filter scan covers every step of A and B and every eighth of the rest, and each sample says so', () => {
  const ys = [0, 50, 100, 150, 300, 500, 800, 900, 1000];
  assert.deepEqual(scanSteps(ys, 100, 1000), [0, 1, 8]);
});

test('the calm filter average is over the scanned steps only, and says how many', () => {
  const s = session();
  s.geometry.scroll.forEach((x, k) => { x.scanned = k % 2 === 0; });
  const md = reportMd([['x', analyzeArm([s])]]);
  assert.match(md, /\| calm \| x \| \d+\/\d+ \|/);
});

test('the note block is replaced in place and nothing else changes', () => {
  const note = `before\n${BEGIN}\nold\n${END}\nafter\n`;
  const out = fillBlock(note, 'NEW');
  assert.equal(blockOf(out), 'NEW');
  assert.ok(out.startsWith('before\n') && out.endsWith(`${END}\nafter\n`));
  assert.equal(fillBlock(out, 'NEW'), out);
  assert.throws(() => fillBlock('no markers', 'x'));
});
