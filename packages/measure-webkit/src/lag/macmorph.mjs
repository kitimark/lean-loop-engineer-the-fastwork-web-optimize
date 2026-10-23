import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { serveTree } from '../serve.mjs';
import { bootstrapSource } from '../page.mjs';
import { flattenRecords, markTimes, markTime, reduceSteps, COUNT_TYPES } from '../reduce.mjs';
import { classify, acceptScrollIn, morphMilli } from './phase.mjs';
import { DRIVES, ARMS, acceptMomentum, splitPush } from './macreport.mjs';

export const MAC_SCHEDULE = Object.freeze({ idle: 10, open: 60, close: 60, dy: 120 });
export const SCROLL_IN = Object.freeze({ lead: 300, first: 3, gap: 2, settle: 2, maxWheels: 12, near: 8, stableTries: 20 });
export const MOMENTUM = Object.freeze({ lead: 300, first: 5, gap: 2, before: 1, maxWheels: 12, near: 8 });
export { DRIVES, ARMS };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export const MAC_PAGE_JS = `(() => {
  const nav = document.querySelector('header.start-selling-top-nav, [data-fw="nav"]');
  const S = window.__wkm = { k: 0, on: false, events: [], pending: [], seen: { down: false, up: false }, armed: null, skip: 0, at: [], waiters: [] };
  const morph = () => (nav ? Number(nav.style.getPropertyValue('--morph')) : null);
  addEventListener('wheel', (e) => {
    const d = e.deltaY > 0 ? 'down' : e.deltaY < 0 ? 'up' : null;
    let m = false;
    if (d && !S.seen[d] && (S.armed === null || S.armed === d)) {
      if (S.skip > 0) S.skip--; else { S.seen[d] = true; performance.mark('wk:' + d); m = true; }
    }
    S.pending.push({ f: S.k, dy: e.deltaY, trusted: e.isTrusted, cancelable: e.cancelable, y: Math.round(scrollY), m, ev: e });
  }, { capture: true, passive: true });
  const tick = () => {
    if (!S.on) return;
    performance.mark('wk:s' + S.k); S.k++;
    for (const p of S.pending.splice(0)) { const { ev, ...rest } = p; S.events.push({ ...rest, prevented: ev.defaultPrevented }); }
    for (const w of S.waiters.splice(0)) { if (S.k >= w.k) { S.at.push({ label: w.label, f: S.k, morph: morph(), y: Math.round(scrollY) }); w.ok(); } else S.waiters.push(w); }
    requestAnimationFrame(tick);
  };
  S.start = () => { S.on = true; S.at.push({ label: 'start', f: 0, morph: morph(), y: Math.round(scrollY) }); requestAnimationFrame(tick); };
  S.arm = (d, skip = 0) => { S.armed = d; S.skip = skip; };
  S.until = (k, label) => new Promise((ok) => S.waiters.push({ k, label, ok }));
  S.push = (d) => document.body.dispatchEvent(new WheelEvent('wheel', { deltaY: d, cancelable: true, bubbles: true }));
  S.finish = async () => {
    await new Promise((r) => requestAnimationFrame(() => r()));
    performance.mark('wk:end'); S.on = false;
    for (const p of S.pending.splice(0)) { const { ev, ...rest } = p; S.events.push({ ...rest, prevented: ev.defaultPrevented }); }
    return { frames: S.k, events: S.events, at: S.at, y: Math.round(scrollY) };
  };
  return true;
})()`;

export function sessionOf(page) {
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
      for (let i = 0; i < 60 && !has('wk:end'); i++) await sleep(50);
      await sleep(150);
      (sess.off ?? sess.removeListener).call(sess, 'Timeline.eventRecorded', on);
      return recs;
    },
  };
}

