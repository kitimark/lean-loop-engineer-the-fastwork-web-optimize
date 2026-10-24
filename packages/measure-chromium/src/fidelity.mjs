import { spawn } from 'node:child_process';
import { mkdirSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import puppeteer from 'puppeteer-core';
import { startServer } from './server.mjs';
import { PIN_DATE_SRC, fidelityInPage } from './fidelity-page.mjs';
import { userAgent } from './profile.mjs';
import { VIEWS } from './fidelity-views.mjs';

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const s = a.replace(/^--/, ''); const i = s.indexOf('='); return i < 0 ? [s, true] : [s.slice(0, i), s.slice(i + 1)]; }));
const VARIANT = args.variant ?? 'lane';
const OUT = args.out ?? '/out';
const ROOT = args.root ?? '/snapshot/site';
const ROWS = JSON.parse(readFileSync(args.rows ?? '/exprs/rows.json', 'utf8'));
const READY = '.hero-track .hero.is-ring-splash-done';
const only = typeof args.views === 'string' ? args.views.split(',') : null;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
mkdirSync(OUT, { recursive: true });

const srv = await startServer(ROOT);
const CHROME_ARGS = [
  '--remote-debugging-port=9222', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--user-data-dir=/tmp/fw-fid-profile',
  '--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE localhost, EXCLUDE 127.0.0.1',
  '--font-render-hinting=none', '--force-color-profile=srgb', '--hide-scrollbars', '--mute-audio',
  '--disable-background-networking', '--disable-breakpad', '--no-first-run', '--lang=en-US', 'about:blank',
];
const chrome = spawn(process.env.FW_CHROME, CHROME_ARGS, { stdio: ['ignore', openSync('/tmp/chrome.log', 'w'), openSync('/tmp/chrome.log', 'a')] });
const result = { schema: 'fw.font-fidelity/1', variant: VARIANT, fontconfig: process.env.FONTCONFIG_FILE ?? null, views: {} };

async function measureView(browser, view) {
  const r = { view: view.id, width: view.width, height: view.height, dpr: view.dpr, mobile: view.mobile, crash: false, error: null };
  const page = await browser.newPage();
  const c = await page.createCDPSession();
  c.on('Inspector.targetCrashed', () => { r.crash = true; });
  try {
    await c.send('Page.enable'); await c.send('Runtime.enable'); await c.send('DOM.enable'); await c.send('CSS.enable');
    await c.send('Emulation.setDeviceMetricsOverride', { width: view.width, height: view.height, deviceScaleFactor: view.dpr, mobile: view.mobile, screenWidth: view.width, screenHeight: view.height });
    await c.send('Emulation.setTouchEmulationEnabled', { enabled: view.mobile, maxTouchPoints: 5 });
    await c.send('Emulation.setTimezoneOverride', { timezoneId: 'Asia/Bangkok' });
    await c.send('Emulation.setLocaleOverride', { locale: 'en-US' });
    await c.send('Emulation.setUserAgentOverride', { userAgent: userAgent(view.mobile), acceptLanguage: 'en-US' });
    await c.send('Page.addScriptToEvaluateOnNewDocument', { source: PIN_DATE_SRC });
    const loaded = new Promise((res) => { c.once('Page.loadEventFired', () => res(true)); setTimeout(() => res(false), 60000); });
    await c.send('Page.navigate', { url: `http://127.0.0.1:${srv.port}/` });
    r.loaded = await loaded;
    const expr = `(${fidelityInPage.toString()})(${JSON.stringify({ rows: ROWS, readySel: READY })})`;
    const ev = await Promise.race([c.send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }), sleep(120000).then(() => ({ timeout: true }))]);
    if (ev.timeout) throw new Error('fidelityInPage timed out');
    if (ev.exceptionDetails) throw new Error(`evaluate failed: ${JSON.stringify(ev.exceptionDetails).slice(0, 400)}`);
    Object.assign(r, ev.result.value);
    const { root } = await c.send('DOM.getDocument', { depth: 0 });
    const { nodeIds } = await c.send('DOM.querySelectorAll', { nodeId: root.nodeId, selector: '[data-fw-fid]' });
    const fonts = new Map();
    for (const nodeId of nodeIds) {
      let pf;
      try { pf = (await c.send('CSS.getPlatformFontsForNode', { nodeId })).fonts; } catch { continue; }
      for (const f of pf) {
        const k = `${f.familyName}|${f.postScriptName}|${f.isCustomFont ? 'web' : 'system'}`;
        fonts.set(k, (fonts.get(k) ?? 0) + f.glyphCount);
      }
    }
    r.platformFonts = Array.from(fonts.entries()).map(([k, glyphs]) => { const [family, ps, kind] = k.split('|'); return { family, ps, kind, glyphs }; }).sort((a, b) => b.glyphs - a.glyphs);
  } catch (e) {
    r.error = String(e?.message ?? e).slice(0, 400);
  }
  await page.close().catch(() => {});
  return r;
}

async function main() {
  for (let i = 0; i < 200; i++) { try { await fetch('http://127.0.0.1:9222/json/version'); break; } catch { await sleep(50); } }
  const version = await (await fetch('http://127.0.0.1:9222/json/version')).json();
  result.browser = version.Browser;
  for (const view of VIEWS) {
    if (only && !only.includes(view.id)) continue;
    const browser = await puppeteer.connect({ browserURL: 'http://127.0.0.1:9222', defaultViewport: null, protocolTimeout: 150000 });
    result.views[view.id] = await measureView(browser, view);
    console.error(`FIDELITY ${VARIANT} ${view.id} docH=${result.views[view.id].docH ?? '-'} crash=${result.views[view.id].crash} error=${result.views[view.id].error ?? '-'}`);
    await browser.disconnect();
  }
  result.served = Object.keys(srv.served()).length;
  result.missing = srv.missing();
}

try { await main(); } finally {
  writeFileSync(`${OUT}/fidelity-${VARIANT}.json`, `${JSON.stringify(result)}\n`);
  chrome.kill('SIGKILL');
  process.exit(0);
}
