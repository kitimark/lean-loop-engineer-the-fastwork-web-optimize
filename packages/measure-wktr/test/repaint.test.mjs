// The pure part of the invisible-paint lane: layer-tree text parser, swipe schedule, frame facts and the reduction.
import test from 'node:test';
import assert from 'node:assert/strict';
import { keepDirty, parseLayers, swipeSchedule, zoneOf, frameFacts, frameCounts, reduceRun, sumTables, parseRepaint, buildRepaintRun, ZONES, ARMS } from '../src/repaint.mjs';
import { repaintHarnessSource } from '../src/repaint-page.mjs';

// The shape GraphicsLayer::dumpLayer / dumpProperties / GraphicsLayerCA::dumpAdditionalProperties print (GraphicsLayer.cpp:910-1112, GraphicsLayerCA.cpp:4759-4785 @862f17d).
const TEXT = `(repaint rects
  (rect 0 56 402 40)
  (rect 10 300 80 20)
)
(GraphicsLayer
  (bounds 402 874)
  (usingTiledLayer 1)
  (clips 1)
  (visible rect 0, 100 402 x 874)
  (coverage rect 0, 100 402 x 1386)
  (intersects coverage rect 1)
  (contentsScale 3)
  (tile cache coverage 0, 100 402 x 1386)
  (children 2
    (GraphicsLayer
      (position 0 20)
      (bounds 402 60)
      (opacity 0.5)
      (transform [1 0 0 0] [0 1 0 0] [0 0 1 0] [0 0 0 1])
      (visible rect 0, 0 402 x 60)
      (coverage rect 0, 0 402 x 60)
      (contentsScale 3)
      (repaint rects
        (rect 0 0 402 60)
      )
    )
    (GraphicsLayer
      (bounds 100 100)
      (contentsVisible 0)
      (children 1
        (GraphicsLayer
          (bounds 50 50)
          (repaint rects
            (rect 0 0 50 50)
            (rect 0 0 0 0)
          )
        )
      )
    )
  )
)
`;

test('parseLayers: view rects, flattened layers, properties and depth', () => {
  const t = parseLayers(TEXT);
  assert.deepEqual(t.view, [[0, 56, 402, 40], [10, 300, 80, 20]]);
  assert.equal(t.nodes.length, 4);
  assert.deepEqual(t.nodes.map((n) => [n.i, n.p, n.d]), [[0, -1, 0], [1, 0, 1], [2, 0, 1], [3, 2, 2]]);
  const [root, a, b, c] = t.nodes;
  assert.deepEqual([root.b, root.tiled, root.clips, root.vis, root.cov, root.tcov, root.icov, root.scale], [[402, 874], 1, 1, [0, 100, 402, 874], [0, 100, 402, 1386], [0, 100, 402, 1386], 1, 3]);
  assert.deepEqual([a.pos, a.op, a.tr, a.rep], [[0, 20], 0.5, 1, [[0, 0, 402, 60]]]);
  assert.equal(b.cv, 0);
  assert.deepEqual(c.rep, [[0, 0, 50, 50], [0, 0, 0, 0]]);
});

test('parseLayers: hidden is inherited from the ancestors', () => {
  const t = parseLayers(TEXT);
  assert.deepEqual(t.nodes.map((n) => n.h), [0, 0, 1, 1]);
  assert.equal(parseLayers('(GraphicsLayer\n  (opacity 0)\n  (children 1\n    (GraphicsLayer\n      (bounds 1 1)\n    )\n  )\n)\n').nodes[1].h, 1);
});

test('parseLayers: an empty dump and a dump without repaint rects', () => {
  assert.deepEqual(parseLayers(''), { view: [], nodes: [] });
  const t = parseLayers('(GraphicsLayer\n  (bounds 10 10)\n)\n');
  assert.deepEqual([t.view.length, t.nodes[0].rep.length], [0, 0]);
});

test('parseLayers survives toString (the page embeds it)', () => {
  const f = new Function(`return (${parseLayers.toString()})`)();
  assert.deepEqual(f(TEXT), parseLayers(TEXT));
});

test('swipeSchedule: rest, strokes of 78 moves of 10 px with 2 gap frames, tail', () => {
  const ys = swipeSchedule(2000);
  assert.deepEqual(ys.slice(0, 10), Array(10).fill(0));
  assert.deepEqual(ys.slice(10, 13), [10, 20, 30]);
  assert.equal(ys[10 + 77], 780);
  assert.deepEqual(ys.slice(10 + 78, 10 + 80), [780, 780]);
  assert.equal(ys[10 + 80], 790);
  assert.deepEqual(ys.slice(-30), Array(30).fill(2000));
  assert.equal(Math.max(...ys), 2000);
  assert.ok(ys.every((y, i) => i === 0 || y >= ys[i - 1]));
  assert.deepEqual(swipeSchedule(0), Array(40).fill(0));
  assert.equal(swipeSchedule(5, { rest: 0, tail: 0 }).join(), '5');
});

