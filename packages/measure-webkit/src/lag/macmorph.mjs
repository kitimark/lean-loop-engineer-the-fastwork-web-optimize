// The end-of-page morph on Playwright WebKit (macOS), driven by a trusted wheel (`page.mouse.wheel`, a native wheel through the UI process:
// playwright-core Mouse.wheel -> Input.dispatchWheelEvent) and by a synthetic WheelEvent on document.body, both at the same frame schedule on the
// same page. Phases come from `wk:down` / `wk:up` marks under the Lean rule (phase.mjs). Glue only: playwright-core is passed in by the caller.
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { serveTree } from '../serve.mjs';
import { bootstrapSource } from '../page.mjs';
import { flattenRecords, markTimes, markTime, reduceSteps, COUNT_TYPES } from '../reduce.mjs';
import { classify } from './phase.mjs';

export const MAC_SCHEDULE = Object.freeze({ idle: 10, open: 60, close: 60, dy: 120 });
export const DRIVES = Object.freeze(['trusted', 'synthetic']);
export const ARMS = Object.freeze(['orig', 'rewrite']);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Installed in the page once the end of the page is reached: a rAF loop marking `wk:s<k>` per frame, a capture wheel listener that marks the first push
 * in each direction (`wk:down`, `wk:up`) and keeps what the event was, and `until(k, label)` / `finish()` for the Node side. `--morph` is read from the
 * inline style of the nav (no style recalc) at the boundaries only.
 */
export const MAC_PAGE_JS = `(() => {
  const nav = document.querySelector('header.start-selling-top-nav, [data-fw="nav"]');
  const S = window.__wkm = { k: 0, on: false, events: [], pending: [], seen: { down: false, up: false }, at: [], waiters: [] };
  const morph = () => (nav ? Number(nav.style.getPropertyValue('--morph')) : null);
  addEventListener('wheel', (e) => {
    const d = e.deltaY > 0 ? 'down' : e.deltaY < 0 ? 'up' : null;
    if (d && !S.seen[d]) { S.seen[d] = true; performance.mark('wk:' + d); }
    S.pending.push({ f: S.k, dy: e.deltaY, trusted: e.isTrusted, cancelable: e.cancelable, y: Math.round(scrollY), ev: e });
  }, { capture: true, passive: true });
  const tick = () => {
    if (!S.on) return;
    performance.mark('wk:s' + S.k); S.k++;
    for (const p of S.pending.splice(0)) { const { ev, ...rest } = p; S.events.push({ ...rest, prevented: ev.defaultPrevented }); }
    for (const w of S.waiters.splice(0)) { if (S.k >= w.k) { S.at.push({ label: w.label, f: S.k, morph: morph(), y: Math.round(scrollY) }); w.ok(); } else S.waiters.push(w); }
    requestAnimationFrame(tick);
  };
  S.start = () => { S.on = true; S.at.push({ label: 'start', f: 0, morph: morph(), y: Math.round(scrollY) }); requestAnimationFrame(tick); };
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

/** The protocol session of a Playwright WebKit page (the same internals gate-breakpoints/src/smooth/webkit-cadence.mjs uses). */
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

/** Counts per step of one captured run: the marks, pushes and per-step record tallies (rows are not kept). */
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

/** One run: a fresh context at the 390 wide phone size, the page at its end, the schedule, the Timeline. */
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
    await page.evaluate(async (maxY) => {
      const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
      scrollTo({ top: maxY, behavior: 'instant' }); await raf(); await raf(); await raf();
    }, info.maxY);
    await sleep(500);
    await page.evaluate(MAC_PAGE_JS);
    await page.mouse.move(width / 2, height / 2);
    const tl = await startTimeline(page);
    await page.evaluate(() => window.__wkm.start());
    const push = (d) => (drive === 'trusted' ? page.mouse.wheel(0, d) : page.evaluate((x) => window.__wkm.push(x), d));
    await page.evaluate((n) => window.__wkm.until(n, 'idle'), schedule.idle);
    await push(schedule.dy);
    await page.evaluate((n) => window.__wkm.until(window.__wkm.k + n, 'open'), schedule.open);
    await push(-schedule.dy);
    await page.evaluate((n) => window.__wkm.until(window.__wkm.k + n, 'close'), schedule.close);
    const fin = await page.evaluate(() => window.__wkm.finish());
    const records = await tl.stop();
    const y = await page.evaluate(() => Math.round(scrollY));
    return { info, fin, y, ...runRecord(records, fin.frames), records: records.length };
  } finally { await context.close().catch(() => {}); }
}

/** The served arms: `orig` the read-only snapshot, `rewrite` the prerendered build at `search`. */
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
