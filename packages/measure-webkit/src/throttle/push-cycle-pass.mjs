import { loadavg } from 'node:os';
import { loadFresh, pageInfo } from '../page.mjs';
import { sleep } from '../sim.mjs';
import { takeCensus } from '../census.mjs';
import { dragPass } from './driver.mjs';
import { START_JS, FETCH_JS, nearEndJs } from './finish-page.mjs';
import { EXTRA_START_JS, EXTRA_FETCH_JS } from './push-cycle-page.mjs';
import { GAP_PX, NEAR_END_SETTLE_MS } from './finish-probe.mjs';
import { restMs, SEP_DWELL_CYCLES } from './push-cycle.mjs';

const CENSUS_SETTLE_MS = 2000;
const CENSUS_WINDOW_MS = 300;

const pageNow = async (c) => Number(await c.evaluate('String(performance.now())'));

/** One census point: layers, backing-store bytes, and the layers whose id was not in the previous census (created since). */
async function censusPoint(c, k, seen) {
  const t0 = await pageNow(c);
  const x = await takeCensus(c, { paintWindowMs: CENSUS_WINDOW_MS, withReasons: false, withNames: false });
  const t1 = await pageNow(c);
  const ids = new Set(x.layers.map((l) => l.layerId));
  const created = [...ids].filter((id) => !seen.has(id)).length;
  return { point: { k, layers: x.layerCount, bytes: x.memoryBytes, created, paintTotal: x.paintCountTotal, atMs: Math.round(t0), tookMs: Math.round(t1 - t0) }, ids };
}

/**
 * One pass. profile `full`: one continuous touch run of drag.cycles cycles. profile `dwell` (task push-cycle-separate): one touch run per cycle
 * (SEP_DWELL_CYCLES of them), and between two runs a census and a rest that fills the period to `targetMs` (Lean restMs, capped at `restCapMs`).
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
  let seen = new Set();
  const pre = await censusPoint(c, -1, seen);
  census.push(pre.point); seen = pre.ids;
  const started = await c.evaluate(START_JS);
  if (started !== 'started') throw new Error(`the recorder did not start (${started})`);
  const extra = await c.evaluate(EXTRA_START_JS);
  if (extra !== 'started') throw new Error(`the viewport recorder did not start (${extra})`);
  const n = profile === 'dwell' ? SEP_DWELL_CYCLES : drag.cycles;
  log(`${tag}: page recording ${Math.round(near.maxY - near.y)} px above the end, load ${loadavg()[0].toFixed(0)}, ${n} cycles, ${profile} profile, hold ${drag.holdMs} ms`);
  const t0 = Date.now();
  const calls = [], quiet = [];
  let run = null;
  if (profile === 'dwell') {
    for (let k = 0; k < n; k++) {
      const began = Date.now(), beganPage = await pageNow(c);
      run = await dragPass(driver, { udid, tag: `${tag}-c${k + 1}`, log, ...drag, mode: 'finish', cycles: 1 });
      const endPage = await pageNow(c);
      calls.push({ k, code: run.code, beganMs: Math.round(beganPage), endMs: Math.round(endPage) });
      log(`${tag}: cycle ${k + 1} touches ${run.code === 0 ? 'done' : `failed (code ${run.code}${run.timedOut ? ', timed out' : ''})`}`);
      if (run.code !== 0) break;
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
    calls.push({ k: 0, code: run.code, beganMs: null, endMs: null });
  }
  log(`${tag}: touches ${run.code === 0 ? 'done' : `failed (code ${run.code}${run.timedOut ? ', timed out' : ''})`} in ${Math.round((Date.now() - t0) / 1000)} s`);
  await sleep(500);
  const rec = JSON.parse(await c.evaluate(FETCH_JS));
  if (rec.err) throw new Error(rec.err);
  const x = JSON.parse(await c.evaluate(EXTRA_FETCH_JS));
  const post = await censusPoint(c, n, seen);
  census.push(post.point);
  return {
    profile, targetMs: profile === 'dwell' ? targetMs : null,
    info: { ua: info.ua, vw: info.vw, vh: info.vh, dpr: info.dpr, docH: info.docH, fw: info.fw },
    near,
    drag: { code: run.code, timedOut: run.timedOut, signal: run.signal, tail: null },
    calls, census,
    rec: { ...rec, rz: x.rz, vvr: x.vvr, vvs: x.vvs, quiet },
  };
}
