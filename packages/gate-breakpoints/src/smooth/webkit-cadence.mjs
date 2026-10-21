// WebKit leg 1 of the smoothness-webkit-cadence lane: Playwright WebKit on a macOS runner, one browser process for all arms, a real
// wheel at the Chromium lane's schedule, the WebKit Timeline read per frame of each window. Glue only: the zone binning, the
// per-frame tallies and the clock-offset rule are Lean's (lean/Fw/Measure/WebKitProfile.lean, twin measure-webkit/src/profile/reduce.mjs).
//
// Arms are resolved by their flags (Lean's dedup, device-arms.mjs `sessionPlan`), never by preset name: `orig` (the snapshot),
// `base` (the faithful rewrite), `aa` (a second server of the same rewrite, the control outside the dedup), `look` (the look-change
// flags) and `v2` only when its flags differ from the rewrite's. Each window opens a fresh page per arm; arms are interleaved per
// rep and the order rotates (`orderFor`). Event reps run with the Timeline on; cadence reps run without it (the Timeline slows the
// page), so the two are reported apart.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { webkit } from 'playwright-core';
import { PIN_SRC, waitReady } from '../page.mjs';
import { startServer, snapshotRoot, siteDist, rewriteFor } from '../serve.mjs';
import { envFor } from '../trajectory/registry.mjs';
import { runCheck } from '../trajectory/reduce.mjs';
import { HERO_BURST, END_PUSH, orderFor } from './cadence.mjs';
import { hitches } from './reduce.mjs';
import { RECORDER_SRC, TO_END_JS, pageOf, intervalsOf } from '../../../measure-webkit/src/profile/recorder.mjs';
import { profileWindow, toHundredths } from '../../../measure-webkit/src/profile/reduce.mjs';
import { sessionPlan } from '../../../measure-webkit/src/device-arms.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => process.stderr.write(`${a.join(' ')}\n`);

/** The server-side protocol session of a Playwright WebKit page (the in-process server object, as engines.mjs `resize` reaches it). */
function sessionOf(page) {
  const sess = page._connection?.toImpl?.(page)?.delegate?._session;
  if (!sess || typeof sess.send !== 'function' || typeof sess.on !== 'function') throw new Error('the WebKit protocol session of the page is not reachable (playwright-core internals changed)');
  return sess;
}

/** Start the WebKit Timeline on a page; `stop()` returns the raw protocol records once the closing mark has arrived. */
async function startTimeline(page) {
  const sess = sessionOf(page);
  const recs = [];
  const on = (p) => recs.push(p.record);
  sess.on('Timeline.eventRecorded', on);
  await sess.send('Timeline.setInstruments', { instruments: ['Timeline'] });
  await sess.send('Timeline.start', { maxCallStackDepth: 1 });
  return {
    async stop() {
      await sess.send('Timeline.stop');
      const has = (m) => recs.some((r) => r.type === 'TimeStamp' && r.data?.message === m);
      for (let i = 0; i < 60 && !has('wk:b'); i++) await sleep(50);
      await sleep(150);
      (sess.off ?? sess.removeListener).call(sess, 'Timeline.eventRecorded', on);
      return recs;
    },
  };
}

async function openPage(browser, env, a) {
  const context = await browser.newContext({
    viewport: { width: Math.ceil(env.width), height: env.height },
    screen: { width: Math.round(env.deviceWidth), height: Math.round(env.deviceHeight) },
    deviceScaleFactor: env.dpr,
    hasTouch: env.hover === 'none',
    colorScheme: 'light',
    reducedMotion: 'no-preference',
  });
  await context.route('**/*', (route) => (route.request().url().startsWith('http://127.0.0.1') ? route.continue() : route.abort()));
  const page = await context.newPage();
  await page.addInitScript(PIN_SRC);
  await page.goto(a.origin + (a.site === 'rewrite' ? `/${a.search}` : '/'), { waitUntil: 'load' });
  const frame = page.mainFrame();
  await frame.evaluate(waitReady, { site: a.site, capMs: 20000 });
  const arm = await frame.evaluate(() => (window.__fw ? { config: window.__fw.configHash ?? null, mode: window.__fw.mode ?? null } : { config: null, mode: null }));
  await frame.evaluate(RECORDER_SRC);
  return { context, page, frame, arm };
}