export function runRecord(records, frames) {
  const rows = flattenRecords(records);
  const marks = markTimes(rows, 'wk:s', frames);
  const endTime = markTime(rows, 'wk:end');
  const down = markTime(rows, 'wk:down'), up = markTime(rows, 'wk:up');
  if (endTime === null || marks.some((t) => t === null)) return { outcome: 'marksMissing', marks, down, up };
  const c = classify(marks, down, up);
  const red = reduceSteps(rows, marks, endTime);
  return { outcome: c.outcome, idle: c.idle ?? null, open: c.open ?? null, close: c.close ?? null, marks, endTime, down, up, countTypes: COUNT_TYPES, perStep: red.perStep, paintArea: red.perStepPaintArea };
}

async function oneRun(browser, a, drive, { width = 390, height = 844, settleMs = 4000, schedule = MAC_SCHEDULE }) {
  const context = await browser.newContext({
    viewport: { width, height }, deviceScaleFactor: 2, hasTouch: true, colorScheme: 'light', reducedMotion: 'no-preference',
  });
  await context.route('**/*', (route) => (route.request().url().startsWith('http://127.0.0.1') ? route.continue() : route.abort()));
  try {
    const page = await context.newPage();
    await page.addInitScript(bootstrapSource());
    await page.goto(a.url, { waitUntil: 'load' });
    if (a.arm === 'rewrite') await page.waitForFunction(() => !!(window.__fw && window.__fw.hydrated), null, { timeout: 30000 });
    await sleep(settleMs);
    const info = await page.evaluate(() => ({ maxY: Math.max(0, document.documentElement.scrollHeight - innerHeight), config: window.__fw?.configHash ?? null, mode: window.__fw?.mode ?? null }));
    const startY = Math.max(0, info.maxY - (drive === 'scrollin' ? SCROLL_IN.lead : drive === 'momentum' ? MOMENTUM.lead : 0));
    await page.evaluate(async (top) => {
      const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
      scrollTo({ top, behavior: 'instant' }); await raf(); await raf(); await raf();
    }, startY);
    await sleep(500);
    await page.evaluate(MAC_PAGE_JS);
    await page.mouse.move(width / 2, height / 2);
    const tl = await startTimeline(page);
    await page.evaluate(() => window.__wkm.start());
    const readY = () => page.evaluate(() => Math.round(scrollY));
    const wait = (n, label) => page.evaluate(([m, l]) => window.__wkm.until(window.__wkm.k + m, l), [n, label]);
    const push = (d) => (drive === 'synthetic' ? page.evaluate((x) => window.__wkm.push(x), d) : page.mouse.wheel(0, d));
    let wheels = 0;
    if (drive === 'scrollin') {
      await page.evaluate(() => window.__wkm.arm('none'));
      await wait(SCROLL_IN.first, 'lead');
      for (; wheels < SCROLL_IN.maxWheels && info.maxY - (await readY()) > SCROLL_IN.near; wheels++) {
        await page.mouse.wheel(0, schedule.dy);
        await wait(SCROLL_IN.gap, 'scroll');
      }
      for (let i = 0, last = -1, now = await readY(); i < SCROLL_IN.stableTries && now !== last; i++) { last = now; await wait(SCROLL_IN.gap, 'stable'); now = await readY(); }
    }
    let pushY;
    if (drive === 'momentum') {
      const need = Math.max(2, Math.ceil((info.maxY - (await readY())) / schedule.dy));
      await page.evaluate(() => window.__wkm.arm('none'));
      await wait(MOMENTUM.first, 'lead');
      for (; wheels < Math.min(need - 1, MOMENTUM.maxWheels); wheels++) {
        await page.mouse.wheel(0, schedule.dy);
        await wait(MOMENTUM.gap, 'scroll');
      }
      pushY = await readY();
      await page.evaluate(() => window.__wkm.arm('down', 1));
      await page.mouse.wheel(0, schedule.dy);
      wheels++;
      await wait(MOMENTUM.before, 'momentum');
      await page.mouse.wheel(0, schedule.dy);
    } else {
      await page.evaluate(([n, extra]) => window.__wkm.until(Math.max(n, window.__wkm.k + extra), 'idle'), [schedule.idle, drive === 'scrollin' ? SCROLL_IN.settle : 0]);
      pushY = await readY();
      await page.evaluate(() => window.__wkm.arm('down'));
      await push(schedule.dy);
    }
    await wait(schedule.open, 'open');
    await page.evaluate(() => window.__wkm.arm('up'));
    await push(-schedule.dy);
    await wait(schedule.close, 'close');
    const fin = await page.evaluate(() => window.__wkm.finish());
    const records = await tl.stop();
    const y = await readY();
    const rec = runRecord(records, fin.frames);
    const sp = splitPush(fin.events);
    const out = drive === 'scrollin' ? { ...rec, outcome: acceptScrollIn(rec, startY, pushY, morphMilli(fin.at)).outcome }
      : drive === 'momentum' ? { ...rec, outcome: acceptMomentum(rec, startY, pushY, morphMilli(fin.at), sp.scrolls, sp.push).outcome } : rec;
    return { info, fin, y, startY, pushY, wheels, ...out, records: records.length };
  } finally { await context.close().catch(() => {}); }
}

