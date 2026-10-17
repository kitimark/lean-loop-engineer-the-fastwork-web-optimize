// Engine adapters. Both expose the same small surface:
//   engine.open(env, { origin, path, init }) -> session { evaluate(fn, arg), resize(env), close() }
// `env` = { width, height, deviceWidth, deviceHeight, dpr, hover, pointer, reducedMotion, colorScheme }.
//
// How each engine emulates the probe environment (CONFIRMED by running it, see the handoff):
//
// Chromium (Mac Google Chrome through puppeteer-core, headless, no touch events, not "mobile"):
//   width/height/DPR/device width: CDP Emulation.setDeviceMetricsOverride { width, height, deviceScaleFactor, mobile:false,
//     screenWidth, screenHeight }. screenWidth is what `device-width` and `screen.width` report. Both are integers.
//   hover/pointer: not settable per page by CDP. `--blink-settings=primaryHoverType,availableHoverTypes,primaryPointerType,
//     availablePointerTypes` sets them per browser process, so one browser is launched per (hover, pointer) pair.
//     Enum values: hover none=1 hover=2; pointer none=1 coarse=2 fine=4. All four combinations are reachable.
//   reduced motion and colour scheme: CDP Emulation.setEmulatedMedia { features }.
//   network: --host-resolver-rules makes every host except 127.0.0.1 unresolvable.
//
// Playwright WebKit (playwright-core 1.64.1, WebKit 27.2 on this Mac, not Safari, no toolbar):
//   width/height: context `viewport`; DPR: `deviceScaleFactor`; device width: context `screen` (fixed for the context's
//     life, so a live resize cannot change it).
//   hover/pointer: WebKit takes them from the platform (WebCore css/query/MediaQueryFeatures.cpp: hover from
//     Chrome::client().hoverSupportedByPrimaryPointingDevice(), pointer from pointerCharacteristicsOfPrimaryPointingDevice()),
//     and Playwright only offers `hasTouch`, which flips BOTH to (hover: none)+(pointer: coarse). So desktop (hover, fine)
//     and touch (none, coarse) are reachable; the cross pairs (none, fine) and (hover, coarse) are NOT. For those probes
//     the closest reachable pair is used (hasTouch = requested hover is none) and the probe is reported as env not achieved.
//   reduced motion, colour scheme: context `reducedMotion`, `colorScheme`.
//   network: context.route aborts everything but 127.0.0.1.
//
// Fractional widths (600.5 ...): NOT reachable in either engine. The emulation protocols take whole CSS px, and an
// <iframe> of CSS width 600.5 (and with DPR 1.25) still gets a 601 px viewport (MEASURED: bisecting `(min-width)` gives
// 601.0156 in Chromium and in WebKit; the extra 1/64 is the bisection's own resolution). Such a probe is loaded at the next
// whole px (ceil) and reported as env not achieved (width); the gap behaviour itself is covered only by the Lean proofs.
import puppeteer from 'puppeteer-core';
import { webkit } from 'playwright-core';

const CHROME_DEFAULT = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
/** Whole CSS px the engine is asked for: the width itself, or the next whole px for a fractional width. */
const hostWidth = (env) => Math.ceil(env.width);

export async function launchChromium({ chromePath = process.env.CHROME_PATH ?? CHROME_DEFAULT } = {}) {
  const browsers = new Map();
  const HOVER = { none: 1, hover: 2 };
  const POINTER = { none: 1, coarse: 2, fine: 4 };
  const browserFor = (env) => {
    const key = `${env.hover}/${env.pointer}`;
    if (!browsers.has(key)) {
      browsers.set(key, puppeteer.launch({
        executablePath: chromePath,
        headless: true,
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
  const metrics = (env, w) => ({
    width: w, height: env.height, deviceScaleFactor: env.dpr, mobile: false,
    screenWidth: Math.round(env.deviceWidth), screenHeight: Math.round(env.deviceHeight),
  });
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
      await cdp.send('Emulation.setDeviceMetricsOverride', metrics(env, hostWidth(env)));
      await cdp.send('Emulation.setEmulatedMedia', media(env));
      await page.evaluateOnNewDocument(init);
      await page.goto(origin + path, { waitUntil: 'load' });
      const frame = page.mainFrame();
      return {
        evaluate: (fn, arg) => frame.evaluate(fn, arg),
        async resize(next) { await cdp.send('Emulation.setDeviceMetricsOverride', metrics(next, hostWidth(next))); },
        async mouse(x, y) { await page.mouse.move(x, y); },
        async close() { await context.close(); },
      };
    },
    async close() { for (const p of browsers.values()) await (await p).close(); },
  };
}

export async function launchWebkit() {
  const browser = await webkit.launch();
  return {
    name: 'playwright-webkit',
    async version() { return `WebKit ${browser.version()} (playwright-core 1.64.1)`; },
    async open(env, { origin, path, init }) {
      const context = await browser.newContext({
        viewport: { width: hostWidth(env), height: env.height },
        screen: { width: Math.round(env.deviceWidth), height: Math.round(env.deviceHeight) },
        deviceScaleFactor: env.dpr,
        hasTouch: env.hover === 'none',
        colorScheme: env.colorScheme === 'dark' ? 'dark' : 'light',
        reducedMotion: env.reducedMotion === 'reduce' ? 'reduce' : 'no-preference',
      });
      await context.route('**/*', (route) => {
        const u = route.request().url();
        return u.startsWith('http://127.0.0.1') ? route.continue() : route.abort();
      });
      const page = await context.newPage();
      await page.addInitScript(init);
      await page.goto(origin + path, { waitUntil: 'load' });
      const frame = page.mainFrame();
      return {
        evaluate: (fn, arg) => frame.evaluate(fn, arg),
        async resize(next) { await page.setViewportSize({ width: next.width, height: next.height }); },
        async mouse(x, y) { await page.mouse.move(x, y); },
        // The CI WebKit (GLib port) gave a page about one frame per second (run 39075162003); a page that is not the front one of
        // its browser is throttled there. The settle wait counts real frames, so the page is brought to the front first.
        async front() { await page.bringToFront(); },
        async close() { await context.close(); },
      };
    },
    async close() { await browser.close(); },
  };
}

export const LAUNCHERS = { chromium: launchChromium, 'playwright-webkit': launchWebkit };