/** One window on one arm: the recorder result, the Timeline records (event reps) and the arm identity the page reported. */
async function oneWindow(browser, env, a, win, events) {
  const { context, page, frame, arm } = await openPage(browser, env, a);
  try {
    const cx = env.width / 2;
    const cy = env.height / 2;
    if (win === 'end') await frame.evaluate(TO_END_JS);
    else await sleep(400);
    await page.mouse.move(cx, cy);
    const tl = events ? await startTimeline(page) : null;
    await frame.evaluate(() => window.__pr.start());
    if (win === 'hero') {
      const t0 = Date.now();
      for (let i = 0; i < HERO_BURST.count; i++) {
        const wait = t0 + i * HERO_BURST.everyMs - Date.now();
        if (wait > 0) await sleep(wait);
        await page.mouse.wheel(0, HERO_BURST.dy);
      }
      await sleep(HERO_BURST.tailMs);
    } else {
      await page.mouse.wheel(0, END_PUSH.dy);
      await sleep(END_PUSH.holdMs);
      await page.mouse.wheel(0, -END_PUSH.dy);
      await sleep(END_PUSH.holdMs);
    }
    const rec = await frame.evaluate(() => window.__pr.stop());
    const records = tl ? await tl.stop() : null;
    return { rec, records, arm };
  } finally { await context.close().catch(() => {}); }
}

/**
 * Run the leg: `events` reps with the Timeline on and `cadenceReps` reps without it, all arms interleaved, both windows, on one
 * browser at the width `width`. `lookSearch` is the look-change arm's `?fw=...` search. Returns the result object the report reads.
 */
export async function runWebkitCadence({ width = 390, lookSearch, reps = 6, cadenceReps = 5, env = process.env }) {
  const plan = sessionPlan(lookSearch);
  const configs = JSON.parse(readFileSync(join(siteDist(env), 'configs.json'), 'utf8'));
  const baseHash = configs.bySearch[''];
  const hashOf = (search) => (search ? rewriteFor(siteDist(env), { ...env, FW_SEARCH: search }).hash : baseHash);
  const servers = [];
  const serve = async (root, rewrite = null) => { const s = await startServer(root, rewrite); servers.push(s); return s; };
  const origin = await serve(snapshotRoot(env));
  const faithful = await serve(siteDist(env));
  const second = await serve(siteDist(env));
  const searchOf = { base: '', look: lookSearch, v2: '?preset=v2-proved' };
  const arms = [
    { id: 'orig', site: 'orig', search: '', want: null, origin: origin.origin },
    { id: 'base', site: 'rewrite', search: '', want: baseHash, origin: faithful.origin },
    { id: 'aa', site: 'rewrite', search: '', want: baseHash, origin: second.origin },
  ];
  for (const [kept, id] of [['look', 'look'], ['v2', 'v2']]) {
    if (!plan.kept.includes(kept)) continue;
    const v = rewriteFor(siteDist(env), { ...env, FW_SEARCH: searchOf[id] });
    const srv = await serve(siteDist(env), v.rewrite);
    arms.push({ id, site: 'rewrite', search: searchOf[id], want: hashOf(searchOf[id]), origin: srv.origin });
  }
  const e = envFor(width);
  const browser = await webkit.launch();
  const rows = [];
  let refused = false;
  const started = Date.now();
  try {
    const total = reps + cadenceReps;
    outer: for (let k = 0; k < total; k++) {
      const events = k < reps;
      const rep = events ? k : k - reps;
      for (const a of orderFor(arms, k)) {
        for (const win of ['hero', 'end']) {
          const t0 = Date.now();
          const r = await oneWindow(browser, e, a, win, events);
          const base = { arm: a.id, window: win, rep, mode: events ? 'events' : 'cadence', config: r.arm.config, fwMode: r.arm.mode };
          const ivs = intervalsOf(r.rec.ts);
          const row = { ...base, frames: r.rec.ts.length, hitches: hitches(ivs), ivs };
          if (events) {
            const pw = profileWindow(pageOf(r.rec, toHundredths), r.records);
            Object.assign(row, { ok: pw.ok, reason: pw.reason ?? null, off: pw.off ?? null, offA: pw.offA ?? null, offB: pw.offB ?? null, profiles: pw.profiles, records: r.records.length });
          }
          rows.push(row);
          if (runCheck([{ site: a.site, want: a.want, config: r.arm.config, mode: r.arm.mode }]) !== 'ok') {
            refused = true;
            log(`webkit ${width} ${a.id} ${win}: REFUSED config (${JSON.stringify(r.arm)})`);
            break outer;
          }
          log(`webkit ${width} ${row.mode} rep ${rep} ${a.id} ${win}: ${row.frames} frames${events ? `, ${row.records} records, window ${row.ok ? 'kept' : `refused (${row.reason})`}` : ''} in ${Date.now() - t0} ms`);
        }
      }
    }
    return {
      leg: 'mac', engine: 'playwright-webkit', version: browser.version(), width, search: lookSearch, baseHash, reps, cadenceReps,
      plan: { kept: plan.kept, dropped: plan.dropped, flags: plan.flags }, arms: arms.map((a) => a.id),
      hero: HERO_BURST, end: END_PUSH, refused, wallSeconds: Math.round((Date.now() - started) / 1000), rows,
    };
  } finally {
    await browser.close().catch(() => {});
    for (const s of servers) await s.close().catch(() => {});
  }
}