test('zoneOf: hero in the first two viewports, finish in the last, else rest', () => {
  assert.equal(zoneOf(800, 10000, 0), 'hero');
  assert.equal(zoneOf(800, 10000, 1599), 'hero');
  assert.equal(zoneOf(800, 10000, 1600), 'rest');
  assert.equal(zoneOf(800, 10000, 9201), 'finish');
  assert.equal(zoneOf(800, 10000, 9200), 'rest');
  assert.equal(zoneOf(800, 1000, 100), 'hero');
});

const META = { innerWidth: 402, innerHeight: 874, maxY: 5000, els: [{ d: 'section#hero', p: 'hero' }, { d: 'div.blob', p: 'pain' }] };
const FR = {
  f: 0, y: 100, sy: 100,
  view: [{ r: [0, 56, 402, 40], e: 0, h: 0, c: 'scroll', p: 'hero' }, { r: [0, 2000, 10, 10], e: 1, h: 0, c: 'anim:pulse', p: 'pain' }, { r: [0, 0, 0, 5], e: -1, h: 0, c: 'scroll', p: 'other' }, { r: [0, 10, 5, 5], e: 1, h: 1, c: 'js-anim', p: 'pain' }],
  rootCov: [0, 100, 402, 1386],
  L: [{ i: 2, r: [[0, 110, 50, 20]], v: [0, 100, 50, 50], c: [0, 100, 50, 300], b: [50, 400], h: 0, t: 1, e: 1, k: 'trans:opacity' }, { i: 3, r: [[0, 200, 50, 50]], v: [0, 0, 50, 50], c: [0, 0, 50, 300], b: [50, 400], h: 0, t: 1, e: 1, k: 'scroll' }],
  rs: [[4, 100, 60, 100, 70, 0, 0], [5, 100, 60, 100, 70, 1, 0], [6, 10, 10, 10, 10, 0, 0]],
};

test('frameFacts: classes of view and layer rects, resizes', () => {
  const f = frameFacts(FR, META);
  assert.deepEqual(f.rects.map((r) => r.cls), ['visible', 'beyond-margin', 'zero-area', 'hidden', 'visible', 'prepaint-margin']);
  assert.deepEqual(f.rects.map((r) => r.part), ['hero', 'pain', 'other', 'pain', 'pain', 'pain']);
  assert.deepEqual(f.rects.map((r) => r.waste), [0, 100, 0, 25, 0, 2500]);
  assert.deepEqual(f.rects[1].cause, 'anim:pulse');
  assert.deepEqual(f.resizes.map((z) => z.area), [100 * 70, 0, 0]);
  assert.deepEqual(f.resizes[0], { i: 4, el: 'section#hero', part: 'hero', old: [100, 60], new: [100, 70], tiled: false, area: 7000 });
});

test('keepDirty: repeats and held rects are dropped, the first kept item stays on a merge', () => {
  const R = (x, y, w, h, n) => ({ rect: { x, y, w, h }, n });
  assert.deepEqual(keepDirty([R(0, 0, 10, 10, 'a'), R(0, 0, 10, 10, 'b'), R(2, 2, 3, 3, 'c'), R(20, 0, 5, 5, 'd')]).map((k) => k.n), ['a', 'd']);
  assert.deepEqual(keepDirty([R(2, 2, 3, 3, 'c'), R(0, 0, 10, 10, 'a')]).map((k) => k.n), ['c', 'a']);
  const many = Array.from({ length: 34 }, (_, i) => R(2 * i, 0, 1, 1, `r${i}`));
  const kept = keepDirty(many);
  assert.equal(kept.length, 32);
  assert.equal(kept[0].n, 'r0');
  assert.deepEqual(kept[0].rect, { x: 0, y: 0, w: 67, h: 1 });
});

