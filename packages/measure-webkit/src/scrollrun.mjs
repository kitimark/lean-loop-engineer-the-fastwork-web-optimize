// Timeline records over a scripted scroll.
//
// The scroll is stepped by the page's own native requestAnimationFrame: step k does `scrollTo({top: y_k, behavior:
// 'instant'})` and then waits two animation frames, so the schedule is indexed by position and frame, not by wall
// clock (04-webkit-rendering-math.md §8). Every step is bracketed by a `performance.mark('wk:s<k>')`, which arrives in
// the Timeline as a TimeStamp record on the records' clock; rows are bucketed to steps by that (reduce.mjs).
// What this is NOT: a finger gesture. `scrollTo` does not set the scroll velocity that iOS tile coverage depends on
// (§3, §8.3), so tile counts need a real gesture run and are out of scope here.
//
// Modes (per-step determinism experiments, see README): base | lock | hold | lock+hold. None replaces
// requestAnimationFrame or seeks an animation.
//
// Output schema `fw.webkit.scroll/1`: { schema, mode, info, step, framesPerStep, dtMs, ys, marks, endTime, records, reduced }.
// `records`/`marks`/`endTime` are the RAW part (reduce.mjs documents it); `reduced` is reduce.mjs's interim reduction.
import { sleep } from './sim.mjs';
import { startTimeline } from './timeline.mjs';
import { markTimes, markTime, reduceSteps } from './reduce.mjs';
import { RAF_HELPER, pageInfo } from './page.mjs';
import { lagMonitor, lagBuckets } from './hostmon.mjs';

/** The scroll schedule: y = 0, step, 2*step ... up to and including maxY. */
export function schedule(maxY, step) {
  const ys = [];
  for (let y = 0; y < maxY; y += step) ys.push(y);
  ys.push(maxY);
  return ys;
}

const STEP_JS = (ys, framesPerStep, dtMs) => `(async () => {
  ${RAF_HELPER}
  const ys = ${JSON.stringify(ys)};
  performance.mark('wk:begin');
  for (let k = 0; k < ys.length; k++) {
    performance.mark('wk:s' + k);
    scrollTo({ top: ys[k], behavior: 'instant' });
    ${dtMs ? `__wk.advance(${dtMs});` : ''}
    for (let f = 0; f < ${framesPerStep}; f++) await raf();
  }
  performance.mark('wk:end');
  return Math.round(scrollY);
})()`;

/** Poll `pred` every 4 ms until it returns a truthy value or `ms` passes (null on timeout). */
async function waitFor(pred, ms) {
  const t0 = Date.now();
  for (;;) {
    const v = pred();
    if (v) return v;
    if (Date.now() - t0 > ms) return null;
    await sleep(4);
  }
}

/**
 * Step-locked scroll driven from the Mac (experiment (a)). Per step k:
 *   1. one evaluate: `performance.mark('wk:s<k>')` + `scrollTo` (nothing else);
 *   2. wait until the Timeline stream shows that mark and then a `Composite` record that starts after it;
 *   3. one evaluate that (optionally advances the held timers by dt, then) waits `quiet` native rAFs in the page and
 *      writes `performance.mark('wk:q<k>')`; wait until that mark arrives.
 * Native requestAnimationFrame is untouched; the Mac only decides WHEN the next scroll is issued.
 * @returns {{noComposite:number[]}} steps where no Composite arrived within `compositeMs` (the lock fell through)
 */
async function lockedSteps(c, tl, ys, { quiet, dtMs, compositeMs = 2000 }) {
  const noComposite = [];
  const find = (type, pred) => tl.top.find((r) => r.type === type && pred(r));
  const stamp = (name) => find('TimeStamp', (r) => r.data?.message === name);
  await c.evaluate("performance.mark('wk:begin'); 1");
  for (let k = 0; k < ys.length; k++) {
    await c.evaluate(`performance.mark('wk:s${k}'); scrollTo({ top: ${ys[k]}, behavior: 'instant' }); 1`);
    const m = await waitFor(() => stamp(`wk:s${k}`), 5000);
    if (!m) throw new Error(`mark wk:s${k} never arrived`);
    const comp = await waitFor(() => find('Composite', (r) => r.startTime > m.startTime), compositeMs);
    if (!comp) noComposite.push(k);
    await c.evaluate(`(async () => { ${RAF_HELPER} ${dtMs ? `__wk.advance(${dtMs});` : ''} for (let f = 0; f < ${quiet}; f++) await raf(); performance.mark('wk:q${k}'); })(); 1`);
    if (!(await waitFor(() => stamp(`wk:q${k}`), 5000))) throw new Error(`mark wk:q${k} never arrived`);
  }
  await c.evaluate("performance.mark('wk:end'); 1");
  if (!(await waitFor(() => stamp('wk:end'), 5000))) throw new Error('mark wk:end never arrived');
  return { noComposite };
}

