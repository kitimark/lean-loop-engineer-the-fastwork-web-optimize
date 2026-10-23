// webkit-lag-probe: the passes that record where the Simulator lag regions spend their work (I/O only; the reductions are
// reduce.mjs, the Lean module Fw.Measure.WebKitLag, and report.mjs).
//   geometry : untimed. At every scroll step (and every frame of the morph push) the part boxes and the filter /
import { loadFresh, pageInfo, RAF_HELPER } from '../page.mjs';
import { reconnect } from '../wip.mjs';
import { TargetLostError } from '../inspector.mjs';
import { attempts } from '../timeouts.mjs';
import { scrollRun, schedule } from '../scrollrun.mjs';
import { startTimeline } from '../timeline.mjs';
import { sleep } from '../sim.mjs';
import { censusAt } from '../census.mjs';
import { markTimes, markTime, reduceSteps } from '../reduce.mjs';
import { regionOf } from './reduce.mjs';
import { costPasses } from './costprobe.mjs';
import { swapPass } from './swapprobe.mjs';
import { classify } from './phase.mjs';

export const MORPH_FRAMES = Object.freeze({ idle: 10, open: 60, close: 60 });

/** In-page helpers: the parts of the page and one read of their boxes and filter elements (quarter CSS px, viewport coordinates). */
const SAMPLE_SRC = `
const ORIG = [['nav', 'header.start-selling-top-nav'], ['nav-lang', '.site-locale-links'], ['hero', 'section.hero-track'],
  ['hero-copy', 'header.hero-copy'], ['people', '#people'], ['people-profile', '#profile-showcase'], ['pain', 'section.pain'],
  ['commission', 'section.commission'], ['platform', '#platform']];
const REWRITE = !!document.querySelector('[data-fw]');
const partEls = () => REWRITE
  ? [...document.querySelectorAll('[data-fw]')].filter((e) => e.dataset.fw !== 'page-root').map((e) => [e.dataset.fw, e])
  : ORIG.flatMap(([n, s]) => [...document.querySelectorAll(s)].map((e) => [n, e]));
const q4 = (v) => Math.round(v * 4);
const rectOf = (e) => { const r = e.getBoundingClientRect(); return [q4(r.left), q4(r.top), q4(r.right), q4(r.bottom)]; };
const blurPx = (s) => { let t = 0; for (const m of String(s).matchAll(/blur\\(([\\d.]+)px\\)/g)) t += Number(m[1]); return Math.round(t); };
const sample = (scan) => {
  const pe = partEls(), boxes = [];
  for (const [name, e] of pe) { const rect = rectOf(e); if (rect[2] > rect[0] && rect[3] > rect[1]) boxes.push({ name, rect }); }
  const filters = [];
  if (scan) {
    for (const el of document.querySelectorAll('*')) {
      const cs = getComputedStyle(el), f = cs.filter, b = cs.webkitBackdropFilter || cs.backdropFilter;
      const hasF = f && f !== 'none', hasB = b && b !== 'none';
      if (!hasF && !hasB) continue;
      const rect = rectOf(el);
      let part = '(none)', best = Infinity;
      for (const [n, p] of pe) { if (!p.contains(el)) continue; const r = rectOf(p), a = Math.max(0, r[2] - r[0]) * Math.max(0, r[3] - r[1]); if (a < best) { best = a; part = n; } }
      filters.push({ kind: hasB ? 'backdrop' : 'filter', radius: blurPx(hasB ? b : f), rect, part, tag: el.tagName.toLowerCase() });
    }
  }
  return { boxes, filters, scanned: !!scan };
};
`;

const SCROLL_GEOM_JS = (ys, scanAt) => `(async () => {
  ${RAF_HELPER} ${SAMPLE_SRC}
  const ys = ${JSON.stringify(ys)}, scan = new Set(${JSON.stringify(scanAt)}), out = [];
  for (let k = 0; k < ys.length; k++) { scrollTo({ top: ys[k], behavior: 'instant' }); await raf(); await raf(); out.push(sample(scan.has(k))); }
  scrollTo({ top: 0, behavior: 'instant' });
  return out;
})()`;

