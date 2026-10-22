// Layer census over CDP at pinned scroll offsets, taken after the profile and the trace so no count is touched.
// CONFIRMED (devtools-protocol 0.0.1696802): `LayerTree.layerTreeDidChange {layers}` carries Layer {layerId, backendNodeId?, offsetX,
// offsetY, width, height, paintCount, ...}; `LayerTree.compositingReasons(layerId)` returns `compositingReasonIds`. The offsets are
// parent-relative and there is no backing-store size, so `boundsU` is the layer's own box and `memory` is null; both arms are read the
// same way. INFERRED (Chromium source not read): the tree is sent on `enable` and after the next frame, so the collector pumps frames
// and waits, and a sample that never gets a tree is recorded as an error, never as an empty page.
// The two page-side strings below are byte copies of packages/measure-webkit/src/census.mjs (test/census.test.mjs compares them).
import { setTimeout as sleep } from 'node:timers/promises';

/** Page side, run on a layer's node: its description (the layer `name`), `data-fw`, `data-fw-layer` and viewport origin in micro CSS px. */
export const INFO_FN = `function () {
  if (this.nodeType !== 1) return { name: this.nodeName, fw: null, layer: null, origin: null };
  const cls = typeof this.className === 'string' ? this.className : (this.className && this.className.baseVal) || '';
  const name = this.tagName.toLowerCase() + (this.id ? '#' + this.id : '') + (cls.trim() ? '.' + cls.trim().split(/\\s+/).slice(0, 2).join('.') : '');
  const r = this.getBoundingClientRect();
  return { name, fw: this.getAttribute('data-fw'), layer: this.getAttribute('data-fw-layer'), origin: [Math.round(r.left * 1e6), Math.round(r.top * 1e6)] };
}`;

/** Page side: the pixel ratio in thousandths and the `data-fw-layer` ids of the nodes that have a box now (one entry per node). */
export const RENDERED_EXPR = `JSON.stringify({ dprMilli: Math.round(devicePixelRatio * 1000), rendered: Array.from(document.querySelectorAll('[data-fw-layer]')).filter((e) => e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden').map((e) => e.getAttribute('data-fw-layer')).filter(Boolean) })`;

/** The pinned scroll offsets, as the WebKit census takes them (`max` = the last scroll offset). */
export const sampleYs = (maxScroll) => [0, 1500, 3000, 4500, maxScroll];

const micro = (v) => Math.round(Number(v) * 1e6);

/** A CDP layer with its node's info and reasons, in the census record shape of the WebKit collector. */
export function layerRecord(l, info, reasons) {
  const i = info ?? { name: l.backendNodeId ? '?' : '(no node)', fw: null, layer: null, origin: null };
  return {
    name: i.name, fw: i.fw ?? null, layer: i.layer ?? null, origin: i.origin ?? null,
    boundsU: [micro(l.offsetX ?? 0), micro(l.offsetY ?? 0), micro(l.width ?? 0), micro(l.height ?? 0)],
    reasons: [...(reasons ?? [])].sort(), memory: null, paintCount: l.paintCount ?? null,
  };
}

const layerSortKey = (l) => `${l.name}|${l.boundsU.join(',')}|${l.reasons.join(',')}`;

async function infoOf(c, backendNodeId) {
  if (!backendNodeId) return null;
  try {
    const o = await c.send('DOM.resolveNode', { backendNodeId, objectGroup: 'fw-census' });
    const v = await c.send('Runtime.callFunctionOn', { objectId: o.object.objectId, functionDeclaration: INFO_FN, returnByValue: true });
    return v.result?.value ?? null;
  } catch { return null; }
}

async function reasonsOf(c, layerId) {
  try {
    const r = await c.send('LayerTree.compositingReasons', { layerId });
    return r.compositingReasonIds ?? r.compositingReasons ?? [];
  } catch { return ['(gone)']; }
}

/**
 * One sample at scroll offset y: scroll, settle, enable LayerTree, wait for a tree, read reasons and node info, disable.
 * `ev(expr)` evaluates in the page, `pump()` renders one frame; neither may end the process.
 */
export async function sampleAt(c, { ev, pump, y, tries = 12, settleFrames = 3, waitMs = 40 }) {
  const rec = { requestedY: y, scrollY: null, dprMilli: null, rendered: [], layerCount: 0, layers: [] };
  let tree = null;
  const onTree = (e) => { tree = e.layers ?? []; };
  c.on('LayerTree.layerTreeDidChange', onTree);
  try {
    await ev(`window.scrollTo(0, ${Number(y)})`);
    for (let i = 0; i < settleFrames; i++) await pump();
    rec.scrollY = Math.round(await ev('scrollY'));
    const seen = JSON.parse(await ev(RENDERED_EXPR));
    rec.dprMilli = seen.dprMilli;
    rec.rendered = seen.rendered;
    await c.send('DOM.enable').catch(() => {});
    await c.send('LayerTree.enable');
    for (let i = 0; i < tries && tree === null; i++) { await pump(); if (tree === null) await sleep(waitMs); }
    if (tree === null) { rec.error = 'no LayerTree.layerTreeDidChange after enable'; return rec; }
    await pump(); // a later tree (the first one may predate the commit) replaces the first
    const layers = tree;
    for (const l of layers) rec.layers.push(layerRecord(l, await infoOf(c, l.backendNodeId), await reasonsOf(c, l.layerId)));
    rec.layers.sort((a, b) => (layerSortKey(a) < layerSortKey(b) ? -1 : layerSortKey(a) > layerSortKey(b) ? 1 : 0));
    rec.layerCount = rec.layers.length;
    return rec;
  } catch (e) {
    rec.error = String(e.message ?? e).slice(0, 300);
    return rec;
  } finally {
    c.off('LayerTree.layerTreeDidChange', onTree);
    await c.send('Runtime.releaseObjectGroup', { objectGroup: 'fw-census' }).catch(() => {});
    await c.send('LayerTree.disable').catch(() => {});
  }
}

/** The census record of a run (`meta.layerCensus`): the samples in order; every sample carries its own error when it could not be read. */
export async function collectCensus(c, { ev, pump, maxScroll, ys = sampleYs(maxScroll), ...opts }) {
  const samples = [];
  for (const y of ys) samples.push(await sampleAt(c, { ev, pump, y, ...opts }));
  return { schema: 'fw.layer-census/1', engine: 'chromium', samples };
}