test('frameFacts: the engine drops repeated rects of a layer, calls keep the count before', () => {
  const rep = Array(5).fill([416, 452, 18, 314]);
  const f = frameFacts({ ...FR, view: [{ r: [-1, 10, 1, 1], e: -1, h: 0, cl: 1, c: 'scroll', p: 'platform' }, { r: [-1, 10, 1, 1], e: -1, h: 0, cl: 1, c: 'scroll', p: 'platform' }], L: [{ i: 2, r: rep, v: [0, 0, 402, 820], c: [0, 0, 402, 820], b: [434, 784], h: 0, t: 0, e: 1, k: 'scroll' }], rs: [] }, META);
  assert.equal(f.calls, 7);
  assert.deepEqual(f.rects.map((r) => [r.src, r.cls]), [['view', 'clipped-out'], ['layer', 'beyond-margin']]);
  assert.equal(frameCounts(f).trackedCalls, 7);
  assert.equal(frameCounts(f).paintRects, 2);
});

test('frameCounts: integers per class, wasted area and re-raster', () => {
  const c = frameCounts(frameFacts(FR, META));
  assert.equal(c.paintRects, 6);
  assert.equal(c.rects_visible, 2);
  assert.equal(c.rects_beyond_margin + c.rects_prepaint_margin + c.rects_zero_area + c.rects_hidden + c.rects_covered + c.rects_clipped_out + c.rects_noop, 4);
  assert.equal(c.wasteArea, 2625);
  assert.equal(c.resizedLayers, 1);
  assert.equal(c.reRasterArea, 7000);
  assert.ok(Object.values(c).every(Number.isInteger));
});

test('reduceRun: frames per zone, part x zone cells, sums', () => {
  const fr = (f, y) => ({ ...FR, f, y, sy: y });
  const run = { meta: { ...META, maxY: 5000 }, frames: [fr(0, 0), fr(1, 2000), fr(2, 2000), fr(3, 4500)] };
  const red = reduceRun(run);
  assert.deepEqual(red.frames, { hero: 1, rest: 2, finish: 1 });
  assert.deepEqual(ZONES.map((z) => red.byZone[z].map((x) => x.n)), [[0], [0, 1], [0]]);
  assert.ok(red.byZone.rest[0].counts.paintRects === 6 && red.byZone.rest[0].phase === 'scroll');
  const cell = red.table.find((c) => c.zone === 'rest' && c.part === 'pain');
  assert.equal(cell.rects, 2 * 4);
  assert.equal(cell.byClass['beyond-margin'].n, 2);
  assert.equal(cell.causes['anim:pulse'], 2);
  assert.deepEqual(cell.reRaster, { layers: 0, area: 0 });
  const hero = red.table.find((c) => c.zone === 'rest' && c.part === 'hero');
  assert.deepEqual(hero.reRaster, { layers: 2, area: 14000 });
  const sum = sumTables([red.table, red.table]);
  assert.equal(sum.find((c) => c.zone === 'rest' && c.part === 'pain').rects, 16);
  assert.equal(sum.find((c) => c.zone === 'rest' && c.part === 'pain').causes['anim:pulse'], 4);
});

test('parseRepaint and buildRepaintRun', () => {
  const lines = [
    'CONSOLE MESSAGE: line 3: FWWKTR probe {"candidates":4}',
    `CONSOLE MESSAGE: FWWKTR rp ${JSON.stringify({ ...FR, f: 0 })}`,
    `FWWKTR rp ${JSON.stringify({ ...FR, f: 1 })}`,
    `FWWKTR meta ${JSON.stringify({ ...META, frames: 2 })}`,
    `FWWKTR els ${JSON.stringify(META.els)}`,
    'noise', 'FWWKTR done {}',
  ].join('\n');
  const p = parseRepaint(lines);
  assert.equal(p.frames.length, 2);
  const run = buildRepaintRun(p);
  assert.equal(run.meta.els.length, 2);
  assert.deepEqual(run.meta.probe, { candidates: 4 });
  assert.throws(() => buildRepaintRun(parseRepaint('FWWKTR error {"message":"x"}')), /page reported an error/);
  assert.throws(() => buildRepaintRun(parseRepaint(lines.replace('FWWKTR done {}', ''))), /incomplete/);
  assert.throws(() => buildRepaintRun({ ...p, meta: { ...p.meta, frames: 3 } }), /expected 3/);
});

test('arms: the snapshot, the rewrite default and the v2-proved preset', () => {
  assert.deepEqual(Object.keys(ARMS), ['orig', 'rewrite', 'v2']);
  assert.equal(ARMS.v2.search, '?preset=v2-proved');
});

test('the page script is syntactically valid with all its slots filled', () => {
  const s = repaintHarnessSource({ settleMs: 10, maxProbe: 3, maxFrames: 5 });
  assert.doesNotThrow(() => new Function(s));
  assert.ok(!/__[A-Z]+__/.test(s.replace(/__fw\w*|__wk\w*/g, '')));
  assert.match(s, /"maxFrames":5/);
  assert.match(s, /layerTreeAsText/);
});
