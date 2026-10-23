// Chromium launcher of the cadence lane (task smoothness-probe, part B). Glue only: the environment emulation is the one of
// src/engines.mjs (same flags, same CDP calls), plus the two things the cadence lane needs that the gate's launcher does not offer:
// a real wheel at a fixed schedule and Chromium's own frame trace (Playwright `browser.startTracing`). The browser runs with the
// compositor on its normal vsync (no BeginFrameControl, no frozen clock), so frames are produced the way a person's scroll makes them.
import { chromium } from 'playwright-core';

const CHROME_DEFAULT = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const HOVER = { none: 1, hover: 2 };
const POINTER = { none: 1, coarse: 2, fine: 4 };

/** The trace categories that carry frame production and presentation (devtools timeline frame events and the pipeline reporter). */
export const TRACE_CATEGORIES = ['benchmark', 'cc', 'viz', 'devtools.timeline', 'disabled-by-default-devtools.timeline.frame'];

/** Histogram names read through the browser's DevTools target: scroll jank, smoothness and checkerboarding (Chromium cc/metrics). */
export const HISTOGRAM_QUERIES = ['ScrollJank', 'Smoothness', 'Checkerboarding'];

const metrics = (env) => ({
  width: Math.ceil(env.width), height: env.height, deviceScaleFactor: env.dpr, mobile: false,
  screenWidth: Math.round(env.deviceWidth), screenHeight: Math.round(env.deviceHeight),
});

/** One browser for one environment: `open` returns a session with evaluate, wheel (real input), trace start and stop, and close. */
export async function launchCadence({ chromePath = process.env.CHROME_PATH ?? CHROME_DEFAULT, env }) {
  const browser = await chromium.launch({
    executablePath: chromePath,
    headless: true,
    args: [
      `--blink-settings=primaryHoverType=${HOVER[env.hover]},availableHoverTypes=${HOVER[env.hover]},primaryPointerType=${POINTER[env.pointer]},availablePointerTypes=${POINTER[env.pointer]}`,
      '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
      '--font-render-hinting=none',
      '--force-color-profile=srgb',
    ],
  });
  const browserCdp = await browser.newBrowserCDPSession().catch(() => null);
  /** The histograms that changed since the last call (CDP `Browser.getHistograms`, delta), or null when the target refuses them. */
  const histograms = async () => {
    if (!browserCdp) return null;
    try {
      const out = [];
      for (const query of HISTOGRAM_QUERIES) {
        const r = await browserCdp.send('Browser.getHistograms', { query, delta: true });
        for (const h of r.histograms ?? []) out.push({ name: h.name, count: h.count, sum: h.sum, buckets: (h.buckets ?? []).map((b) => [b.low, b.high, b.count]) });
      }
      return out;
    } catch { return null; }
  };
  return {
    version: () => browser.version(),
    async open({ origin, path, init }) {
      const context = await browser.newContext({ viewport: null });
      const page = await context.newPage();
      const cdp = await context.newCDPSession(page);
      await cdp.send('Emulation.setDeviceMetricsOverride', metrics(env));
      await cdp.send('Emulation.setEmulatedMedia', { features: [
        { name: 'prefers-reduced-motion', value: 'no-preference' },
        { name: 'prefers-color-scheme', value: 'light' },
      ] });
      await page.addInitScript(init);
      if (env.hover === 'hover') await page.mouse.move(-1, -1);
      await page.goto(origin + path, { waitUntil: 'load' });
      const frame = page.mainFrame();
      return {
        evaluate: (fn, arg) => frame.evaluate(fn, arg),
        async wheel(x, y, dy) { await page.mouse.move(x, y); await page.mouse.wheel(0, dy); },
        /** A wheel burst on a fixed schedule: `count` events of `dy` CSS px, one every `everyMs` (absolute deadlines, no drift). */
        async wheelBurst(x, y, dy, count, everyMs) {
          await page.mouse.move(x, y);
          const t0 = Date.now();
          for (let i = 0; i < count; i++) {
            const wait = t0 + i * everyMs - Date.now();
            if (wait > 0) await new Promise((r) => setTimeout(r, wait));
            await page.mouse.wheel(0, dy);
          }
        },
        /** CDP Emulation.setCPUThrottlingRate: 1 = none, n = the main thread runs n times slower (the cheap proxy of a slow phone CPU). */
        setCpuThrottle: (rate) => cdp.send('Emulation.setCPUThrottlingRate', { rate }),
        histograms,
        startTrace: () => browser.startTracing(page, { categories: TRACE_CATEGORIES, screenshots: false }),
        stopTrace: () => browser.stopTracing(),
        async close() { await context.close(); },
      };
    },
    async close() { await browser.close(); },
  };
}
