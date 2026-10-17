// Finger-swipe recording on the real iPhone (session 1b). I/O glue only: the page records the native requestAnimationFrame
// timestamps and scrollY of every frame while a PERSON swipes; the reductions are the ones session 1 used
// (device-runs.mjs summarizeFrames for frame intervals, reduce.mjs reduceSteps/zones for Timeline counts). Nothing is decided here.
//  - arm "frames": no Timeline (the Timeline instrument costs time on the page; the frame-interval metric is taken without it).
//  - arm "counts": Timeline on; a performance.mark('wk:s<k>') every time scrollY enters a new 50 px band (same step size as the
//    scripted counts) so records join to scroll position; idle time between swipes is attributed to the last band.
// The person is told what to do by a banner drawn in the page itself (the page is on the phone's screen); the banner is
// removed before recording starts and shown again when it ends. The recorder's own rAF loop is one FireAnimationFrame per frame.
import { sleep } from './sim.mjs';
import { startTimeline } from './timeline.mjs';
import { markTimes, markTime, reduceSteps, zones, COUNT_TYPES } from './reduce.mjs';
import { summarizeFrames } from './device-runs.mjs';

const BANNER_JS = (text, big) => `(() => {
  let b = document.getElementById('__wkbanner');
  if (!b) { b = document.createElement('div'); b.id = '__wkbanner'; document.body.appendChild(b); }
  b.style.cssText = 'position:fixed;left:0;right:0;top:0;z-index:2147483647;background:#c00;color:#fff;font:700 ${big ? 26 : 18}px/1.3 -apple-system,sans-serif;padding:16px;text-align:center;pointer-events:none';
  b.textContent = ${JSON.stringify(text)};
  return 1;
})()`;
const BANNER_OFF_JS = `(() => { const b = document.getElementById('__wkbanner'); if (b) b.remove(); return 1; })()`;
const SCHEME_JS = `matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'`;

const RECORD_JS = (seconds, mark) => `(async () => {
  const maxY = document.documentElement.scrollHeight - innerHeight;
  const ts = [], ys = [], bands = [];
  let last = -1;
  const t0 = performance.now();
  await new Promise((done) => {
    const f = (t) => {
      const y = scrollY;
      ts.push(Math.round(t * 100) / 100); ys.push(Math.round(y * 10) / 10);
      ${mark ? `const yc = Math.min(maxY, Math.max(0, y)), b = Math.floor(yc / 50);
      if (b !== last) { last = b; performance.mark('wk:s' + bands.length); bands.push(Math.round(yc)); }` : ''}
      if (performance.now() - t0 < ${Number(seconds) * 1000}) requestAnimationFrame(f); else done();
    };
    requestAnimationFrame(f);
  });
  ${mark ? `performance.mark('wk:end');` : ''}
  return { maxY, ts, ys, bands };
})()`;

/**
 * One swipe recording. Phases: (1) optionally wait for Light appearance (banner asks the person), (2) countdown banner,
 * (3) record `seconds`, (4) "done" banner. Returns raw run + reduced part.
 */
export async function phoneSwipe(ctx, { seconds, timeline, waitLightS, countdownS = 6, instruction, loadFresh, clock, settleMs, log }) {
  const readouts = [ctx.readout()];
  await loadFresh(ctx.c, { clock, settleMs, timers: 'live' });
  await ctx.c.evaluate('scrollTo({ top: 0, behavior: "instant" }); 1');
  let scheme = await ctx.c.evaluate(SCHEME_JS);
  const schemeAtStart = scheme;
  const tw = Date.now();
  while (scheme === 'dark' && Date.now() - tw < waitLightS * 1000) {
    await ctx.c.evaluate(BANNER_JS(`Please switch the phone to LIGHT appearance (Control Centre or Settings). Waiting ${Math.ceil(waitLightS - (Date.now() - tw) / 1000)} s`, false));
    await sleep(2000);
    scheme = await ctx.c.evaluate(SCHEME_JS);
  }
  log(`appearance at start ${schemeAtStart}, at record ${scheme}`);
  for (let s = countdownS; s > 0; s--) {
    await ctx.c.evaluate(BANNER_JS(`${instruction}  Starts in ${s} s (this banner disappears when recording starts; keep going for ${seconds} s)`, false));
    await sleep(1000);
  }
  await ctx.c.evaluate(BANNER_OFF_JS);
  await ctx.c.evaluate('scrollTo({ top: 0, behavior: "instant" }); 1');
  const tl = timeline ? await startTimeline(ctx.c) : null;
  log(`recording ${seconds} s${timeline ? ' with Timeline' : ''}: person swipes now`);
  // own poll loop: an evaluate that times out while a finger is on the screen is retried, not fatal
  await ctx.c.evaluate(`window.__wkSw = undefined; Promise.resolve(${RECORD_JS(seconds, timeline)}).then(v => { window.__wkSw = JSON.stringify(v); }, e => { window.__wkSw = JSON.stringify({err: String(e)}); }); 'started'`);
  let run = null, polls = 0, pollErrors = 0;
  const tEnd = Date.now() + (seconds + 90) * 1000;
  while (!run && Date.now() < tEnd) {
    await sleep(2500); polls++;
    try { const v = await ctx.c.evaluate('window.__wkSw || null'); if (v) run = JSON.parse(v); } catch (e) { pollErrors++; log(`poll ${polls}: ${e.message}`); }
  }
  if (!run || run.err) throw new Error(`recording did not finish: ${run?.err ?? 'timeout'}`);
  const records = tl ? await tl.stop() : null;
  await ctx.c.evaluate(BANNER_JS('DONE. You can stop swiping and put the phone down.', true)).catch(() => {});
  readouts.push(ctx.readout());
  const out = {
    schema: 'fw.phone.swipe/1', kind: 'finger swipe by a person (rAF timestamps + scrollY of every frame)', arm: timeline ? 'counts' : 'frames',
    seconds, polls, pollErrors, appearance: { atStart: schemeAtStart, atRecord: scheme }, device: ctx.device, readouts,
    maxY: run.maxY, reachedY: Math.max(0, ...run.ys), minY: Math.min(...run.ys), frames: run.ts.length,
    summary: summarizeFrames([{ ts: run.ts, ys: run.ys }]),
    run: { ts: run.ts, ys: run.ys },
  };
  if (records) {
    const marks = markTimes(records, 'wk:s', run.bands.length), endTime = markTime(records, 'wk:end');
    if (marks.some((t) => t === null) || endTime === null) throw new Error(`step marks missing from the Timeline: ${marks.filter((t) => t === null).length} of ${marks.length}`);
    const reduced = reduceSteps(records, marks, endTime);
    out.counts = { countTypes: COUNT_TYPES, bands: run.bands.length, total: reduced.total, zones: zones(run.bands, reduced.perStep, reduced.perStepPaintArea), other: reduced.other, rowsBeforeFirstStep: reduced.rowsBeforeFirstStep };
  }
  return out;
}
