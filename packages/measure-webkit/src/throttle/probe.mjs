// One pass of the toolbar-throttle probe in an open session (I/O glue): fresh load, start the page recorder, let the XCUITest
// driver touch Mobile Safari, fetch the record. Nothing is decided here; report.mjs and stillruns.mjs reduce the records.
import { readFileSync } from 'node:fs';
import { loadavg } from 'node:os';
import { loadFresh, pageInfo } from '../page.mjs';
import { sleep } from '../sim.mjs';
import { dragPass } from './driver.mjs';
import { START_JS, FETCH_JS } from './recorder.mjs';

/** The last 2000 characters of the driver's log with device ids and home paths removed. */
function logTail(file) {
  try {
    return readFileSync(file, 'utf8').slice(-2000)
      .replace(/[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}/gi, '<id>').replace(/\/Users\/[^/\s]+/g, '<home>');
  } catch { return null; }
}

/** @returns the pass record: page facts, the drag run's exit, the frames (t ms, y tenth px, v per mille, ih/vh tenth px) */
export async function armPass(ctx, { driver, udid, drag, settleMs = 6000, tag = 'pass' }) {
  const { c, log } = ctx;
  await loadFresh(c, { clock: 'pinned', settleMs });
  const info = await pageInfo(c);
  const started = await c.evaluate(START_JS);
  if (started !== 'started') throw new Error(`the recorder did not start (${started})`);
  log(`${tag}: page recording, load ${loadavg()[0].toFixed(0)}`);
  const t0 = Date.now();
  const run = await dragPass(driver, { udid, tag, ...drag });
  log(`${tag}: touches ${run.code === 0 ? 'done' : `failed (code ${run.code}${run.timedOut ? ', timed out' : ''}; log ${run.logFile})`} in ${Math.round((Date.now() - t0) / 1000)} s`);
  await sleep(500);
  const rec = JSON.parse(await c.evaluate(FETCH_JS));
  if (rec.err) throw new Error(rec.err);
  return {
    info: { ua: info.ua, vw: info.vw, vh: info.vh, dpr: info.dpr, docH: info.docH, fw: info.fw },
    drag: { code: run.code, timedOut: run.timedOut, signal: run.signal, tail: run.code === 0 ? null : logTail(run.logFile) },
    rec,
  };
}
