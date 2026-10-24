// One pass of the per-part throttle measure in an open session (I/O glue): fresh load, place the page for the mode, start the base
// recorder (hero: recorder.mjs; finish: finish-page.mjs) and the parts recorder (parts-recorder.mjs), let the XCUITest driver touch
// Mobile Safari, fetch both records. The base record keeps its shape (the existing report still reads the artifact); the parts
// record is added as `rec.parts`. Nothing is decided here; parts.mjs reduces.
//   drags  the page at the top, the hero exit drags (testDrags)
//   finish the page 300 px above its end, drags past the end (testFinish)
//   rest   the page placed on the ramp of one part (ANCHORS[round % 3], found by scanning the page), then the testDrags drags
import { readFileSync } from 'node:fs';
import { loadavg } from 'node:os';
import { loadFresh, pageInfo } from '../page.mjs';
import { sleep } from '../sim.mjs';
import { dragPass } from './driver.mjs';
import * as hero from './recorder.mjs';
import * as fin from './finish-page.mjs';
import { GAP_PX, NEAR_END_SETTLE_MS } from './finish-probe.mjs';
import * as parts from './parts-recorder.mjs';

export const MODES = Object.freeze(['drags', 'finish', 'rest']);
export const ANCHOR_SETTLE_MS = 1800;

/** The last 2000 characters of the driver's log with device ids and home paths removed. */
function logTail(file) {
  try {
    return readFileSync(file, 'utf8').slice(-2000)
      .replace(/[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}/gi, '<id>').replace(/\/Users\/[^/\s]+/g, '<home>');
  } catch { return null; }
}

/** The series a rest pass is placed on in round `round` (1-based). */
export const anchorOf = (round) => parts.ANCHORS[(Math.max(1, round) - 1) % parts.ANCHORS.length];

/** @returns the pass record: page facts, where the page stood, the drag run's exit, the base frames with `rec.parts` added; or {skipped} when the anchor series never ramps. */
export async function partsPass(ctx, { driver, udid, drag, mode, round = 1, settleMs = 6000, tag = 'pass' }) {
  if (!MODES.includes(mode)) throw new Error(`unknown parts mode ${mode}`);
  const { c, log } = ctx;
  const base = mode === 'finish' ? fin : hero;
  await loadFresh(c, { clock: 'pinned', settleMs });
  const info = await pageInfo(c);
  const where = {};
  if (mode === 'finish') {
    Object.assign(where, JSON.parse(await c.evaluate(fin.nearEndJs(GAP_PX))));
    await sleep(NEAR_END_SETTLE_MS);
  } else if (mode === 'rest') {
    const key = anchorOf(round);
    const found = JSON.parse(await c.runAsync(parts.discoverJs(), { pollMs: 200 }));
    const y = parts.anchorY(found.at[key] ?? null);
    where.anchor = key; where.rampAt = found.at; where.maxY = found.maxY;
    if (y === null) {
      log(`${tag}: ${key} never ramps on this page, no touches`);
      return { info: { ua: info.ua, vw: info.vw, vh: info.vh, dpr: info.dpr, docH: info.docH, fw: info.fw }, where, skipped: `anchor ${key} not found` };
    }
    where.y = JSON.parse(await c.evaluate(parts.scrollToJs(y))).y;
    await sleep(ANCHOR_SETTLE_MS);
  }
  for (const js of [base.START_JS, parts.START_JS]) {
    const started = await c.evaluate(js);
    if (started !== 'started') throw new Error(`a recorder did not start (${started})`);
  }
  log(`${tag}: page recording (${mode}), load ${loadavg()[0].toFixed(0)}`);
  const t0 = Date.now();
  const run = await dragPass(driver, { udid, tag, log, ...drag, mode: mode === 'finish' ? 'finish' : 'drags' });
  log(`${tag}: touches ${run.code === 0 ? 'done' : `failed (code ${run.code}${run.timedOut ? ', timed out' : ''}; log ${run.logFile})`} in ${Math.round((Date.now() - t0) / 1000)} s`);
  await sleep(500);
  const rec = JSON.parse(await c.evaluate(base.FETCH_JS));
  if (rec.err) throw new Error(rec.err);
  const pr = JSON.parse(await c.evaluate(parts.FETCH_JS));
  if (pr.err) throw new Error(pr.err);
  rec.parts = pr;
  return {
    info: { ua: info.ua, vw: info.vw, vh: info.vh, dpr: info.dpr, docH: info.docH, fw: info.fw },
    where,
    drag: { code: run.code, timedOut: run.timedOut, signal: run.signal, tail: run.code === 0 ? null : logTail(run.logFile) },
    rec,
  };
}
