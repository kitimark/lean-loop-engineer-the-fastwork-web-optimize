// webkit-cost-counters: the passes that record the per-frame cost counters (I/O only; the counted predicates are
// cost.mjs, the Lean module Fw.Measure.WkCost, and costreport.mjs). Four fresh-load passes, none touching the lag passes:
//   scrollCost  : timed. The stepped scroll of the lane; every rAF callback writes its timestamp and a mark, so Paint and
//                 Composite durations of the Timeline are bucketed to frames.
//   morphCost   : timed. Idle frames, a synthetic wheel push down, 1.8 s of frames, a push up, 1.8 s of frames (the tween is
//                 680 ms, so the 1000 ms after each tween end is covered); Paint start times are kept.
//   scrollLayers: untimed. After every frame of the same scroll the LayerTree is read (id and composited size per layer).
//   morphLayers : untimed. Around the morph pushes the tree is read each time `LayerTree.layerTreeDidChange` fires (WebKit
//                 suppresses the event until the tree is read again, so read, wait for the event, read).
import { loadFresh, pageInfo, RAF_HELPER } from '../page.mjs';
import { schedule } from '../scrollrun.mjs';
import { startTimeline } from '../timeline.mjs';
import { sleep } from '../sim.mjs';
import { TargetLostError } from '../inspector.mjs';
import { markTimes, markTime, bucketBySteps } from '../reduce.mjs';
import { scrollZone, morphZone, morphEnd, TWEEN_US, EARLY_US, LATE_US } from './cost.mjs';

/** Frames after each morph push: the tween, the early and late windows, and 120 ms of margin (milliseconds). */
export const HOLD_MS = (TWEEN_US + EARLY_US + LATE_US) / 1000 + 120;
/** Idle frames before the first push. */
export const IDLE_FRAMES = 10;

const RAF_TS = `const rafT = () => new Promise((r) => requestAnimationFrame((t) => r(t)));`;

const SCROLL_COST_JS = (ys, framesPerStep) => `(async () => {
  ${RAF_TS}
  const ys = ${JSON.stringify(ys)}, frames = [];
  let n = 0;
  performance.mark('wk:begin');
  for (let k = 0; k < ys.length; k++) {
    scrollTo({ top: ys[k], behavior: 'instant' });
    for (let f = 0; f < ${framesPerStep}; f++) { const t = await rafT(); performance.mark('wk:f' + n); n++; frames.push([Math.round(t * 1000), k]); }
  }
  performance.mark('wk:end');
  return { frames, y: Math.round(scrollY) };
})()`;

const MORPH_COST_JS = `(async () => {
  ${RAF_TS}
  const frames = [], taken = [];
  let n = 0;
  const frame = async () => { const t = await rafT(); performance.mark('wk:f' + n); n++; frames.push(Math.round(t * 1000)); };
  const push = (d) => { const e = new WheelEvent('wheel', { deltaY: d, cancelable: true, bubbles: true }); document.body.dispatchEvent(e); return e.defaultPrevented; };
  performance.mark('wk:begin');
  for (let i = 0; i < ${IDLE_FRAMES}; i++) await frame();
  const po = performance.now(); performance.mark('wk:po'); taken.push(push(120));
  while (performance.now() < po + ${HOLD_MS}) await frame();
  const pc = performance.now(); performance.mark('wk:pc'); taken.push(push(-120));
  while (performance.now() < pc + ${HOLD_MS}) await frame();
  performance.mark('wk:end');
  return { frames, taken, po: Math.round(po * 1000), pc: Math.round(pc * 1000) };
})()`;

const toEnd = (maxY) => `(async () => { ${RAF_HELPER} scrollTo({ top: ${maxY}, behavior: 'instant' }); await raf(); await raf(); await raf(); return scrollY; })()`;

/** Paint and Composite time per frame in integer microseconds, rows bucketed by the frame marks. */
export function frameCosts(records, marks, endTime) {
  const { steps } = bucketBySteps(records, marks, endTime);
  const us = (r, type) => (r[0] === type && typeof r[2] === 'number' ? Math.round((r[2] - r[1]) * 1e6) : 0);
  return steps.map((rows) => [rows.reduce((s, r) => s + us(r, 'Paint'), 0), rows.reduce((s, r) => s + us(r, 'Composite'), 0)]);
}

const framesOf = (records, n) => {
  const marks = markTimes(records, 'wk:f', n), endTime = markTime(records, 'wk:end');
  if (marks.some((t) => t === null) || endTime === null) throw new Error(`frame marks missing from the Timeline (${marks.filter((t) => t === null).length} of ${n})`);
  return { marks, endTime };
};

/** The timed stepped scroll with frame timestamps; frames are [t µs, zone], costs [zone, paintUs, compUs]. */
export async function scrollCost(c, { clock, settleMs, step, framesPerStep }) {
  await loadFresh(c, { clock, settleMs });
  const info = await pageInfo(c);
  const ys = schedule(info.maxY, step);
  const tl = await startTimeline(c);
  const res = await c.runAsync(SCROLL_COST_JS(ys, framesPerStep), { pollMs: 1000 });
  await sleep(300);
  const records = await tl.stop();
  const { marks, endTime } = framesOf(records, res.frames.length);
  const zoneOf = (k) => scrollZone(info.vh, info.maxY, ys[k]);
  const per = frameCosts(records, marks, endTime);
  return {
    schema: 'fw.webkit.lag.cost.scroll/1', info, step, framesPerStep, ys,
    frames: res.frames.map(([t, k]) => [t, zoneOf(k)]),
    costs: res.frames.map(([, k], i) => [zoneOf(k), per[i][0], per[i][1]]),
  };
}