const MORPH_JS = (sampling) => `(async () => {
  ${RAF_HELPER} ${SAMPLE_SRC}
  const F = ${JSON.stringify(MORPH_FRAMES)};
  const counts = { scrollTo: 0 };
  const nativeScrollTo = window.scrollTo.bind(window);
  window.scrollTo = (...a) => { counts.scrollTo++; return nativeScrollTo(...a); };
  const push = (d) => { performance.mark(d > 0 ? 'wk:down' : 'wk:up'); const e = new WheelEvent('wheel', { deltaY: d, cancelable: true, bubbles: true }); document.body.dispatchEvent(e); return e.defaultPrevented; };
  const taken = [], samples = [];
  let k = 0;
  const frames = async (n) => { for (let i = 0; i < n; i++) { performance.mark('wk:s' + k); k++; await raf(); ${sampling ? 'samples.push(sample(true));' : ''} } };
  performance.mark('wk:begin');
  await frames(F.idle);
  taken.push(push(120));
  await frames(F.open);
  taken.push(push(-120));
  await frames(F.close);
  performance.mark('wk:end');
  return { taken, scrollTo: counts.scrollTo, samples, y: Math.round(scrollY) };
})()`;

const MORPH_STATE_JS = `JSON.stringify((() => {
  const p = document.querySelector('.start-selling-platform, [data-fw="platform"]');
  const r = p ? p.getBoundingClientRect() : null;
  const nav = document.querySelector('header.start-selling-top-nav, [data-fw="nav"]');
  const vv = window.visualViewport;
  return { vh: vv ? vv.height : innerHeight, platform: r ? { height: r.height, bottom: r.bottom } : null, morph: nav ? getComputedStyle(nav).getPropertyValue('--morph').trim() : null, y: Math.round(scrollY) };
})())`;

/**
 * Which scroll steps get the filter scan: every step of A and B, every eighth step of the rest (the scan reads the
 * computed style of every element, so the calm baseline is a subsample). Each sample records `scanned`.
 */
export function scanSteps(ys, vh, maxY) {
  return ys.map((y, k) => [y, k]).filter(([y, k]) => ['A', 'B'].includes(regionOf(vh, maxY, y)) || k % 8 === 0).map(([, k]) => k);
}

/** Retry a pass from a fresh load after a reconnect, like determinism.mjs `onePassRetrying`. */
async function retrying(ctx, name, log, fn) {
  for (let attempt = 1; ; attempt++) {
    await ctx.check?.();
    try { return await fn(); } catch (e) {
      if (attempt >= attempts()) throw e;
      log(`  ${name} attempt ${attempt} failed (${e.message}); reconnecting and repeating from a fresh load`);
      await reconnect(ctx, { log });
    }
  }
}

const compactCensus = (c) => ({
  scrollY: c.scrollY, layerCount: c.layerCount, memoryBytes: c.memoryBytes, reasonCounts: c.reasonCounts,
  filterLayers: c.layers.filter((l) => l.reasons.some((r) => /filter|backdrop/i.test(r))).map((l) => ({ name: l.name, compositedBounds: l.compositedBounds, memory: l.memory, reasons: l.reasons })),
});

/** The untimed geometry pass: scroll steps, the morph frames, and a census at the four states. */
export async function geometryPass(ctx, { clock, settleMs, step, log }) {
  return retrying(ctx, 'geometry', log, async () => {
    const c0 = ctx.c;
    await loadFresh(c0, { clock, settleMs });
    const info = await pageInfo(c0);
    const ys = schedule(info.maxY, step);
    const scroll = await c0.runAsync(SCROLL_GEOM_JS(ys, scanSteps(ys, info.vh, info.maxY)), { pollMs: 1000 });
    await loadFresh(c0, { clock, settleMs });
    await c0.runAsync(`(async () => { ${RAF_HELPER} scrollTo({ top: ${info.maxY}, behavior: 'instant' }); await raf(); await raf(); await raf(); return scrollY; })()`);
    await sleep(500);
    const before = JSON.parse(await c0.evaluate(MORPH_STATE_JS));
    const morph = await c0.runAsync(MORPH_JS(true), { pollMs: 1000 });
    const after = JSON.parse(await c0.evaluate(MORPH_STATE_JS));
    const census = [];
    for (const y of [0, Math.round(info.vh / 2), Math.round(info.maxY / 2), info.maxY]) census.push(compactCensus(await censusAt(c0, y, { holdMs: 300, paintWindowMs: 500 })));
    log(`  geometry: ${ys.length} steps, morph wheel taken ${JSON.stringify(morph.taken)}, --morph ${before.morph} -> ${after.morph}`);
    return { info, ys, scroll, morph: { ...morph, before, after }, census };
  });
}

