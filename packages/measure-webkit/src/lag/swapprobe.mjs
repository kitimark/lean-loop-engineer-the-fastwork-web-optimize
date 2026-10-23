import { loadFresh, pageInfo, RAF_HELPER } from '../page.mjs';
import { startTimeline } from '../timeline.mjs';
import { sleep } from '../sim.mjs';
import { TargetLostError } from '../inspector.mjs';
import { markTimes, markTime } from '../reduce.mjs';
import { PERIODS, DEADLINE_US, KINDS, validAt, countCells } from './swap.mjs';
import { freezeStep } from './freeze.mjs';

export const ORDER = Object.freeze([['faithful', 'a'], ['crop', 'a'], ['faithful', 'b'], ['crop', 'b']]);
export const FLIPPED = Object.freeze([ORDER[1], ORDER[0], ORDER[3], ORDER[2]]);

export const WATCH_JS = (periods, deadlineMs) => `(async () => {
  const el = document.querySelector('[data-fw="people-carousel"]');
  if (!el) return { error: 'no carousel' };
  let armed = el.childElementCount <= 4, open = false, closed = 0, calls = 0, resolve;
  const end = new Promise((r) => { resolve = r; });
  const obs = new MutationObserver(() => {
    calls++;
    const n = el.childElementCount;
    if (n <= 4) {
      armed = true;
      if (open) { open = false; performance.mark('wk:off' + closed); closed++; if (closed >= ${periods}) resolve('full'); }
    } else if (armed && !open) { open = true; performance.mark('wk:on' + closed); }
  });
  obs.observe(el, { childList: true });
  performance.mark('wk:begin');
  const timer = setTimeout(() => resolve('deadline'), ${deadlineMs});
  const why = await end;
  clearTimeout(timer);
  obs.disconnect();
  performance.mark('wk:end');
  return { why, closed, open, calls, children: el.childElementCount, variant: el.getAttribute('data-fw-variant') };
})()`;

export const FIND_JS = (maxY) => `(async () => {
  ${RAF_HELPER}
  const el = document.querySelector('[data-fw="people-carousel"]');
  if (!el) return { error: 'no carousel' };
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const vh = innerHeight, step = Math.max(50, Math.round(vh / 4));
  for (let y = 0; y <= ${maxY}; y += step) {
    scrollTo({ top: y, behavior: 'instant' });
    await raf(); await raf();
    const r = el.getBoundingClientRect();
    if (r.top >= 0 && r.bottom <= vh && r.width > 0) return { y: Math.round(scrollY), top: Math.round(r.top), bottom: Math.round(r.bottom), vh, reduced, children: el.childElementCount };
  }
  return { error: 'the carousel never lies inside the viewport', reduced, vh, maxY: ${maxY} };
})()`;
const us = (s) => Math.round(s * 1e6);

export const DIAG_JS = (durationMs, bucketMs) => `(async () => {
  const B = ${bucketMs}, n = Math.ceil(${durationMs} / B);
  const owner = (node) => {
    const el = node && (node.nodeType === 1 ? node : node.parentElement);
    if (!el) return 'none';
    const f = el.closest('[data-fw]');
    return f ? f.getAttribute('data-fw') : el.tagName.toLowerCase();
  };
  const skip = ['offset', 'easing', 'composite', 'computedOffset'];
  const anims = () => {
    const seen = {};
    for (const a of document.getAnimations()) {
      const kf = a.effect ? a.effect.getKeyframes() : [];
      const props = [...new Set(kf.flatMap((k) => Object.keys(k)).filter((k) => !skip.includes(k)))].sort().join(',');
      const tm = a.effect ? a.effect.getComputedTiming() : {};
      const key = [owner(a.effect && a.effect.target), a.animationName || a.transitionProperty || a.constructor.name, a.constructor.name, a.playState, tm.duration, tm.iterations, props].join('|');
      seen[key] = (seen[key] || 0) + 1;
    }
    return seen;
  };
  const before = anims();
  const owners = {};
  const t0 = performance.now();
  performance.mark('wk:dbegin');
  const mo = new MutationObserver((recs) => {
    const b = Math.min(n - 1, Math.floor((performance.now() - t0) / B));
    for (const r of recs) {
      const key = owner(r.target) + ':' + (r.type === 'attributes' ? r.attributeName : r.type);
      (owners[key] || (owners[key] = new Array(n).fill(0)))[b]++;
    }
  });
  mo.observe(document.documentElement, { subtree: true, attributes: true, childList: true, characterData: true });
  await new Promise((r) => setTimeout(r, ${durationMs}));
  mo.disconnect();
  performance.mark('wk:dend');
  return { buckets: n, bucketMs: B, owners, before, after: anims() };
})()`;

export function bucketRows(rows, type, beginS, bucketMs, n) {
  const out = new Array(n).fill(0);
  for (const r of rows) {
    if (r[0] !== type || typeof r[1] !== 'number') continue;
    const b = Math.floor(((r[1] - beginS) * 1000) / bucketMs);
    if (b >= 0 && b < n) out[b]++;
  }
  return out;
}

export const DIAG_MS = 7000;
export const DIAG_BUCKET_MS = 100;

