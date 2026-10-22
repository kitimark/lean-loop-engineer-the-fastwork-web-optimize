import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { webkit } from 'playwright-core';
import { PIN_SRC, waitReady } from '../page.mjs';
import { startServer, snapshotRoot, siteDist, rewriteFor } from '../serve.mjs';
import { envFor } from '../trajectory/registry.mjs';
import { runCheck } from '../trajectory/reduce.mjs';
import { HERO_BURST, orderFor } from './schedule.mjs';
import { BOUND_JS, endPushFor } from './bound.mjs';
import { hitches } from './reduce.mjs';
import { RECORDER_SRC, TO_END_JS, pageOf, intervalsOf } from '../../../measure-webkit/src/profile/recorder.mjs';
import { profileWindow, toHundredths } from '../../../measure-webkit/src/profile/reduce.mjs';
import { sessionPlan } from '../../../measure-webkit/src/device-arms.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => process.stderr.write(`${a.join(' ')}\n`);

function sessionOf(page) {
  const sess = page._connection?.toImpl?.(page)?.delegate?._session;
  if (!sess || typeof sess.send !== 'function' || typeof sess.on !== 'function') throw new Error('the WebKit protocol session of the page is not reachable (playwright-core internals changed)');
  return sess;
}

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
  if (a.id === 'bound') {
    const dur = await frame.evaluate(BOUND_JS);
    if (dur === null || !/^0s(, 0s)*$/.test(dur)) throw new Error(`bound arm: the earn button is missing or still has transitions (transition-duration ${JSON.stringify(dur)})`);
  }
  await frame.evaluate(RECORDER_SRC);
  return { context, page, frame, arm };
}

async function oneWindow(browser, env, a, win, events, end) {
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
      await page.mouse.wheel(0, end.dy);
      await sleep(end.holdMs);
      await page.mouse.wheel(0, -end.dy);
      await sleep(end.holdMs);
    }
    const rec = await frame.evaluate(() => window.__pr.stop());
    const records = tl ? await tl.stop() : null;
    return { rec, records, arm };
  } finally { await context.close().catch(() => {}); }
}

export async function runWebkitCadence({ width = 390, lookSearch, reps = 6, cadenceReps = 5, only, holdMs, env = process.env }) {
  const end = endPushFor(holdMs);
  if (only?.includes('look') && !lookSearch) throw new Error('the look arm needs --search ?fw=...');
  const plan = only ? { kept: [], dropped: [], flags: {} } : sessionPlan(lookSearch);
  const configs = JSON.parse(readFileSync(join(siteDist(env), 'configs.json'), 'utf8'));
  const baseHash = configs.bySearch[''];
  const hashOf = (search) => (search ? rewriteFor(siteDist(env), { ...env, FW_SEARCH: search }).hash : baseHash);
  const servers = [];
  const serve = async (root, rewrite = null) => { const s = await startServer(root, rewrite); servers.push(s); return s; };
  const origin = await serve(snapshotRoot(env));
  const faithful = await serve(siteDist(env));
  const second = await serve(siteDist(env));
  const searchOf = { base: '', look: lookSearch, v2: '?preset=v2-proved' };
  let arms = [
    { id: 'orig', site: 'orig', search: '', want: null, origin: origin.origin },
    { id: 'base', site: 'rewrite', search: '', want: baseHash, origin: faithful.origin },
    { id: 'aa', site: 'rewrite', search: '', want: baseHash, origin: second.origin },
  ];
  if (only?.includes('bound')) arms.push({ id: 'bound', site: 'rewrite', search: '', want: baseHash, origin: (await serve(siteDist(env))).origin });
  for (const [kept, id] of [['look', 'look'], ['v2', 'v2']]) {
    if (only ? !only.includes(id) : !plan.kept.includes(kept)) continue;
    const v = rewriteFor(siteDist(env), { ...env, FW_SEARCH: searchOf[id] });
    const srv = await serve(siteDist(env), v.rewrite);
    arms.push({ id, site: 'rewrite', search: searchOf[id], want: hashOf(searchOf[id]), origin: srv.origin });
  }
  if (only) {
    const missing = only.filter((id) => !arms.some((a) => a.id === id));
    if (missing.length) throw new Error(`arms not available: ${missing.join(', ')}`);
    arms = arms.filter((a) => only.includes(a.id));
  }
  const e = envFor(width);
  const browser = await webkit.launch();
  const rows = [];
  const raws = [];
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
          const r = await oneWindow(browser, e, a, win, events, end);
          const base = { arm: a.id, window: win, rep, mode: events ? 'events' : 'cadence', config: r.arm.config, fwMode: r.arm.mode };
          const ivs = intervalsOf(r.rec.ts);
          const row = { ...base, frames: r.rec.ts.length, hitches: hitches(ivs), ivs };
          if (events) {
            const pw = profileWindow(pageOf(r.rec, toHundredths), r.records);
            raws.push({ arm: a.id, window: win, rep, raw: pw.raw });
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
      hero: HERO_BURST, end, refused, wallSeconds: Math.round((Date.now() - started) / 1000), rows, raws,
    };
  } finally {
    await browser.close().catch(() => {});
    for (const s of servers) await s.close().catch(() => {});
  }
}
