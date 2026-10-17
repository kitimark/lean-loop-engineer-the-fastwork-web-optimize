// Timeline records over a scripted scroll.
//
// The scroll is stepped by the page's own native requestAnimationFrame: step k does `scrollTo({top: y_k, behavior:
// 'instant'})` and then waits two animation frames, so the schedule is indexed by position and frame, not by wall
// clock (04-webkit-rendering-math.md §8). Every step is bracketed by a `performance.mark('wk:s<k>')`, which arrives in
// the Timeline as a TimeStamp record on the records' clock; rows are bucketed to steps by that (reduce.mjs).
// What this is NOT: a finger gesture. `scrollTo` does not set the scroll velocity that iOS tile coverage depends on
// (§3, §8.3), so tile counts need a real gesture run and are out of scope here.
//
// Output schema `fw.webkit.scroll/1`: { schema, info, step, framesPerStep, ys, marks, endTime, records, reduced }.
// `records`/`marks`/`endTime` are the RAW part (reduce.mjs documents it); `reduced` is reduce.mjs's interim reduction.
import { sleep } from './sim.mjs';
import { startTimeline } from './timeline.mjs';
import { markTimes, markTime, reduceSteps } from './reduce.mjs';
import { RAF_HELPER, pageInfo } from './page.mjs';

/** The scroll schedule: y = 0, step, 2*step ... up to and including maxY. */
export function schedule(maxY, step) {
  const ys = [];
  for (let y = 0; y < maxY; y += step) ys.push(y);
  ys.push(maxY);
  return ys;
}

const STEP_JS = (ys, framesPerStep) => `(async () => {
  ${RAF_HELPER}
  const ys = ${JSON.stringify(ys)};
  performance.mark('wk:begin');
  for (let k = 0; k < ys.length; k++) {
    performance.mark('wk:s' + k);
    scrollTo({ top: ys[k], behavior: 'instant' });
    for (let f = 0; f < ${framesPerStep}; f++) await raf();
  }
  performance.mark('wk:end');
  return Math.round(scrollY);
})()`;

/**
 * Run the scripted scroll on a loaded page.
 * @param {number} step px per step; @param {number} framesPerStep rAFs waited per step
 * @param {number} idleMs idle capture before the scroll (free-running page, no scroll)
 */
export async function scrollRun(c, { step = 50, framesPerStep = 2, idleMs = 0 } = {}) {
  const info = await pageInfo(c);
  const ys = schedule(info.maxY, step);
  const tl = await startTimeline(c);
  if (idleMs) await sleep(idleMs);
  // a long poll interval: every poll is an inspector round trip inside the timed window
  const finalY = await c.runAsync(STEP_JS(ys, framesPerStep), { pollMs: 1000 });
  await sleep(300);
  const records = await tl.stop();
  const marks = markTimes(records, 'wk:s', ys.length);
  const endTime = markTime(records, 'wk:end');
  if (marks.some((t) => t === null) || endTime === null) {
    throw new Error(`step marks missing from the Timeline: ${marks.filter((t) => t === null).length} of ${ys.length} steps, end ${endTime !== null}`);
  }
  return {
    schema: 'fw.webkit.scroll/1', info, step, framesPerStep, ys, finalY, marks, endTime, records,
    scrollWallMs: Math.round((endTime - marks[0]) * 1000), // informational: wall clock, never a gate
    reduced: reduceSteps(records, marks, endTime),
  };
}
