// packages/measure-chromium/src/{trace,n0}.mjs (container-side copies of Lean specs) against fwcore on random inputs.
import { test, before, after } from 'node:test';
import fc from 'fast-check';
import { FwCore } from '../src/fwcore.mjs';
import { differential } from '../src/diff.mjs';
import { int } from '../src/arb.mjs';
import { snapshotCounts } from '../../measure-chromium/src/trace.mjs';
import { n0Windows, n0FrameCounts } from '../../measure-chromium/src/n0.mjs';

let core;
before(() => { core = new FwCore(); });
after(() => core.close());

const opt = (a) => fc.option(a, { nil: undefined });
const layer = fc.record({
  bounds: opt(fc.record({ width: int(0, 2000), height: int(0, 2000) }, { requiredKeys: [] })),
  draws_content: opt(fc.boolean()),
  tilings: opt(fc.array(fc.constant({}), { maxLength: 3 })),
  invalidation: opt(fc.array(int(0, 400), { maxLength: 10 })),
}, { requiredKeys: [] });
const tile = fc.record({
  content_rect: opt(fc.array(int(0, 600), { maxLength: 5 })),
  draw_info: opt(fc.record({ is_solid_color: opt(fc.boolean()) }, { requiredKeys: [] })),
}, { requiredKeys: [] });
const snapshot = fc.oneof({ weight: 1, arbitrary: fc.constant(null) }, { weight: 6, arbitrary: fc.record({
  active_tree: opt(fc.oneof(fc.constant(null), fc.record({ layers: opt(fc.oneof(fc.constant(null), fc.array(layer, { maxLength: 4 }))) }, { requiredKeys: [] }))),
  active_tiles: opt(fc.oneof(fc.constant(null), fc.array(tile, { maxLength: 5 }))),
  tile_manager_basic_state: opt(fc.oneof(fc.constant(null), fc.record({ tile_count: int(0, 500) }))),
}, { requiredKeys: [] }) });

test('measure.snapshotCounts', () => differential(core, {
  op: 'measure.snapshotCounts',
  arb: fc.record({ snapshot }),
  ts: ({ snapshot: s }) => ({ counts: snapshotCounts(s) }),
}));

// Frame times are non-decreasing (the Lean op refuses other input). Event times sit on frame times and on the +-1/1000
// tolerance edge, where an exact rational and a double can disagree.
const KINDS = ['cssom.sheet', 'cssom.insertRule', 'cssom.deleteRule', 'cssom.keyframes', 'adoptedStyleSheets', 'sheetNode.added', 'sheetNode.removed', 'sheetNode.text'];
const DELTAS = [-0.002, -0.0011, -0.001, -0.0009, 0, 0.0009, 0.001, 0.0011, 0.002];
const n0Input = fc.record({
  startVt: int(0, 300),
  dt: int(1, 20),
  gaps: fc.array(int(0, 30), { maxLength: 5 }),
}).chain(({ startVt, dt, gaps }) => {
  let t = startVt + dt;
  const frameVts = gaps.map((g) => { t += g; return t; });
  const anchors = [startVt, startVt - dt, ...frameVts, frameVts.length ? frameVts[0] - dt : startVt, frameVts.length ? frameVts[frameVts.length - 1] + dt : startVt + dt];
  const vt = fc.oneof(
    fc.tuple(fc.constantFrom(...anchors), fc.constantFrom(...DELTAS)).map(([a, d]) => Number((a + d).toFixed(4))),
    int(-5, 400));
  return fc.record({
    dt: fc.constant(dt), startVt: fc.constant(startVt), frameVts: fc.constant(frameVts),
    events: fc.array(fc.record({ kind: fc.constantFrom(...KINDS), vt }), { maxLength: 8 }),
  });
});

test('measure.n0Windows', () => differential(core, {
  op: 'measure.n0Windows',
  arb: n0Input,
  ts: ({ events, frameVts, startVt, dt }) => {
    const { win, perFrame } = n0Windows(events, frameVts, startVt, dt);
    const where = (e) => (win.load.includes(e) ? 'load' : win.preroll.includes(e) ? 'preroll' : win.after.includes(e) ? 'after' : perFrame.findIndex((l) => l.includes(e)));
    return { after: win.after.length, frames: perFrame.map(n0FrameCounts), load: win.load.length, preroll: win.preroll.length, windows: events.map(where) };
  },
}));