/**
 * Warm-up (experiment (d), beyond the brief): scroll once through the whole page in 400 px steps with a real 200 ms
 * pause each (lets lazy images, observers and decodes happen), come back to the top and idle 2 s. What follows measures a
 * page whose lazy resources have already arrived: it removes network-arrival timing from the counts, and it also
 * removes the cost of first-time loads, so it changes WHAT is measured (a warm scroll, not a cold one).
 */
async function warmUp(c, maxY) {
  await c.runAsync(`(async () => { const w = (ms) => new Promise((r) => setTimeout(r, ms));
    for (let y = 0; y <= ${maxY}; y += 400) { scrollTo({ top: y, behavior: 'instant' }); await w(200); }
    scrollTo({ top: ${maxY}, behavior: 'instant' }); await w(500);
    scrollTo({ top: 0, behavior: 'instant' }); await w(2000); return scrollY; })()`);
}

/**
 * Run the scripted scroll on a loaded page.
 * @param {number} step px per step; @param {number} framesPerStep rAFs waited per step (also the quiet rAFs of `lock`)
 * @param {number} idleMs idle capture before the scroll (free-running page, no scroll)
 * @param {string} mode one of base | lock | hold | lock+hold, each optionally with +warm; base: the first design (in-page loop). lock: the Mac waits for a
 *   Composite and `framesPerStep` quiet rAFs per step. hold: the page's timers are held (needs `timers:'hold'` at load)
 *   and advanced by framesPerStep/60 s of virtual time per step. lock+hold: both.
 */
export async function scrollRun(c, { step = 50, framesPerStep = 2, idleMs = 0, mode = 'base' } = {}) {
  const lock = mode.includes('lock'), hold = mode.includes('hold'), warm = mode.includes('warm');
  const info = await pageInfo(c);
  const ys = schedule(info.maxY, step);
  if (warm) await warmUp(c, info.maxY);
  let holdStats = null;
  if (hold) {
    if (!(await c.evaluate('typeof window.__wk === "object"'))) throw new Error('mode hold needs the page loaded with timers:"hold"');
    holdStats = await c.evaluate('JSON.stringify(__wk.hold())').then(JSON.parse);
  }
  const dtMs = hold ? Math.round((framesPerStep * 1000 / 60) * 1000) / 1000 : 0;
  const tl = await startTimeline(c);
  if (idleMs) await sleep(idleMs);
  let finalY, lockInfo = null;
  // host record, outside the page: the harness's own timer lag over the scroll (hostmon.mjs); never read by a count
  const lag = lagMonitor(20);
  const wallStart = Date.now();
  if (lock) {
    lockInfo = await lockedSteps(c, tl, ys, { quiet: framesPerStep, dtMs });
    finalY = await c.evaluate('Math.round(scrollY)');
  } else {
    // a long poll interval: every poll is an inspector round trip inside the timed window
    finalY = await c.runAsync(STEP_JS(ys, framesPerStep, dtMs), { pollMs: 1000 });
  }
  const wallEnd = Date.now();
  const lagSamples = lag.stop();
  await sleep(300);
  const records = await tl.stop();
  const marks = markTimes(records, 'wk:s', ys.length);
  const endTime = markTime(records, 'wk:end');
  if (marks.some((t) => t === null) || endTime === null) {
    throw new Error(`step marks missing from the Timeline: ${marks.filter((t) => t === null).length} of ${ys.length} steps, end ${endTime !== null}`);
  }
  // who triggered the work: counts of "Parent>Child" over the record tree (top-level parent is '-'), within the steps only
  const parentPairs = {};
  const walk = (r, parent) => {
    if (r.startTime >= marks[0] && r.startTime < endTime && r.type !== 'TimeStamp') { const k = `${parent}>${r.type}`; parentPairs[k] = (parentPairs[k] || 0) + 1; }
    for (const ch of r.children || []) walk(ch, r.type);
  };
  for (const r of tl.top) walk(r, '-');
  const holdAfter = hold ? await c.evaluate('JSON.stringify(__wk.stats())').then(JSON.parse) : null;
  return {
    schema: 'fw.webkit.scroll/1', mode, info, step, framesPerStep, dtMs, ys, finalY, marks, endTime, records,
    holdStats, holdAfter, parentPairs, noComposite: lockInfo?.noComposite ?? null,
    scrollWallMs: Math.round((endTime - marks[0]) * 1000), // informational: wall clock, never a gate
    wall: { start: wallStart, end: wallEnd }, // Mac clock (ms) around the stepped scroll, to join host samples to steps
    lag: lagBuckets(lagSamples, wallStart, wallEnd, 250), // max timer lag (ms) per 250 ms bucket from wall.start
    reduced: reduceSteps(records, marks, endTime),
  };
}
