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

/** The scroll positions of `nCalm` calm steps (vh 100, maxY 1000: calm is 200 to 800) between region A and region B. */
const positions = (nCalm) => [0, 50, 100, ...Array.from({ length: nCalm }, (_, i) => 250 + 10 * i), 900, 1000];

/** `layoutA` Layout rows per step in region A (the first three steps), so two sessions can differ; `idleLayouts` idle frames carry a Layout. */
function session(layoutA = 4, ys = [0, 50, 100, 150, 300, 500, 800, 900, 1000], idleLayouts = 0) {
  const r = run(ys.length, (k) => (k < 3 ? [quad(0, ys[k], 90, ys[k] + 90)] : [quad(0, 500 + ys[k], 10, 520 + ys[k])]), (k) => (k < 3 ? layoutA : 1));
  const scroll = { info, ys, marks: r.marks, endTime: r.endTime, records: r.rows, reduced: reduceSteps(r.rows, r.marks, r.endTime) };
  const n = MORPH_FRAMES.idle + MORPH_FRAMES.open + MORPH_FRAMES.close;
  const m = run(n, (k) => (k >= MORPH_FRAMES.idle ? [quad(0, 500, 12, 515)] : []), (k) => (k >= MORPH_FRAMES.idle ? 3 : k < idleLayouts ? 1 : 0));
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

test('a part that only the second arm has is still in the parts table', () => {
  const a = analyzeArm([session()]);
  const b = analyzeArm([session()]);
  b.scroll.A.parts.push({ name: 'pain', perPass: [5, 7], mean: 6e9, share: 0.1 });
  const row = reportMd([['x', a], ['y', b]]).split('\n').find((l) => l.startsWith('| pain |'));
  assert.ok(row?.includes('not in this arm') && row.endsWith('| not compared (part absent in one arm) |'), row);
});

const rowOf = (md, name) => md.split('\n').find((l) => l.startsWith(`| ${name} | `));

test('the rare flag is decided per arm: a rare faithful baseline alone is flagged and has no ratio verdict', () => {
  const o = analyzeArm([session(4, positions(20))]), f = analyzeArm([session(4, positions(8))]);
  const layout = (a) => a.scroll.A.table.rows.find((r) => r.name === 'Layout');
  assert.deepEqual(layout(o).basePass, [20, 20]);
  assert.deepEqual(layout(f).basePass, [8, 8]);
  assert.equal(layout(o).rare, false);
  assert.equal(layout(f).rare, true);
  const cells = rowOf(reportMd([['original', o], ['faithful', f]]), 'Layout').split(' | ');
  assert.ok(!cells[3].includes('(*)') && cells[5].includes('(*)'), cells.join(' | '));
  assert.equal(cells[7], 'not stated (rare baseline)');
  const calm = rowOf(reportMd([['original', o], ['faithful', analyzeArm([session(4, positions(20))])]]), 'Layout').split(' | ');
  assert.ok(!calm[3].includes('(*)') && !calm[5].includes('(*)') && calm[7] === 'no difference shown (ranges overlap)', calm.join(' | '));
});

test('the same calm baseline is flagged alike in the scroll and the morph tables', () => {
  for (const nCalm of [8, 20]) {
    const a = analyzeArm([session(4, positions(nCalm))]);
    const at = (t) => t.rows.find((r) => r.name === 'Layout');
    const scrollA = at(a.scroll.A.table), scrollB = at(a.scroll.B.table);
    for (const ph of ['open', 'close']) {
      assert.deepEqual(at(a.morph.phases[ph].table).basePass, scrollA.basePass);
      assert.equal(at(a.morph.phases[ph].table).rare, scrollA.rare);
    }
    assert.equal(scrollB.rare, scrollA.rare);
    assert.equal(scrollA.rare, nCalm === 8);
  }
});

test('durations and the paint area are never flagged, and the 10-frame idle baseline is flagged by the same rule', () => {
  const a = analyzeArm([session(4, positions(8), 5)]);
  const row = (t, n) => t.rows.find((r) => r.name === n);
  for (const n of ['LayoutUs', 'PaintUs', 'paintArea']) assert.equal(row(a.scroll.A.table, n).rare, false, n);
  const idle = row(a.morph.phases.open.tableIdle, 'Layout');
  assert.deepEqual(idle.basePass, [5, 5]);
  assert.equal(idle.rare, true);
  const md = reportMd([['x', a]]);
  assert.match(md, /- x: Layout x[\d.]+ \([\d.-]+\) \(\*\)/);
  assert.ok(md.includes('has fewer than 10 events'), 'the footnote is generated from rareMin');
});

test('a part that is zero in one arm says so, and parts beyond the table say how many', () => {
  const a = analyzeArm([session()]), b = analyzeArm([session()]);
  b.scroll.A.parts.push({ name: 'pain', perPass: [0, 0], mean: 0, share: 0 });
  a.scroll.A.parts.push({ name: 'pain', perPass: [3, 4], mean: 3.5, share: 0.1 });
  for (let i = 0; i < 11; i++) a.scroll.A.parts.push({ name: `extra${i}`, perPass: [1, 1], mean: 1, share: 0 });
  const md = reportMd([['x', a], ['y', b]]);
  assert.ok(rowOf(md, 'pain')?.endsWith('| not compared (zero in one arm) |'), rowOf(md, 'pain'));
  assert.match(md, /\n3 more parts not shown\n/);
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
