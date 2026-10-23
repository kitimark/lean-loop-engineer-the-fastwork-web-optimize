import { RAF_HELPER } from '../page.mjs';
import { schedule } from '../scrollrun.mjs';
import { startTimeline } from '../timeline.mjs';
import { sleep } from '../sim.mjs';
import { markTimes, markTime, reduceSteps } from '../reduce.mjs';
import { regionOf } from './reduce.mjs';
import { loadArm } from './swapprobe.mjs';
import { freezeStep } from './freeze.mjs';

export const ALIGN_WAIT_MS = 4000;

export const ZONE_JS = (ys, framesPerStep, align) => `(async () => {
  ${RAF_HELPER}
  const ys = ${JSON.stringify(ys)};
  const em = document.querySelector('[data-fw="hero-accent"]');
  const stateOf = () => { const c = em ? String(em.className) : ''; return /drawingOut/i.test(c) ? 'out' : /drawingIn/i.test(c) ? 'in' : /idle/i.test(c) ? 'idle' : 'none'; };
  const drawing = () => { const s = stateOf(); return s === 'in' || s === 'out'; };
  let aligned = drawing();
  if (${align ? 'true' : 'false'} && em && !aligned) {
    aligned = await new Promise((resolve) => {
      const o = new MutationObserver(() => { if (drawing()) { clearTimeout(t); o.disconnect(); resolve(true); } });
      const t = setTimeout(() => { o.disconnect(); resolve(false); }, ${ALIGN_WAIT_MS});
      o.observe(em, { attributes: true, attributeFilter: ['class'] });
    });
  }
  const start = stateOf(), changes = [];
  let k = 0;
  const mo = em ? new MutationObserver(() => changes.push([k, stateOf()])) : null;
  if (mo) mo.observe(em, { attributes: true, attributeFilter: ['class'] });
  performance.mark('wk:begin');
  for (k = 0; k < ys.length; k++) {
    performance.mark('wk:s' + k);
    scrollTo({ top: ys[k], behavior: 'instant' });
    for (let f = 0; f < ${framesPerStep}; f++) await raf();
  }
  performance.mark('wk:end');
  if (mo) mo.disconnect();
  return { y: Math.round(scrollY), start, changes, aligned };
})()`;

/** The steps of the hero-exit zone of the lane's scroll schedule. */
export const zoneSteps = (vh, maxY, step) => schedule(maxY, step).filter((y) => regionOf(vh, maxY, y) === 'A');

export async function zoneCapture(ctx, arm, { clock, settleMs, step, framesPerStep, freeze = null, align = false }) {
  const info = await loadArm(ctx, arm, { clock, settleMs });
  const accent = await freezeStep(ctx.c, freeze);
  const ys = zoneSteps(info.vh, info.maxY, step);
  if (ys.length < 2) throw new Error(`hero-exit zone has ${ys.length} steps (vh ${info.vh}, maxY ${info.maxY})`);
  await ctx.c.evaluate('scrollTo({ top: 0, behavior: "instant" }); 1');
  await sleep(300);
  const tl = await startTimeline(ctx.c);
  const res = await ctx.c.runAsync(ZONE_JS(ys, framesPerStep, align), { pollMs: 500 });
  await sleep(300);
  const records = await tl.stop();
  const marks = markTimes(records, 'wk:s', ys.length), endTime = markTime(records, 'wk:end');
  if (marks.some((t) => t === null) || endTime === null) throw new Error('zone step marks missing from the Timeline');
  const t = reduceSteps(records, marks, endTime).total;
  return {
    schema: 'fw.webkit.lag.freeze.zone/1', arm: arm.id, zone: 'scroll-A', align, ...(accent ? { accent } : {}), steps: ys.length, framesPerStep,
    layout: t.Layout, paint: t.Paint, composite: t.Composite, style: t.RecalculateStyles,
    accentStart: res.start, accentChanges: res.changes.length, drew: res.start === 'in' || res.start === 'out' || res.changes.length > 0,
  };
}
