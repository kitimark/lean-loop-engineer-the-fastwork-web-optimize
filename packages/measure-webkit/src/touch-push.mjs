// The end-of-page push through real touches (I/O glue): the XCUITest driver of the toolbar-throttle probe swipes Mobile Safari while
// the page records. morph.tween reacts to touchmove as well as wheel (apps/site/src/parts/morph.tween/driver.ts onTouchMove), so a
// finger swipe up at the end of the page opens the morph and a swipe down closes it. Nothing is decided here.
import { dragPass, findDriver } from './throttle/driver.mjs';
import { sleep } from './sim.mjs';

/** One swipe up (opens), hold, one swipe down (closes), hold: 300 pt at 600 pt/s, each hold 1 s. */
export const TOUCH_PUSH = Object.freeze({ cycles: 1, dragPt: 300, velocity: 600, holdMs: 1000 });

/** The prebuilt driver in `dir`, or null with the reason. */
export function openDriver(dir) {
  if (!dir) return { driver: null, why: 'no driver directory given' };
  try { return { driver: findDriver(dir), why: null }; } catch (e) { return { driver: null, why: `driver not built (${e.message.replace(/\/Users\/[^/\s]+/g, '<home>')})` }; }
}

/** In-page: counts the touches the page receives. Install once per load, before the touches. */
export const TOUCH_COUNT_JS = `(() => {
  const w = window.__fwTouch = { starts: 0, moves: 0 };
  addEventListener('touchstart', () => { w.starts++; }, { capture: true, passive: true });
  addEventListener('touchmove', () => { w.moves++; }, { capture: true, passive: true });
  return true;
})()`;

/**
 * Run `pageJs` (a promise that ends when `window.__fwTouchStop` is set) while the driver touches. Resolves
 * {run, result, error}: `run` is the driver's exit, `result` the page value, `error` why the page value is missing.
 */
export async function touchWindow(c, { driver, udid, tag, log = () => {}, pageJs, drag = TOUCH_PUSH, pollMs = 500, tailMs = 600, lostMs = 20000 }) {
  await c.evaluate('window.__fwTouchStop = false; true');
  const page = c.runAsync(pageJs, { pollMs, timeoutMs: 150000 }).then((result) => ({ result }), (e) => ({ error: e.message }));
  const run = await dragPass(driver, { udid, tag, log, ...drag });
  await sleep(tailMs);
  await c.evaluate('window.__fwTouchStop = true; true').catch(() => {});
  const got = await Promise.race([page, sleep(lostMs).then(() => ({ error: 'the page did not answer after the touches (reloaded?)' }))]);
  return { run: { code: run.code, timedOut: run.timedOut }, ...got };
}