/** One timed morph run from a fresh load, scrolled to the end of the page first. */
export async function morphRun(c, { clock, settleMs }) {
  await loadFresh(c, { clock, settleMs });
  const info = await pageInfo(c);
  await c.runAsync(`(async () => { ${RAF_HELPER} scrollTo({ top: ${info.maxY}, behavior: 'instant' }); await raf(); await raf(); await raf(); return scrollY; })()`);
  await sleep(500);
  const before = JSON.parse(await c.evaluate(MORPH_STATE_JS));
  const tl = await startTimeline(c);
  const res = await c.runAsync(MORPH_JS(false), { pollMs: 1000 });
  await sleep(300);
  const records = await tl.stop();
  const n = MORPH_FRAMES.idle + MORPH_FRAMES.open + MORPH_FRAMES.close;
  const marks = markTimes(records, 'wk:s', n);
  const endTime = markTime(records, 'wk:end');
  if (marks.some((t) => t === null) || endTime === null) throw new Error(`morph step marks missing from the Timeline (${marks.filter((t) => t === null).length} of ${n})`);
  const down = markTime(records, 'wk:down'), up = markTime(records, 'wk:up');
  const used = classify(marks, down, up);
  if (used.outcome !== 'ok') throw new Error(`morph run refused by the phase rule: ${used.outcome}`);
  const after = JSON.parse(await c.evaluate(MORPH_STATE_JS));
  return { schema: 'fw.webkit.lag.morph/1', info, frames: MORPH_FRAMES, phases: { down, up }, before, after, taken: res.taken, scrollTo: res.scrollTo, marks, endTime, records, reduced: reduceSteps(records, marks, endTime) };
}

/**
 * A session: the geometry pass once, then `passes` times a fresh-load scroll run and morph run. A run that still fails
 * after its retries ends the session; the completed runs are kept and the reason goes to `failed`.
 */
export async function lagSession(ctx, { passes, clock, settleMs, step, framesPerStep, log, cost = false, costOnly = false, swap = null }) {
  const geometry = costOnly ? null : await geometryPass(ctx, { clock, settleMs, step, log });
  const out = [], failed = [];
  let targetLost = false;
  for (let i = 0; i < passes; i++) {
    let scroll = null, morph = null;
    if (!costOnly) {
      try {
        scroll = await retrying(ctx, 'scroll', log, async () => {
          await loadFresh(ctx.c, { clock, settleMs });
          return scrollRun(ctx.c, { step, framesPerStep, mode: 'base' });
        });
      } catch (e) { targetLost = e instanceof TargetLostError; failed.push(`pass ${i + 1} scroll: ${e.message}`); log(`  ${failed.at(-1)}`); break; }
      const t = scroll.reduced.total;
      log(`pass ${i + 1}/${passes} scroll: ${scroll.ys.length} steps, style ${t.RecalculateStyles} layout ${t.Layout} paint ${t.Paint} composite ${t.Composite}`);
      try {
        morph = await retrying(ctx, 'morph', log, () => morphRun(ctx.c, { clock, settleMs }));
      } catch (e) { targetLost = e instanceof TargetLostError; out.push({ scroll }); failed.push(`pass ${i + 1} morph: ${e.message}`); log(`  ${failed.at(-1)}`); break; }
      const m = morph.reduced.total;
      log(`pass ${i + 1}/${passes} morph: taken ${JSON.stringify(morph.taken)}, scrollTo ${morph.scrollTo}, style ${m.RecalculateStyles} layout ${m.Layout} paint ${m.Paint} composite ${m.Composite}`);
    }
    let costs = null;
    if (cost || costOnly) {
      costs = {};
      try {
        if (swap) {
          const home = swap.home;
          costs.swap = await swapPass(ctx, {
            clock, settleMs, arms: swap.arms, log, flip: i % 2 === 1,
            retry: (name, fn) => retrying(ctx, name, log, fn),
            restore: async () => { ctx.setArm(home.id); await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + home.search)}); 1`); },
          });
        }
        Object.assign(costs, await costPasses((name, fn) => retrying(ctx, `cost ${name}`, log, () => fn(ctx.c, { clock, settleMs, step, framesPerStep })), log));
      } catch (e) {
        targetLost = e instanceof TargetLostError; failed.push(`pass ${i + 1} cost: ${e.message}`); log(`  ${failed.at(-1)}`);
        out.push({ scroll, morph, ...(costs.swap ? { cost: costs } : {}) });
        break;
      }
      log(`pass ${i + 1}/${passes} cost: ${['scroll', 'morph', 'layersScroll', 'layersMorph', ...(swap ? ['swap'] : [])].map((k) => `${k} ${costs[k] ? 'ok' : 'failed'}`).join(', ')}`);
    }
    out.push({ ...(scroll ? { scroll, morph } : {}), ...(costs ? { cost: costs } : {}) });
  }
  return { schema: 'fw.webkit.lag/1', step, framesPerStep, geometry, passes: out, failed, ...(targetLost ? { targetLost } : {}) };
}
