// LayerTree census at a held scroll state while the page free-runs.
// Protocol (CONFIRMED: Source/JavaScriptCore/inspector/protocol/LayerTree.json): `layersForNode(nodeId)` with the
// document's node id lists every composited layer {layerId, nodeId, bounds, compositedBounds, paintCount, memory,
// pseudoElement...}; `reasonsForCompositingLayer(layerId)` returns the compositing-reason flags (29 booleans).
// `memory` is the backing-store estimate in bytes (RenderLayerBacking / GraphicsLayerCA backingStoreMemoryEstimate).
// Layer ids and node ids belong to one inspector session; they are kept for within-run deltas only and are left
// out of the canonical form that two runs are compared on.
//
// A census is taken OUTSIDE any timed window: layersForNode is not free (v1 safari-render-signals §2.5).
import { sleep } from './sim.mjs';
import { scrollHold } from './page.mjs';

export const INFO_FN = `function () {
  if (this.nodeType !== 1) return { name: this.nodeName, fw: null, layer: null, origin: null };
  const cls = typeof this.className === 'string' ? this.className : (this.className && this.className.baseVal) || '';
  const name = this.tagName.toLowerCase() + (this.id ? '#' + this.id : '') + (cls.trim() ? '.' + cls.trim().split(/\\s+/).slice(0, 2).join('.') : '');
  const r = this.getBoundingClientRect();
  return { name, fw: this.getAttribute('data-fw'), layer: this.getAttribute('data-fw-layer'), origin: [Math.round(r.left * 1e6), Math.round(r.top * 1e6)] };
}`;

export const RENDERED_EXPR = `JSON.stringify({ dprMilli: Math.round(devicePixelRatio * 1000), rendered: Array.from(document.querySelectorAll('[data-fw-layer]')).filter((e) => e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden').map((e) => e.getAttribute('data-fw-layer')).filter(Boolean) })`;

async function layersOf(c) {
  const doc = (await c.send('DOM.getDocument', { depth: 0 })).root.nodeId;
  return (await c.send('LayerTree.layersForNode', { nodeId: doc })).layers || [];
}

/** Reason flags of a layer; a layer torn down between the two calls answers with an error: ['(gone)']. */
async function reasonsOf(c, layerId) {
  try { return sortedKeys((await c.send('LayerTree.reasonsForCompositingLayer', { layerId })).compositingReasons); } catch (e) {
    if (/Missing render layer/i.test(e.message)) return ['(gone)'];
    throw e;
  }
}

const NO_INFO = { fw: null, layer: null, origin: null };

async function describe(c, nodeId) {
  if (!nodeId) return { name: '(no node)', ...NO_INFO };
  try {
    const o = await c.send('DOM.resolveNode', { nodeId, objectGroup: 'wk-census' });
    const v = await c.send('Runtime.callFunctionOn', { objectId: o.object.objectId, functionDeclaration: INFO_FN, returnByValue: true });
    return v.result?.value ?? { name: '?', ...NO_INFO };
  } catch { return { name: '?', ...NO_INFO }; }
}

const microRect = (key) => {
  const p = key ? key.split(',').map(Number) : [];
  return p.length === 4 && p.every(Number.isFinite) ? p.map((n) => Math.round(n * 1e6)) : null;
};

const sortedKeys = (o) => Object.keys(o || {}).filter((k) => o[k]).sort();
const rectKey = (r) => (r ? `${r.x},${r.y},${r.width},${r.height}` : '');

/**
 * Census at the current scroll state. Takes layers twice, `paintWindowMs` apart, to get the repaint count of each
 * layer in a fixed free-running interval (paintCount is cumulative since the layer's creation).
 */
export async function takeCensus(c, { paintWindowMs = 2000, withReasons = true, withNames = true } = {}) {
  await c.enable('Page');
  await c.enable('DOM').catch(() => {});
  await c.enable('LayerTree');
  const a = await layersOf(c);
  await sleep(paintWindowMs);
  const b = await layersOf(c);
  const paintBefore = new Map(a.map((l) => [l.layerId, l.paintCount]));
  const layers = [];
  for (const l of b) {
    const info = withNames ? await describe(c, l.nodeId) : { name: null, ...NO_INFO };
    const d = {
      name: info.name, fw: info.fw, layer: info.layer, origin: info.origin,
      pseudo: l.pseudoElement || null,
      bounds: rectKey(l.bounds), compositedBounds: rectKey(l.compositedBounds), boundsU: microRect(rectKey(l.compositedBounds)),
      memory: l.memory, paintCount: l.paintCount,
      paintDelta: paintBefore.has(l.layerId) ? l.paintCount - paintBefore.get(l.layerId) : null, // null: layer is new in the window
      reasons: withReasons ? await reasonsOf(c, l.layerId) : [],
      flags: ['isInShadowTree', 'isReflection', 'isGeneratedContent', 'isAnonymous'].filter((k) => l[k]),
      layerId: l.layerId, nodeId: l.nodeId,
    };
    layers.push(d);
  }
  await c.send('Runtime.releaseObjectGroup', { objectGroup: 'wk-census' }).catch(() => {});
  // leave no LayerTree/DOM tracking behind: a later reload and a timed window should not pay for it
  await c.disable('LayerTree');
  await c.disable('DOM');
  const seen = typeof c.evaluate === 'function' ? JSON.parse(await c.evaluate(RENDERED_EXPR)) : { dprMilli: null, rendered: [] };
  const reasonCounts = {};
  for (const l of layers) for (const r of l.reasons) reasonCounts[r] = (reasonCounts[r] || 0) + 1;
  const sum = (f) => layers.reduce((s, l) => s + f(l), 0);
  return {
    layerCount: layers.length,
    dprMilli: seen.dprMilli, rendered: seen.rendered,
    layersAtFirstRead: a.length,
    memoryBytes: sum((l) => l.memory),
    paintCountTotal: sum((l) => l.paintCount),
    paintDeltaTotal: sum((l) => l.paintDelta ?? 0),
    newLayersInWindow: layers.filter((l) => l.paintDelta === null).length,
    paintWindowMs,
    reasonCounts: Object.fromEntries(Object.entries(reasonCounts).sort(([x], [y]) => (x < y ? -1 : 1))),
    layers,
  };
}

/** Census at scroll offset y (instant scroll, hold, then census). */
export async function censusAt(c, y, { holdMs = 1500, ...opts } = {}) {
  const at = await scrollHold(c, y, { holdMs });
  const census = await takeCensus(c, opts);
  return { requestedY: y, scrollY: at, ...census };
}
