import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadavg } from 'node:os';
import { loadFresh, pageInfo } from '../page.mjs';
import { sleep } from '../sim.mjs';
import { takeCensus } from '../census.mjs';
import { dragPass } from './driver.mjs';
import { startServer, stopServer, logTail } from '../touch-push.mjs';
import { START_JS, FETCH_JS, nearEndJs } from './finish-page.mjs';
import { EXTRA_START_JS, EXTRA_FETCH_JS, STAMP_JS, COLS_LOG_JS, COLS_LOG_FETCH_JS } from './push-cycle-page.mjs';
import { startTimeline } from '../timeline.mjs';
import { buildPushSegs, stampSync } from './morph-push.mjs';
import { GAP_PX, NEAR_END_SETTLE_MS } from './finish-probe.mjs';
import { restMs, SEP_DWELL_CYCLES } from './push-cycle.mjs';

const CENSUS_SETTLE_MS = 2000;
const CENSUS_WINDOW_MS = 300;
const SERVER_READY_MS = 420000;
const SERVER_MAX_S = 2400;
const CYCLE_DONE_MS = 180000;

const pageNow = async (c) => Number(await c.evaluate('String(performance.now())'));

/**
 * One census point: layers, backing-store bytes, and `created`, the layers of this census that the previous one has no layer of the same geometry for.
 * Layer ids are handed out again by every census (the LayerTree domain is switched off between two: run 40284577163 read created = layers at every point),
 * so a layer is matched by its bounds, composited bounds and pseudo-element; a layer that moved counts as created (an upper bound).
 */
async function censusPoint(c, k, seen) {
  const t0 = await pageNow(c);
  const x = await takeCensus(c, { paintWindowMs: CENSUS_WINDOW_MS, withReasons: false, withNames: false });
  const t1 = await pageNow(c);
  const keys = new Map();
  for (const l of x.layers) { const key = `${l.bounds}|${l.compositedBounds}|${l.pseudo ?? ''}`; keys.set(key, (keys.get(key) ?? 0) + 1); }
  let created = 0;
  for (const [key, n] of keys) created += Math.max(0, n - (seen.get(key) ?? 0));
  return { point: { k, layers: x.layerCount, bytes: x.memoryBytes, created, paintTotal: x.paintCountTotal, atMs: Math.round(t0), tookMs: Math.round(t1 - t0) }, ids: keys };
}

/** One finish cycle from the server: write go-<n>, wait for done-<n> (or for the driver to end); the press durations, or null on a miss. */
async function askCycle(server, doneMs) {
  const n = server.next++;
  writeFileSync(join(server.dir, `go-${n}`), 'springboard');
  const doneFile = join(server.dir, `done-${n}`);
  const t0 = Date.now();
  while (!existsSync(doneFile) && !server.run.state.ended && Date.now() - t0 < doneMs) await sleep(100);
  if (!existsSync(doneFile)) return null;
  try { return readFileSync(doneFile, 'utf8').trim().split(/\s+/).slice(1).map(Number); } catch { return []; }
}

/**
 * One pass. profile `full`: one continuous touch run of drag.cycles cycles (DragTests.testFinish). profile `dwell` (task push-cycle-separate): SEP_DWELL_CYCLES
 * cycles asked one at a time from one long XCUITest run (FinishServer.swift: the same presses as testFinish, one cycle per request), and between two
 * cycles a census and a rest that fills the period to `targetMs` (Lean restMs, capped at `restCapMs`); one xcodebuild start per pass, so the period is the
 * rest's to set (a run with one xcodebuild start per cycle spent 76 to 296 s on each start: run 40284577163).
 * The census and the rests are recorded as `quiet` page-time ranges: recordCycles does not count their frames. Both profiles take a census
 * before the first touch and after the last; the dwell profile also after every cycle.
 */
