// One toolbar pass in an open session (I/O glue): the finish pass of finish-probe.mjs (fresh load, near the page end, recorder, real touches,
// fetch) with one bounded Timeline window around the first press of the second cycle (gesture 4, the drag past the end that opens the morph).
// Why one short window and not the pass: a Timeline over a whole touch window held 20 to 40 thousand records and its stop timed out
// (research/notes/2026/10-2x-sim-touch-reliable.md), so the window is bounded by Lean `winPhase` (closed at gesture 5 or after 10 s).
// Nothing is decided here beyond feeding `winPhase`; toolbar.mjs and toolbar-report.mjs reduce.
import { readFileSync } from 'node:fs';
import { loadavg } from 'node:os';
import { loadFresh, pageInfo } from '../page.mjs';
import { sleep } from '../sim.mjs';
import { T } from '../timeouts.mjs';
import { startTimeline } from '../timeline.mjs';
import { tally } from '../reduce.mjs';
import { dragPass } from './driver.mjs';
import { START_TB_JS, FETCH_TB_JS, COUNT_TB_JS, nearEndJs } from './toolbar-page.mjs';
import { GAP_PX, NEAR_END_SETTLE_MS } from './finish-probe.mjs';
import { winPhase, winCounts } from './toolbar.mjs';

export const POLL_MS = 250;

/** The last 2000 characters of the driver's log with device ids and home paths removed. */
function logTail(file) {
  try {
    return readFileSync(file, 'utf8').slice(-2000)
      .replace(/[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}/gi, '<id>').replace(/\/Users\/[^/\s]+/g, '<home>');
  } catch { return null; }
}

const NO_COST = { layout: 0, recalc: 0, frames: 0 };

/** Poll the gesture counter while the touches run; open the Timeline when Lean says record, close it when Lean says done or the touches end. */
export function windowWatcher(c, { log, tag }, deps = {}) {
  const d = { startTimeline, sleep, now: Date.now, ...deps };
  const state = { stop: false, cost: { ...NO_COST, note: 'window never opened' } };
  const run = (async () => {
    let tl = null, at = 0, g0 = 0, startMs = 0;
    const close = async (why, seen) => {
      const t = tl; tl = null;
      const sent = d.now();
      let g1 = seen?.g ?? null;
      if (g1 === null) {
        try { g1 = JSON.parse(await c.evaluate(COUNT_TB_JS)).g; } catch (e) { log(`${tag}: window end read failed: ${e.message}`); }
      }
      const spanMs = sent - at;
      try {
        const rows = await t.stop();
        const k = tally(rows).counts;
        state.cost = {
          layout: k.Layout, recalc: k.RecalculateStyles, frames: k.RenderingFrame, rows: rows.length, spanMs, stopMs: d.now() - sent, startMs, g0, g1, why,
          counts: g1 !== null && winCounts(g1, spanMs),
        };
        log(`${tag}: window ${why}: ${rows.length} records, ${k.RenderingFrame} frames, Layout ${k.Layout}, RecalculateStyles ${k.RecalculateStyles}, gestures ${g0} to ${g1}, span ${spanMs} ms, start ${startMs} ms, stop ${state.cost.stopMs} ms, ${state.cost.counts ? 'counts' : 'overran'}`);
      } catch (e) {
        state.cost = { ...NO_COST, error: e.message, why, spanMs, startMs, g0, g1, counts: false };
        log(`${tag}: Timeline stop failed: ${e.message}`);
      }
    };
    for (;;) {
      await d.sleep(POLL_MS);
      if (state.stop) { if (tl) await close('touches ended', null); return; }
      let cnt = null;
      try { cnt = JSON.parse(await c.evaluate(COUNT_TB_JS)); } catch (e) { log(`${tag}: window poll failed: ${e.message}`); }
      if (!cnt) continue;
      const phase = winPhase(cnt.g, tl ? d.now() - at : null);
      if (phase === 'record' && !tl) {
        try {
          const s0 = d.now();
          tl = await d.startTimeline(c, { stopMs: T(15000) });
          at = d.now(); startMs = at - s0; g0 = cnt.g;
        } catch (e) { state.cost = { ...NO_COST, error: `Timeline start failed: ${e.message}` }; log(`${tag}: ${state.cost.error}`); return; }
      } else if (phase === 'done') {
        if (tl) await close(cnt.g > 4 ? 'next gesture' : 'cap', cnt);
        else state.cost = { ...NO_COST, note: 'window missed (gesture counter past the start)' };
        return;
      }
    }
  })();
  return { state, done: run };
}

/** @returns the pass record: page facts, the touch run's exit, the frames, and the window's Timeline counts as `cost` */
export async function toolbarPass(ctx, { driver, udid, drag, gapPx = GAP_PX, settleMs = 6000, tag = 'pass' }) {
  const { c, log } = ctx;
  await loadFresh(c, { clock: 'pinned', settleMs });
  const info = await pageInfo(c);
  const near = JSON.parse(await c.evaluate(nearEndJs(gapPx)));
  await sleep(NEAR_END_SETTLE_MS);
  const started = await c.evaluate(START_TB_JS);
  if (started !== 'started') throw new Error(`the recorder did not start (${started})`);
  log(`${tag}: page recording ${Math.round(near.maxY - near.y)} px above the end, load ${loadavg()[0].toFixed(0)}`);
  const t0 = Date.now();
  const w = windowWatcher(c, { log, tag });
  let run;
  try { run = await dragPass(driver, { udid, tag, log, mode: 'finish', ...drag }); } finally { w.state.stop = true; }
  await w.done;
  log(`${tag}: touches ${run.code === 0 ? 'done' : `failed (code ${run.code}${run.timedOut ? ', timed out' : ''}; log ${run.logFile})`} in ${Math.round((Date.now() - t0) / 1000)} s`);
  await sleep(500);
  const rec = JSON.parse(await c.evaluate(FETCH_TB_JS));
  if (rec.err) throw new Error(rec.err);
  return {
    info: { ua: info.ua, vw: info.vw, vh: info.vh, dpr: info.dpr, docH: info.docH, fw: info.fw },
    near,
    drag: { code: run.code, timedOut: run.timedOut, signal: run.signal, tail: run.code === 0 ? null : logTail(run.logFile) },
    rec,
    cost: w.state.cost,
  };
}
