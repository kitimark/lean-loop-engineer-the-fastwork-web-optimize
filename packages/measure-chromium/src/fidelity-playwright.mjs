// Font fidelity, Playwright side (task counts-font-fidelity): the reference layout on a macOS runner, where WebKit takes
// the system fonts of the OS (the engine and fonts of the phone's family). Runs the same fidelityInPage as the Chromium
// container driver over the same views and writes fidelity-<variant>.json. Nothing here is phone time.
// usage: node fidelity-playwright.mjs --root=<snapshot/site> --rows=<rows.json> --out=<dir> [--variant=webkit-mac] [--views=m430,d1280]
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { devices, webkit } from 'playwright-core';
import { startServer } from './server.mjs';
import { PIN_DATE_SRC, fidelityInPage } from './fidelity-page.mjs';
import { VIEWS } from './fidelity-views.mjs';

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const s = a.replace(/^--/, ''); const i = s.indexOf('='); return i < 0 ? [s, true] : [s.slice(0, i), s.slice(i + 1)]; }));
const VARIANT = args.variant ?? 'webkit-mac';
const OUT = args.out;
const ROOT = args.root;
if (!OUT || !ROOT || !args.rows) { console.error('usage: fidelity-playwright.mjs --root=<site> --rows=<rows.json> --out=<dir> [--variant=name] [--views=m430,d1280]'); process.exit(2); }
const ROWS = JSON.parse(readFileSync(args.rows, 'utf8'));
const READY = '.hero-track .hero.is-ring-splash-done';
const only = typeof args.views === 'string' ? args.views.split(',') : null;
mkdirSync(OUT, { recursive: true });
const srv = await startServer(ROOT);
const browser = await webkit.launch({ headless: true });
const result = { schema: 'fw.font-fidelity/1', variant: VARIANT, browser: `webkit ${browser.version()}`, platform: process.platform, views: {} };
const phoneUa = devices['iPhone 15 Pro Max'].userAgent;
try {
  for (const view of VIEWS) {
    if (only && !only.includes(view.id)) continue;
    const r = { view: view.id, width: view.width, height: view.height, dpr: view.dpr, mobile: view.mobile, crash: false, error: null };
    const ctx = await browser.newContext({
      viewport: { width: view.width, height: view.height }, deviceScaleFactor: view.dpr, isMobile: view.mobile, hasTouch: view.mobile,
      locale: 'en-US', timezoneId: 'Asia/Bangkok', ...(view.mobile ? { userAgent: phoneUa } : {}),
    });
    const page = await ctx.newPage();
    page.on('crash', () => { r.crash = true; });
    try {
      await page.addInitScript(PIN_DATE_SRC);
      await page.goto(`http://127.0.0.1:${srv.port}/`, { waitUntil: 'load', timeout: 60000 });
      Object.assign(r, await page.evaluate(fidelityInPage, { rows: ROWS, readySel: READY }));
    } catch (e) {
      r.error = String(e?.message ?? e).slice(0, 400);
    }
    result.views[view.id] = r;
    console.error(`FIDELITY ${VARIANT} ${view.id} docH=${r.docH ?? '-'} innerH=${r.innerH ?? '-'} crash=${r.crash} error=${r.error ?? '-'}`);
    await ctx.close().catch(() => {});
  }
  result.served = Object.keys(srv.served()).length;
  result.missing = srv.missing();
} finally {
  writeFileSync(`${OUT}/fidelity-${VARIANT}.json`, `${JSON.stringify(result)}\n`);
  await browser.close().catch(() => {});
  process.exit(0);
}
