import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { takeCensus, INFO_FN as WK_INFO, RENDERED_EXPR as WK_RENDERED } from '../src/census.mjs';
import { INFO_FN as CR_INFO, RENDERED_EXPR as CR_RENDERED, sampleAt, collectCensus, layerRecord, sampleYs } from '../../measure-chromium/src/census.mjs';
import { checkPair } from '../src/census-check.mjs';
import { atTop, pinStates, resolveStates } from '../src/determinism.mjs';

test('both engines run byte-identical page-side code', () => {
  assert.equal(WK_INFO, CR_INFO);
  assert.equal(WK_RENDERED, CR_RENDERED);
});

test('page-side code reads the attributes and the origin, and keeps the old description', () => {
  const fn = new Function(`return (${WK_INFO});`)();
  const node = { nodeType: 1, tagName: 'DIV', id: 'x', className: 'a b c', getBoundingClientRect: () => ({ left: 0.333333, top: 12 }), getAttribute: (k) => ({ 'data-fw': 'hero', 'data-fw-layer': 'hero_copy' })[k] ?? null };
  assert.deepEqual(fn.call(node), { name: 'div#x.a.b', fw: 'hero', layer: 'hero_copy', origin: [333333, 12000000] });
  assert.deepEqual(fn.call({ nodeType: 9, nodeName: '#document' }), { name: '#document', fw: null, layer: null, origin: null });
});

function fakeWebKit(layers, infos, seen) {
  const log = [];
  return {
    log,
    enable: async (d) => { log.push(`enable ${d}`); },
    disable: async (d) => { log.push(`disable ${d}`); },
    evaluate: async (expr) => { assert.equal(expr, WK_RENDERED); return JSON.stringify(seen); },
    send: async (m, p) => {
      if (m === 'DOM.getDocument') return { root: { nodeId: 1 } };
      if (m === 'LayerTree.layersForNode') return { layers };
      if (m === 'LayerTree.reasonsForCompositingLayer') return { compositingReasons: { willChange: true, video: false } };
      if (m === 'DOM.resolveNode') return { object: { objectId: `o${p.nodeId}` } };
      if (m === 'Runtime.callFunctionOn') return { result: { value: infos[p.objectId] } };
      return {};
    },
  };
}

test('WebKit census keeps the old fields and adds identity, origin, micro bounds, pixel ratio and rendered ids', async () => {
  const layers = [
    { layerId: 'L1', nodeId: 10, bounds: { x: 0, y: 0, width: 390, height: 844 }, compositedBounds: { x: 0, y: 80, width: 390, height: 300 }, paintCount: 2, memory: 4096 },
    { layerId: 'L2', nodeId: 11, bounds: { x: 0, y: 0, width: 10, height: 10 }, compositedBounds: { x: 0, y: 0, width: 10, height: 10 }, paintCount: 1, memory: 100 },
  ];
  const infos = { o10: { name: 'div.hero', fw: 'hero', layer: 'hero_copy', origin: [0, 80000000] }, o11: { name: 'span.glow', fw: null, layer: null, origin: [1, 2] } };
  const c = fakeWebKit(layers, infos, { dprMilli: 3000, rendered: ['hero_copy'] });
  const cen = await takeCensus(c, { paintWindowMs: 0 });
  assert.equal(cen.layerCount, 2);
  assert.equal(cen.dprMilli, 3000);
  assert.deepEqual(cen.rendered, ['hero_copy']);
  const [h, g] = cen.layers;
  assert.equal(h.name, 'div.hero');
  assert.equal(h.compositedBounds, '0,80,390,300');
  assert.deepEqual([h.fw, h.layer, h.origin, h.boundsU, h.memory, h.reasons], ['hero', 'hero_copy', [0, 80000000], [0, 80000000, 390000000, 300000000], 4096, ['willChange']]);
  assert.deepEqual([g.name, g.fw, g.layer], ['span.glow', null, null]);
  assert.equal(checkPair([{ ...cen, requestedY: 0 }], [{ ...cen, requestedY: 0 }], { composite: 'all' }).state, 'accepted');
});

test('WebKit census of a node that cannot be resolved keeps a name and no identity', async () => {
  const c = fakeWebKit([{ layerId: 'L1', nodeId: 0, compositedBounds: { x: 0, y: 0, width: 1, height: 1 }, paintCount: 0, memory: 0 }], {}, { dprMilli: 2000, rendered: [] });
  const cen = await takeCensus(c, { paintWindowMs: 0 });
  assert.deepEqual([cen.layers[0].name, cen.layers[0].fw, cen.layers[0].layer, cen.layers[0].origin], ['(no node)', null, null, null]);
});

class FakeCdp extends EventEmitter {
  constructor({ tree, delay = 0, infos = {}, reasons = {} }) { super(); Object.assign(this, { tree, delay, infos, reasons, calls: [], pumps: 0, enabled: false }); }
  async send(m, p) {
    this.calls.push(m);
    if (m === 'LayerTree.enable') { this.enabled = true; return {}; }
    if (m === 'LayerTree.disable') { this.enabled = false; return {}; }
    if (m === 'LayerTree.compositingReasons') return { compositingReasonIds: this.reasons[p.layerId] ?? [], compositingReasons: ['ignored'] };
    if (m === 'DOM.resolveNode') return { object: { objectId: `o${p.backendNodeId}` } };
    if (m === 'Runtime.callFunctionOn') return { result: { value: this.infos[p.objectId] } };
    return {};
  }
}
const fakeEnv = (c, { y = 0 } = {}) => ({
  exprs: (c.exprs = []),
  ev: async (e) => (c.exprs.push(e), e === RENDERED_CR ? JSON.stringify({ dprMilli: 3000, rendered: ['hero_copy'] }) : e === 'scrollY' ? y : null),
  pump: async () => { c.pumps++; if (c.enabled && c.pumps > c.delay) c.emit('LayerTree.layerTreeDidChange', { layers: c.tree }); },
});
const RENDERED_CR = CR_RENDERED;

