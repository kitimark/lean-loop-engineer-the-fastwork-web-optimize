// webkit-swap-probe: the Timeline events inside the swap windows of the people carousel (I/O only; the schedule, the counts and
// the verdict are swap.mjs, the Lean module Fw.Measure.SwapWindow, and swapreport.mjs).
// One capture: a fresh load of an arm's page, scrolled until the carousel lies in the viewport (the carousel loop runs only while the people
// section is active), then a MutationObserver on the carousel marks every swap on (5 avatars) and off (4 avatars) with
// performance.mark, without a rAF loop of its own. The Timeline rows are counted per observed window.
// A pass is four captures, faithful, crop, faithful, crop: the two faithful ones are the A/A floor of the crop against the faithful.
import { loadFresh, pageInfo, RAF_HELPER } from '../page.mjs';
import { startTimeline } from '../timeline.mjs';
import { sleep } from '../sim.mjs';
import { TargetLostError } from '../inspector.mjs';
import { markTimes } from '../reduce.mjs';
import { PERIODS, DEADLINE_US, KINDS, validAt, countCells } from './swap.mjs';

/** The order of the captures of one pass: [arm, slot]; slots a and b of the faithful arm are the two floor samples. */
export const ORDER = Object.freeze([['faithful', 'a'], ['crop', 'a'], ['faithful', 'b'], ['crop', 'b']]);
/** The same four with the crop first in each pair, for every other pass. */
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

/** Scroll down until the whole carousel lies inside the viewport: the people section sits in the middle of the page, not at its end. */
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

/** Load the arm's page and check it is the arm asked for (the config hash the server answered with). */
export async function loadArm(ctx, arm, { clock, settleMs }) {
  ctx.setArm(arm.id);
  await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + arm.search)}); scrollTo({ top: 0, behavior: 'instant' }); location.search`);
  await loadFresh(ctx.c, { clock, settleMs });
  const info = await pageInfo(ctx.c);
  const want = ctx.armHash(arm.id);
  if (want && info.fw?.configHash !== want) throw new Error(`arm ${arm.id}: wrong page (config ${info.fw?.configHash}, want ${want})`);
  return info;
}

/** One capture: the observed windows (Timeline µs), their validity and the counts per phase and kind. */
export async function swapCapture(ctx, arm, { clock, settleMs, periods = PERIODS }) {
  const info = await loadArm(ctx, arm, { clock, settleMs });
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
    schema: 'fw.webkit.lag.swap.capture/1', arm: arm.id, config: info.fw?.configHash ?? null, variant: res.variant, why: res.why,
    open: res.open, calls: res.calls, at, endChildren: res.children, ws, valid: ws.map((_, k) => validAt(ws, k)), cells: countCells(ws, recs, KINDS), records: recs.length,
  };
}

/**
 * One pass: the four captures in ORDER (`flip` runs the crop first). A capture that still fails after its retries is recorded as
 * null with its reason; the pass goes on. `arms` is { faithful: {id, search}, crop: {id, search} }; `retry(name, fn)` repeats from a fresh load.
 */
export async function swapPass(ctx, { clock, settleMs, arms, retry, log, flip = false, restore }) {
  const order = flip ? FLIPPED : ORDER;
  const out = { schema: 'fw.webkit.lag.swap/1', order: order.map(([a, s]) => `${a}-${s}`), captures: {}, failed: [] };
  try {
    for (const [arm, slot] of order) {
      const name = `${arm}-${slot}`;
      try {
        out.captures[name] = await retry(`swap ${name}`, () => swapCapture(ctx, arms[arm], { clock, settleMs }));
        const c = out.captures[name];
        log(`  swap ${name}: ${c.ws.length} windows (${c.why}), valid ${c.valid.filter(Boolean).length}, layout in swaps ${c.cells.filter((x) => x[0].startsWith('swap:') && x[1] === 'Layout').map((x) => x[2]).join(',')}`);
      } catch (e) {
        if (e instanceof TargetLostError) throw e;
        out.captures[name] = null;
        out.failed.push(`${name}: ${e.message}`);
        log(`  swap ${name} failed: ${e.message}`);
      }
    }
  } finally {
    await restore?.();
  }
  return out;
}