/** The timed morph with frame timestamps and the Paint start times (Timeline clock, integer microseconds). */
export async function morphCost(c, { clock, settleMs }) {
  await loadFresh(c, { clock, settleMs });
  const info = await pageInfo(c);
  await c.runAsync(toEnd(info.maxY));
  await sleep(500);
  const tl = await startTimeline(c);
  const res = await c.runAsync(MORPH_COST_JS, { pollMs: 1000 });
  await sleep(300);
  const records = await tl.stop();
  const { marks, endTime } = framesOf(records, res.frames.length);
  const poT = markTime(records, 'wk:po'), pcT = markTime(records, 'wk:pc');
  if (poT === null || pcT === null) throw new Error('morph push marks missing from the Timeline');
  const per = frameCosts(records, marks, endTime);
  const zones = res.frames.map((t) => morphZone(res.po, res.pc, t));
  const us = (s) => Math.round(s * 1e6);
  return {
    schema: 'fw.webkit.lag.cost.morph/1', info, taken: res.taken,
    frames: res.frames.map((t, i) => [t, zones[i]]),
    costs: zones.map((z, i) => [z, per[i][0], per[i][1]]),
    pushes: { open: us(poT), close: us(pcT) },
    paints: records.filter((r) => r[0] === 'Paint' && typeof r[1] === 'number' && r[1] >= poT).map((r) => us(r[1])),
    ends: { open: morphEnd(us(poT)), close: morphEnd(us(pcT)) },
  };
}

/** The layers of the document right now: [id, w, h] of the composited bounds. */
async function readLayers(c, docId) {
  const r = await c.send('LayerTree.layersForNode', { nodeId: docId });
  return (r.layers || []).map((l) => [String(l.layerId), Math.round(l.compositedBounds?.width ?? 0), Math.round(l.compositedBounds?.height ?? 0)]);
}

async function layerSession(c) {
  await c.enable('DOM').catch(() => {});
  await c.enable('LayerTree');
  return (await c.send('DOM.getDocument', { depth: 0 })).root.nodeId;
}

/** Untimed: the scroll again, the layer tree read after every frame; snaps are [zone, layers]. */
export async function scrollLayers(c, { clock, settleMs, step, framesPerStep }) {
  await loadFresh(c, { clock, settleMs });
  const info = await pageInfo(c);
  const ys = schedule(info.maxY, step);
  const doc = await layerSession(c);
  const snaps = [['scroll-start', await readLayers(c, doc)]];
  for (let k = 0; k < ys.length; k++) {
    const z = scrollZone(info.vh, info.maxY, ys[k]);
    await c.runAsync(`(async () => { ${RAF_HELPER} scrollTo({ top: ${ys[k]}, behavior: 'instant' }); await raf(); return 1; })()`, { pollMs: 20 });
    snaps.push([z, await readLayers(c, doc)]);
    for (let f = 1; f < framesPerStep; f++) {
      await c.runAsync(`(async () => { ${RAF_HELPER} await raf(); return 1; })()`, { pollMs: 20 });
      snaps.push([z, await readLayers(c, doc)]);
    }
  }
  await c.disable('LayerTree');
  await c.disable('DOM');
  return { schema: 'fw.webkit.lag.cost.layers.scroll/1', info, ys, snaps };
}

const PUSH_JS = (d) => `(() => { const e = new WheelEvent('wheel', { deltaY: ${d}, cancelable: true, bubbles: true }); document.body.dispatchEvent(e); return e.defaultPrevented; })()`;

/** Untimed: the morph again; the tree is read at each change event (Mac clock µs for the zone). */
export async function morphLayers(c, { clock, settleMs }) {
  await loadFresh(c, { clock, settleMs });
  const info = await pageInfo(c);
  await c.runAsync(toEnd(info.maxY));
  await sleep(500);
  const doc = await layerSession(c);
  let changed = false, wake = null;
  const off = c.on((m) => { if (m.method === 'LayerTree.layerTreeDidChange') { changed = true; wake?.(); } });
  const now = () => Date.now() * 1000;
  const reads = [[now(), await readLayers(c, doc)]];
  const phase = async (d) => {
    const p = now();
    const taken = await c.evaluate(PUSH_JS(d));
    while (now() < p + HOLD_MS * 1000) {
      if (!changed) await Promise.race([new Promise((r) => { wake = r; }), sleep(100)]);
      wake = null;
      if (!changed) continue;
      changed = false;
      reads.push([now(), await readLayers(c, doc)]);
    }
    return [p, taken];
  };
  const [po, takenOpen] = await phase(120);
  const [pc, takenClose] = await phase(-120);
  off();
  await c.disable('LayerTree');
  await c.disable('DOM');
  return { schema: 'fw.webkit.lag.cost.layers.morph/1', info, taken: [takenOpen, takenClose], snaps: reads.map(([t, l]) => [morphZone(po, pc, t), l]) };
}

/** The four cost passes of one session pass; each runs on its own fresh load, and a failed one is recorded, not fatal. */
export async function costPasses(run, log) {
  const out = {};
  for (const [name, fn] of [['scroll', scrollCost], ['morph', morphCost], ['layersScroll', scrollLayers], ['layersMorph', morphLayers]]) {
    try { out[name] = await run(name, fn); } catch (e) { if (e instanceof TargetLostError) throw e; out[name] = null; (out.failed ??= []).push(`${name}: ${e.message}`); log(`  cost ${name} failed: ${e.message}`); }
  }
  return { schema: 'fw.webkit.lag.cost/1', ...out };
}