test('Chromium sample normalises layers to micro px, ids to reasons, nodes to identity and sorts them', async () => {
  const tree = [
    { layerId: '2', backendNodeId: 22, offsetX: 0.5, offsetY: 80, width: 390, height: 300.25, paintCount: 3 },
    { layerId: '1', offsetX: 0, offsetY: 0, width: 390, height: 844, paintCount: 1 },
  ];
  const c = new FakeCdp({ tree, infos: { o22: { name: 'div.hero', fw: 'hero', layer: 'hero_copy', origin: [0, 80000000] } }, reasons: { 2: ['willChange', 'activeTransformAnimation'] } });
  const rec = await sampleAt(c, { ...fakeEnv(c), y: 1500 });
  assert.equal(rec.error, undefined);
  assert.deepEqual([rec.requestedY, rec.scrollY, rec.dprMilli, rec.rendered, rec.layerCount], [1500, 0, 3000, ['hero_copy'], 2]);
  assert.deepEqual(rec.layers.map((l) => l.name), ['(no node)', 'div.hero']);
  const hero = rec.layers[1];
  assert.deepEqual([hero.fw, hero.layer, hero.origin, hero.boundsU, hero.reasons, hero.memory], ['hero', 'hero_copy', [0, 80000000], [500000, 80000000, 390000000, 300250000], ['activeTransformAnimation', 'willChange'], null]);
  assert.equal(c.listenerCount('LayerTree.layerTreeDidChange'), 0);
  assert.equal(c.calls.at(-1), 'LayerTree.disable');
  assert.ok(c.exprs.some((e) => e.includes('top: 1500') && e.includes("behavior: 'instant'")), 'the scroll is instant (a smooth-scrolling page would still be moving)');
});

test('Chromium sample waits for the tree across frames, and records an error when it never comes', async () => {
  const slow = new FakeCdp({ tree: [], delay: 6 });
  const ok = await sampleAt(slow, { ...fakeEnv(slow), y: 0 });
  assert.equal(ok.error, undefined);
  assert.ok(slow.pumps > 6);
  const never = new FakeCdp({ tree: [], delay: 1e9 });
  const bad = await sampleAt(never, { ...fakeEnv(never), y: 0, tries: 3, waitMs: 1 });
  assert.match(bad.error, /no LayerTree/);
  assert.equal(bad.layerCount, 0);
  assert.equal(never.listenerCount('LayerTree.layerTreeDidChange'), 0);
});

test('Chromium sample turns a thrown protocol error into an error record, not an exception', async () => {
  const c = new FakeCdp({ tree: [] });
  c.send = async () => { throw new Error('Protocol error: LayerTree.enable'); };
  const rec = await sampleAt(c, { ev: async (e) => (e === RENDERED_CR ? JSON.stringify({ dprMilli: 3000, rendered: [] }) : 0), pump: async () => {}, y: 0 });
  assert.match(rec.error, /Protocol error/);
});

test('Chromium census takes the five pinned offsets and its records go through the check like WebKit ones', async () => {
  assert.deepEqual(sampleYs(5200), [0, 1500, 3000, 4500, 5200]);
  const tree = [{ layerId: '1', backendNodeId: 5, offsetX: 0, offsetY: 0, width: 390, height: 844 }];
  const mk = () => new FakeCdp({ tree, infos: { o5: { name: 'html', fw: null, layer: null, origin: [0, 0] } } });
  const run = async () => { const c = mk(); return collectCensus(c, { ...fakeEnv(c), maxScroll: 5200 }); };
  const [r1, r2] = [await run(), await run()];
  assert.equal(r1.samples.length, 5);
  assert.equal(checkPair(r1.samples, r2.samples).state, 'accepted');
  r2.samples[3].layers.push(layerRecord({ offsetX: 1, offsetY: 2, width: 3, height: 4 }, { name: 'canvas', fw: null, layer: null, origin: null }, []));
  const v = checkPair(r1.samples, r2.samples);
  assert.deepEqual(v.refusals.map((r) => [r.code, r.y, r.box]), [['undeclared', 4500, 'canvas']]);
});

test('a pass scrolls to the top before its reload so the load does not restore a deep position', async () => {
  const calls = [];
  const c = { runAsync: async (src) => { calls.push(src); return 0; }, evaluate: async (e) => { calls.push(e); return 0; } };
  assert.equal(await atTop(c), 0);
  assert.match(calls[0], /top: 0, behavior: 'instant'/);
});

test('later passes read the offsets pass 1 resolved, not their own page height', () => {
  const first = { census: [0, 1500, 5231].map((requestedY) => ({ requestedY })) };
  assert.deepEqual(resolveStates(pinStates(first), 5267), [0, 1500, 5231]);
});