export async function serveArms({ snapshotDir, siteDir, search = '' }) {
  const orig = await serveTree(resolve(snapshotDir));
  const root = resolve(siteDir);
  const cfg = JSON.parse(readFileSync(join(root, 'configs.json'), 'utf8'));
  const hash = cfg.bySearch[search];
  if (!hash) throw new Error(`search "${search}" is not prerendered; known: ${Object.keys(cfg.bySearch).join(' | ')}`);
  const file = cfg.byHash[hash];
  const rewrite = await serveTree(root, { rewrite: (p) => (p === '/' || p === '/index.html' ? '/' + file : null) });
  return {
    arms: [{ arm: 'orig', url: orig.url + '/' }, { arm: 'rewrite', url: rewrite.url + '/' + search }],
    hash,
    async close() { await orig.close().catch(() => {}); await rewrite.close().catch(() => {}); },
  };
}

/**
 * `reps` repeats; per repeat every arm x drive once, the order rotated per repeat. The result keeps one record per run, refused runs included.
 * @param {{webkit:object, snapshotDir:string, siteDir:string, search?:string, reps?:number, log?:Function, schedule?:object}} o
 */
export async function runMacMorph({ webkit, snapshotDir, siteDir, search = '', reps = 4, log = () => {}, schedule = MAC_SCHEDULE }) {
  const served = await serveArms({ snapshotDir, siteDir, search });
  const browser = await webkit.launch();
  const cells = served.arms.flatMap((a) => DRIVES.map((drive) => ({ ...a, drive })));
  const runs = [];
  const started = Date.now();
  try {
    for (let rep = 0; rep < reps; rep++) {
      const order = cells.map((_, i) => cells[(i + rep) % cells.length]);
      for (const cell of order) {
        const t0 = Date.now();
        let r;
        try { r = await oneRun(browser, cell, cell.drive, { schedule }); } catch (e) { r = { outcome: 'error', error: String(e?.message ?? e).slice(0, 300) }; }
        runs.push({ rep, arm: cell.arm, drive: cell.drive, ...r });
        log(`mac morph rep ${rep} ${cell.arm} ${cell.drive}: ${r.outcome}${r.outcome === 'ok' ? ` ${r.idle}/${r.open}/${r.close} frames` : ''} in ${Date.now() - t0} ms`);
      }
    }
    return { schema: 'fw.webkit.lag.macmorph/1', engine: 'playwright-webkit', version: browser.version(), schedule, search, configHash: served.hash, reps, wallSeconds: Math.round((Date.now() - started) / 1000), runs };
  } finally {
    await browser.close().catch(() => {});
    await served.close();
  }
}
