// The lag report joins records to boxes and ranks counters (reduce.mjs is the twin of Fw.Measure.WebKitLag, lag-reduce.test.mjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import { clipRect, clipsPerStep, analyzeScroll, analyzeMorph, armMd, COLUMNS, MORPH_PHASES } from '../src/lag/report.mjs';
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

function session() {
  const ys = [0, 50, 100, 150, 300, 500, 800, 900, 1000];
  const r = run(ys.length, (k) => (k < 3 ? [quad(0, ys[k], 90, ys[k] + 90)] : [quad(0, 500 + ys[k], 10, 520 + ys[k])]), (k) => (k < 3 ? 4 : 1));
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

test('region A is ranked by its excess over the calm baseline and its paints go to the smallest covering part', () => {
  const a = analyzeScroll([session()]);
  assert.deepEqual(a.A.table.ranked.slice(0, 2).map(([n]) => n), ['paintArea', 'Layout']);
  const layout = a.A.table.rows.find((r) => r.name === 'Layout');
  assert.equal(layout.perStep, 4);
  assert.equal(layout.baseline, 1);
  assert.deepEqual(a.A.paintAreaByPart, [['hero-deck', 24300]]);
  assert.deepEqual(a.A.paintAreaByCoarse, [['hero', 24300]]);
});

test('morph phases are ranked against the idle frames', () => {
  const m = analyzeMorph([session()]);
  const layout = m.open.table.rows.find((r) => r.name === 'Layout');
  assert.equal(layout.perStep, 3);
  assert.equal(layout.baseline, 0);
  assert.equal(layout.ratio, null);
  assert.deepEqual(m.open.paintCountByPart, [['platform', MORPH_FRAMES.open]]);
  assert.deepEqual(MORPH_PHASES.close, [70, 130]);
});

test('the markdown has a section per region', () => {
  const md = armMd('x', [session()]);
  for (const h of ['Region A (scroll)', 'Region B (scroll)', 'Region B morph, open', 'Region B morph, close', 'Layers']) assert.ok(md.includes(h), h);
  assert.equal(COLUMNS.length, COUNT_TYPES.length + 1);
});

test('the filter scan covers every step of A and B and every eighth of the rest', () => {
  const ys = [0, 50, 100, 150, 300, 500, 800, 900, 1000];
  assert.deepEqual(scanSteps(ys, 100, 1000), [0, 1, 2, 7, 8]);
});
