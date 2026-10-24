// One finish pass of the toolbar-throttle probe in an open session (I/O glue): fresh load, scroll near the page end, start the page
// recorder, let the XCUITest driver drag past the end, fetch the record. Nothing is decided here; finish-report.mjs and finish.mjs reduce.
import { readFileSync } from 'node:fs';
import { loadavg } from 'node:os';
import { loadFresh, pageInfo } from '../page.mjs';
import { sleep } from '../sim.mjs';
import { dragPass } from './driver.mjs';
import { START_JS, FETCH_JS, nearEndJs } from './finish-page.mjs';

export const GAP_PX = 300;
export const NEAR_END_SETTLE_MS = 1800;

/** The last 2000 characters of the driver's log with device ids and home paths removed. */
function logTail(file) {
  try {
    return readFileSync(file, 'utf8').slice(-2000)
      .replace(/[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}/gi, '<id>').replace(/\/Users\/[^/\s]+/g, '<home>');
  } catch { return null; }
}

/** @returns the pass record: page facts, where the page stood before the touches, the drag run's exit, the frames (t ms, y/mx/ih/vh tenth px, o 0/1) */
export async function finishPass(ctx, { driver, udid, drag, gapPx = GAP_PX, settleMs = 6000, tag = 'pass' }) {
  const { c, log } = ctx;
  await loadFresh(c, { clock: 'pinned', settleMs });
  const info = await pageInfo(c);
  const near = JSON.parse(await c.evaluate(nearEndJs(gapPx)));
  await sleep(NEAR_END_SETTLE_MS);
  const started = await c.evaluate(START_JS);
  if (started !== 'started') throw new Error(`the recorder did not start (${started})`);
  log(`${tag}: page recording ${Math.round(near.maxY - near.y)} px above the end, load ${loadavg()[0].toFixed(0)}`);
  const t0 = Date.now();
  const run = await dragPass(driver, { udid, tag, log, mode: 'finish', ...drag });
  log(`${tag}: touches ${run.code === 0 ? 'done' : `failed (code ${run.code}${run.timedOut ? ', timed out' : ''}; log ${run.logFile})`} in ${Math.round((Date.now() - t0) / 1000)} s`);
  await sleep(500);
  const rec = JSON.parse(await c.evaluate(FETCH_JS));
  if (rec.err) throw new Error(rec.err);
  return {
    info: { ua: info.ua, vw: info.vw, vh: info.vh, dpr: info.dpr, docH: info.docH, fw: info.fw },
    near,
    drag: { code: run.code, timedOut: run.timedOut, signal: run.signal, tail: run.code === 0 ? null : logTail(run.logFile) },
    rec,
  };
}
