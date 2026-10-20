// Chromium launcher of the gaps lane: the gate's launcher (../engines.mjs) plus browser zoom.
//
// Browser zoom is not a CDP command (devtools-protocol has only Emulation.setPageScaleFactor, which changes
// visualViewport only, and the DPR inside setDeviceMetricsOverride, which keeps the media width whole). It is a profile
// preference: Default/Preferences { partition: { default_zoom_level: { x: log(z)/log(1.2) } } } (MEASURED, research note
// 10-17-gate-gaps-fractional.md C3 to C8). The media width is then P / (DSF x z), so at z = 2, DSF 1 and a CDP override
// of 2N+1 CSS px the page sees N + 1/2, DPR 2 and innerHeight = override height / 2.
//
// env.zoom (default 1) selects the zoom and env.override the CDP metrics (cells.mjs realizeChromium: width*zoom x height*zoom,
// DSF 1 when zoom > 1). The page's DPR is DSF x zoom, which is why the zoom equals Lean's DPR for the fractional cells: the
// environment the page sees is exactly Lean's (DPR 2), nothing is rewritten. One browser per (hover, pointer, zoom), each
// with a fresh user-data-dir that only this lane removes.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import puppeteer from 'puppeteer-core';
import { zoomLevel } from './cells.mjs';

const CHROME_DEFAULT = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const HOVER = { none: 1, hover: 2 };
const POINTER = { none: 1, coarse: 2, fine: 4 };

export async function launchChromiumGaps({ chromePath = process.env.CHROME_PATH ?? CHROME_DEFAULT } = {}) {
  const browsers = new Map();
  const dirs = [];
  const browserFor = (env) => {
    const zoom = env.zoom ?? 1;
    const key = `${env.hover}/${env.pointer}/${zoom}`;
    if (!browsers.has(key)) {
      const userDataDir = mkdtempSync(join(tmpdir(), 'fw-gaps-chrome-'));
      dirs.push(userDataDir);
      if (zoom !== 1) {
        mkdirSync(join(userDataDir, 'Default'));
        writeFileSync(join(userDataDir, 'Default', 'Preferences'), JSON.stringify({ partition: { default_zoom_level: { x: zoomLevel(zoom) } } }));
      }
      browsers.set(key, puppeteer.launch({
        executablePath: chromePath,
        pipe: true,
        headless: true,
        userDataDir,
        args: [
          `--blink-settings=primaryHoverType=${HOVER[env.hover]},availableHoverTypes=${HOVER[env.hover]},primaryPointerType=${POINTER[env.pointer]},availablePointerTypes=${POINTER[env.pointer]}`,
          '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
          '--font-render-hinting=none',
          '--force-color-profile=srgb',
        ],
      }));
    }
    return browsers.get(key);
  };
  const metrics = (env) => {
    const z = env.zoom ?? 1;
    const o = env.override ?? { width: env.width, height: env.height, deviceScaleFactor: env.dpr };
    if (!Number.isInteger(o.width) || !Number.isInteger(o.height)) throw new Error(`override ${o.width}x${o.height} is not whole (zoom ${z})`);
    return { ...o, mobile: false, screenWidth: Math.round(env.deviceWidth * z), screenHeight: Math.round(env.deviceHeight * z) };
  };
  const media = (env) => ({ features: [
    { name: 'prefers-reduced-motion', value: env.reducedMotion === 'reduce' ? 'reduce' : 'no-preference' },
    { name: 'prefers-color-scheme', value: env.colorScheme === 'dark' ? 'dark' : 'light' },
  ] });
  return {
    name: 'chromium',
    async version() { const b = await browserFor({ hover: 'hover', pointer: 'fine' }); return b.version(); },
    async open(env, { origin, path, init }) {
      const browser = await browserFor(env);
      const context = await browser.createBrowserContext();
      const page = await context.newPage();
      const cdp = await page.createCDPSession();
      await cdp.send('Emulation.setDeviceMetricsOverride', metrics(env));
      await cdp.send('Emulation.setEmulatedMedia', media(env));
      if (init) await page.evaluateOnNewDocument(init);
      await page.goto(origin + path, { waitUntil: 'load' });
      const frame = page.mainFrame();
      return {
        evaluate: (fn, arg) => frame.evaluate(fn, arg),
        async resize(next) { await cdp.send('Emulation.setDeviceMetricsOverride', metrics(next)); },
        async close() { await context.close(); },
      };
    },
    async close() {
      for (const p of browsers.values()) await (await p).close();
      for (const d of dirs) rmSync(d, { recursive: true, force: true });
    },
  };
}