export async function diagCapture(ctx, arm, { clock, settleMs, freeze = null }) {
  const info = await loadArm(ctx, arm, { clock, settleMs });
  const accent = await freezeStep(ctx.c, freeze);
  const at = await ctx.c.runAsync(FIND_JS(info.maxY), { pollMs: 500 });
  if (at.error) throw new Error(`arm ${arm.id}: ${at.error}`);
  await sleep(500);
  const tl = await startTimeline(ctx.c);
  const res = await ctx.c.runAsync(DIAG_JS(DIAG_MS, DIAG_BUCKET_MS), { pollMs: 1000 });
  await sleep(300);
  const records = await tl.stop();
  const begin = markTime(records, 'wk:dbegin');
  if (begin === null) throw new Error('diag mark missing from the Timeline');
  const active = Object.fromEntries(Object.entries(res.owners).filter(([, v]) => v.reduce((a, b) => a + b, 0) >= 2));
  return {
    schema: 'fw.webkit.lag.swap.diag/1', arm: arm.id, ...(accent ? { accent } : {}), bucketMs: res.bucketMs, buckets: res.buckets,
    layout: bucketRows(records, 'Layout', begin, res.bucketMs, res.buckets), paint: bucketRows(records, 'Paint', begin, res.bucketMs, res.buckets),
    owners: active, before: res.before, after: res.after,
  };
}

let passNo = 0;

export const jobMeta = (env = process.env) => ({
  run: env.GITHUB_RUN_ID ?? null, attempt: env.GITHUB_RUN_ATTEMPT ?? null, job: env.GITHUB_JOB ?? null, vm: env.VM ?? null,
  jobId: env.FW_JOB_ID ?? null, sha: env.GITHUB_SHA ?? null,
});

export async function loadArm(ctx, arm, { clock, settleMs }) {
  ctx.setArm(arm.id);
  await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + arm.search)}); scrollTo({ top: 0, behavior: 'instant' }); location.search`);
  await loadFresh(ctx.c, { clock, settleMs });
  const info = await pageInfo(ctx.c);
  const want = ctx.armHash(arm.id);
  if (want && info.fw?.configHash !== want) throw new Error(`arm ${arm.id}: wrong page (config ${info.fw?.configHash}, want ${want})`);
  return info;
}

export async function swapCapture(ctx, arm, { clock, settleMs, periods = PERIODS, freeze = null }) {
  const info = await loadArm(ctx, arm, { clock, settleMs });
  const accent = await freezeStep(ctx.c, freeze);
  const at = await ctx.c.runAsync(FIND_JS(info.maxY), { pollMs: 500 });
  if (at.error) throw new Error(`arm ${arm.id}: ${at.error}${at.reduced ? ' (reduced motion is on)' : ''}`);
  await sleep(500);
  const tl = await startTimeline(ctx.c);
  const res = await ctx.c.runAsync(WATCH_JS(periods, Math.ceil(DEADLINE_US / 1000)), { pollMs: 1000 });
  await sleep(300);
  const records = await tl.stop();
  if (res.error) throw new Error(`arm ${arm.id}: ${res.error}`);
  const on = markTimes(records, 'wk:on', res.closed), off = markTimes(records, 'wk:off', res.closed);
  if (on.some((t) => t === null) || off.some((t) => t === null)) throw new Error(`swap marks missing from the Timeline (${res.closed} windows)`);
  const ws = on.map((t, k) => [us(t), us(off[k])]);
  const recs = records.filter((r) => KINDS.includes(r[0]) && typeof r[1] === 'number').map((r) => [r[0], us(r[1])]);
  return {
    schema: 'fw.webkit.lag.swap.capture/1', arm: arm.id, ...(accent ? { accent } : {}), config: info.fw?.configHash ?? null, variant: res.variant, why: res.why,
    open: res.open, calls: res.calls, at, endChildren: res.children, ws, valid: ws.map((_, k) => validAt(ws, k)), cells: countCells(ws, recs, KINDS), records: recs.length,
  };
}

export async function swapPass(ctx, { clock, settleMs, arms, retry, log, flip = false, restore, freeze = null, diagArms = ['crop'], pass = null }) {
  const order = flip ? FLIPPED : ORDER;
  const out = { schema: 'fw.webkit.lag.swap/1', order: order.map(([a, s]) => `${a}-${s}`), job: { ...jobMeta(), pass: pass ?? ++passNo }, captures: {}, failed: [], diag: null, ...(freeze ? { freeze } : {}) };
  try {
    for (const [arm, slot] of order) {
      const name = `${arm}-${slot}`;
      try {
        out.captures[name] = await retry(`swap ${name}`, () => swapCapture(ctx, arms[arm], { clock, settleMs, freeze }));
        const c = out.captures[name];
        log(`  swap ${name}: ${c.ws.length} windows (${c.why}), valid ${c.valid.filter(Boolean).length}, layout in swaps ${c.cells.filter((x) => x[0].startsWith('swap:') && x[1] === 'Layout').map((x) => x[2]).join(',')}`);
      } catch (e) {
        if (e instanceof TargetLostError) throw e;
        out.captures[name] = null;
        out.failed.push(`${name}: ${e.message}`);
        log(`  swap ${name} failed: ${e.message}`);
      }
    }
    if (!flip) {
      for (const id of diagArms) {
        try {
          const d = await retry(`swap diag ${id}`, () => diagCapture(ctx, arms[id], { clock, settleMs, freeze }));
          if (id === 'crop') out.diag = d; else (out.diagOther ??= {})[id] = d;
          log(`  swap diag ${id}: ${Object.keys(d.owners).length} owners with writes, layout rows ${d.layout.reduce((a, b) => a + b, 0)}`);
        } catch (e) {
          if (e instanceof TargetLostError) throw e;
          out.failed.push(`diag ${id}: ${e.message}`);
          log(`  swap diag ${id} failed: ${e.message}`);
        }
      }
    }
  } finally {
    await restore?.();
  }
  return out;
}
