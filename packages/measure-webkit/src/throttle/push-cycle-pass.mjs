import { loadavg } from 'node:os';
import { loadFresh, pageInfo } from '../page.mjs';
import { sleep } from '../sim.mjs';
import { dragPass } from './driver.mjs';
import { START_JS, FETCH_JS, nearEndJs } from './finish-page.mjs';
import { EXTRA_START_JS, EXTRA_FETCH_JS } from './push-cycle-page.mjs';
import { GAP_PX, NEAR_END_SETTLE_MS } from './finish-probe.mjs';

export async function pushCyclePass(ctx, { driver, udid, drag, gapPx = GAP_PX, settleMs = 6000, tag = 'pass' }) {
  const { c, log } = ctx;
  await loadFresh(c, { clock: 'pinned', settleMs });
  const info = await pageInfo(c);
  const near = JSON.parse(await c.evaluate(nearEndJs(gapPx)));
  await sleep(NEAR_END_SETTLE_MS);
  const started = await c.evaluate(START_JS);
  if (started !== 'started') throw new Error(`the recorder did not start (${started})`);
  const extra = await c.evaluate(EXTRA_START_JS);
  if (extra !== 'started') throw new Error(`the viewport recorder did not start (${extra})`);
  log(`${tag}: page recording ${Math.round(near.maxY - near.y)} px above the end, load ${loadavg()[0].toFixed(0)}, ${drag.cycles} cycles, dwell ${drag.holdMs} ms`);
  const t0 = Date.now();
  const run = await dragPass(driver, { udid, tag, log, mode: 'finish', ...drag });
  log(`${tag}: touches ${run.code === 0 ? 'done' : `failed (code ${run.code}${run.timedOut ? ', timed out' : ''})`} in ${Math.round((Date.now() - t0) / 1000)} s`);
  await sleep(500);
  const rec = JSON.parse(await c.evaluate(FETCH_JS));
  if (rec.err) throw new Error(rec.err);
  const x = JSON.parse(await c.evaluate(EXTRA_FETCH_JS));
  return {
    info: { ua: info.ua, vw: info.vw, vh: info.vh, dpr: info.dpr, docH: info.docH, fw: info.fw },
    near,
    drag: { code: run.code, timedOut: run.timedOut, signal: run.signal, tail: null },
    rec: { ...rec, rz: x.rz, vvr: x.vvr, vvs: x.vvs },
  };
}