export async function pushCyclePass(ctx, { driver, udid, drag, gapPx = GAP_PX, settleMs = 6000, tag = 'pass', profile = 'full', targetMs = 0, restCapMs = 120000 }) {
  const { c, log } = ctx;
  await loadFresh(c, { clock: 'pinned', settleMs });
  const info = await pageInfo(c);
  const near = JSON.parse(await c.evaluate(nearEndJs(gapPx)));
  await sleep(NEAR_END_SETTLE_MS);
  const census = [];
  let seen = new Map();
  const pre = await censusPoint(c, -1, seen);
  census.push(pre.point); seen = pre.ids;
  const n = profile === 'dwell' ? SEP_DWELL_CYCLES : drag.cycles;
  const asked = profile === 'dwell' || profile === 'push';
  const pageOut = { ua: info.ua, vw: info.vw, vh: info.vh, dpr: info.dpr, docH: info.docH, fw: info.fw };
  let server = null;
  if (asked) {
    try {
      server = await startServer(driver, { udid, log: (l) => log(`${tag}: ${l}`), push: { dragPt: drag.dragPt, velocity: drag.velocity, holdMs: drag.holdMs }, maxS: SERVER_MAX_S, readyMs: SERVER_READY_MS, tag: `${tag}-srv`, suite: 'FinishServer' });
    } catch (e) {
      log(`${tag}: ${e.message.split('; log tail')[0]}`);
      return { profile, targetMs, info: pageOut, near, drag: { code: 1, timedOut: false, signal: null, tail: e.message.slice(-1500) }, calls: [], census, rec: null };
    }
  }
  try {
    const segs = [];
    if (profile === 'push') { await c.evaluate(STAMP_JS); await c.evaluate(COLS_LOG_JS); }
    const started = await c.evaluate(START_JS);
    if (started !== 'started') throw new Error(`the recorder did not start (${started})`);
    const extra = await c.evaluate(EXTRA_START_JS);
    if (extra !== 'started') throw new Error(`the viewport recorder did not start (${extra})`);
    log(`${tag}: page recording ${Math.round(near.maxY - near.y)} px above the end, load ${loadavg()[0].toFixed(0)}, ${n} cycles, ${profile} profile, hold ${drag.holdMs} ms`);
    const t0 = Date.now();
    const calls = [], quiet = [];
    let run = null, tail = null;
    if (asked) {
      run = { code: 0, timedOut: false, signal: null };
      for (let k = 0; k < n; k++) {
        const began = Date.now();
        const tl = profile === 'push' ? await startTimeline(c).catch((e) => { log(`${tag}: cycle ${k + 1}: no timeline (${e.message})`); return null; }) : null;
        if (tl) log(`${tag}: cycle ${k + 1}: timeline up`);
        const beganPage = profile === 'push' ? null : await pageNow(c);
        const presses = await askCycle(server, CYCLE_DONE_MS);
        log(`${tag}: cycle ${k + 1}: asked ${presses === null ? 'without an answer' : 'and answered'}`);
        const endPage = profile === 'push' ? null : await pageNow(c);
        calls.push({ k, ok: presses !== null, beganMs: beganPage === null ? null : Math.round(beganPage), endMs: endPage === null ? null : Math.round(endPage), presses });
        log(`${tag}: cycle ${k + 1} ${presses === null ? 'failed (no answer from the driver)' : `done, presses ${presses.join(' ')} ms`}`);
        if (tl) { // no host evaluate in this path: the page stamps itself (STAMP_JS)
          await sleep(300);
          try {
            const rows = await tl.stop();
            const g = stampSync(rows);
            log(`${tag}: cycle ${k + 1}: timeline stopped, ${rows.length} rows${g ? '' : ', no stamps'}`);
            if (g) segs.push({ rows, ...g });
          } catch (e) { log(`${tag}: cycle ${k + 1}: timeline stop failed (${e.message})`); }
        }
        if (presses === null) { run = { code: 1, timedOut: !server.run.state.ended, signal: null }; tail = logTail(server.run.logFile); break; }
        if (profile === 'push') continue;
        await sleep(CENSUS_SETTLE_MS);
        const cp = await censusPoint(c, k, seen);
        census.push(cp.point); seen = cp.ids;
        const rest = k + 1 < n ? restMs(targetMs, Date.now() - began, restCapMs) : 0;
        log(`${tag}: cycle ${k + 1}: ${cp.point.layers} layers, ${cp.point.bytes} B, ${cp.point.created} created; rest ${rest} ms`);
        if (rest > 0) await sleep(rest);
        quiet.push([endPage, await pageNow(c)]);
      }
    } else {
      run = await dragPass(driver, { udid, tag, log, ...drag, mode: 'finish' });
      calls.push({ k: 0, ok: run.code === 0, beganMs: null, endMs: null, presses: null });
    }
    log(`${tag}: touches ${run.code === 0 ? 'done' : `failed (code ${run.code}${run.timedOut ? ', timed out' : ''})`} in ${Math.round((Date.now() - t0) / 1000)} s`);
    await sleep(500);
    const endP = await pageNow(c);
    const rec = JSON.parse(await c.evaluate(FETCH_JS));
    if (rec.err) throw new Error(rec.err);
    const x = JSON.parse(await c.evaluate(EXTRA_FETCH_JS));
    const takeLog = profile === 'push' ? JSON.parse(await c.evaluate(COLS_LOG_FETCH_JS)) : [];
    if (server) { await stopServer(server); server = null; }
    const pushOut = profile === 'push' ? buildPushSegs({ segs, endP, rafs: x.raf ?? [], rec }) : null;
    if (pushOut) log(`${tag}: ${pushOut.starts.length} pushes, ${pushOut.rows.length} style/layout/paint rows and ${pushOut.rafs.length} page rAF requests in their windows, sync drift ${pushOut.drift} ms`);
    const post = await censusPoint(c, n, seen);
    census.push(post.point);
    return {
      profile, targetMs: profile === 'dwell' ? targetMs : null,
      info: pageOut, near,
      drag: { code: run.code, timedOut: run.timedOut, signal: run.signal, tail },
      calls, census,
      rec: { ...rec, rz: x.rz, vvr: x.vvr, vvs: x.vvs, quiet },
      ...(pushOut ? { push: pushOut } : {}),
      ...(takeLog.length ? { takeLog } : {}),
    };
  } finally { if (server) await stopServer(server); }
}
