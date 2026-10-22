import { setTimeout as sleep } from 'node:timers/promises';

export const INFO_FN = `function () {
  if (this.nodeType !== 1) return { name: this.nodeName, fw: null, layer: null, origin: null };
  const cls = typeof this.className === 'string' ? this.className : (this.className && this.className.baseVal) || '';
  const name = this.tagName.toLowerCase() + (this.id ? '#' + this.id : '') + (cls.trim() ? '.' + cls.trim().split(/\\s+/).slice(0, 2).join('.') : '');
  const r = this.getBoundingClientRect();
  return { name, fw: this.getAttribute('data-fw'), layer: this.getAttribute('data-fw-layer'), origin: [Math.round(r.left * 1e6), Math.round(r.top * 1e6)] };
}`;

export const RENDERED_EXPR = `JSON.stringify({ dprMilli: Math.round(devicePixelRatio * 1000), rendered: Array.from(document.querySelectorAll('[data-fw-layer]')).filter((e) => e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden').map((e) => e.getAttribute('data-fw-layer')).filter(Boolean) })`;

export const sampleYs = (maxScroll) => [0, 1500, 3000, 4500, maxScroll];

const micro = (v) => Math.round(Number(v) * 1e6);

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

export async function sampleAt(c, { ev, pump, y, tries = 12, settleFrames = 3, waitMs = 40 }) {
  const rec = { requestedY: y, scrollY: null, dprMilli: null, rendered: [], layerCount: 0, layers: [] };
  let tree = null;
  const onTree = (e) => { tree = e.layers ?? []; };
  c.on('LayerTree.layerTreeDidChange', onTree);
  try {
    await ev(`window.scrollTo({ top: ${Number(y)}, left: 0, behavior: 'instant' })`);
    for (let i = 0; i < settleFrames; i++) await pump();
    rec.scrollY = Math.round(await ev('scrollY'));
    const seen = JSON.parse(await ev(RENDERED_EXPR));
    rec.dprMilli = seen.dprMilli;
    rec.rendered = seen.rendered;
    await c.send('DOM.enable').catch(() => {});
    await c.send('LayerTree.enable');
    for (let i = 0; i < tries && tree === null; i++) { await pump(); if (tree === null) await sleep(waitMs); }
    if (tree === null) { rec.error = 'no LayerTree.layerTreeDidChange after enable'; return rec; }
    await pump();
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

export async function collectCensus(c, { ev, pump, maxScroll, ys = sampleYs(maxScroll), ...opts }) {
  const samples = [];
  for (const y of ys) samples.push(await sampleAt(c, { ev, pump, y, ...opts }));
  return { schema: 'fw.layer-census/1', engine: 'chromium', samples };
}
