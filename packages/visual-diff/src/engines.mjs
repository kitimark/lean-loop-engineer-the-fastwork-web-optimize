// Browser launchers with screenshots. Both engines run through Playwright (the gate's own launchers have no screenshot
// call, and they are read only here). The probe environment is emulated as the gate does it (gate-breakpoints/src/engines.mjs):
// viewport, screen (device width), device pixel ratio, reduced motion, colour scheme; hover and pointer through
// --blink-settings in Chromium (one browser per pair), through `hasTouch` in WebKit. Every host except 127.0.0.1 is blocked.
//   session = { page, close() }
import { chromium, webkit } from 'playwright-core';

const hostWidth = (env) => Math.ceil(env.width);
const HOVER = { none: 1, hover: 2 };
const POINTER = { none: 1, coarse: 2, fine: 4 };

const contextOptions = (env) => ({
  viewport: { width: hostWidth(env), height: env.height },
  screen: { width: Math.round(env.deviceWidth), height: Math.round(env.deviceHeight) },
  deviceScaleFactor: env.dpr,
  colorScheme: env.colorScheme === 'dark' ? 'dark' : 'light',
  reducedMotion: env.reducedMotion === 'reduce' ? 'reduce' : 'no-preference',
});

const only127 = (route) => (route.request().url().startsWith('http://127.0.0.1') ? route.continue() : route.abort());

export async function launchChromium({ chromePath = process.env.CHROME_PATH } = {}) {
  const browsers = new Map();
  const browserFor = (env) => {
    const key = `${env.hover}/${env.pointer}`;
    if (!browsers.has(key)) {
      browsers.set(key, chromium.launch({
        ...(chromePath ? { executablePath: chromePath } : {}),
        headless: true,
        args: [
          `--blink-settings=primaryHoverType=${HOVER[env.hover]},availableHoverTypes=${HOVER[env.hover]},primaryPointerType=${POINTER[env.pointer]},availablePointerTypes=${POINTER[env.pointer]}`,
          '--font-render-hinting=none',
          '--force-color-profile=srgb',
        ],
      }));
    }
    return browsers.get(key);
  };
  return {
    name: 'chromium',
    async version() { return (await browserFor({ hover: 'hover', pointer: 'fine' })).version(); },
    async open(env, { origin, path = '/', init }) {
      const browser = await browserFor(env);
      const context = await browser.newContext(contextOptions(env));
      await context.route('**/*', only127);
      const page = await context.newPage();
      await page.addInitScript(init);
      await page.goto(origin + path, { waitUntil: 'load' });
      return { page, close: () => context.close() };
    },
    async close() { for (const p of browsers.values()) await (await p).close(); },
  };
}

export async function launchWebkit() {
  const browser = await webkit.launch();
  return {
    name: 'playwright-webkit',
    async version() { return `WebKit ${browser.version()} (playwright-core 1.64.1)`; },
    async open(env, { origin, path = '/', init }) {
      const context = await browser.newContext({ ...contextOptions(env), hasTouch: env.hover === 'none' });
      await context.route('**/*', only127);
      const page = await context.newPage();
      await page.addInitScript(init);
      await page.goto(origin + path, { waitUntil: 'load' });
      return { page, close: () => context.close() };
    },
    async close() { await browser.close(); },
  };
}

export const LAUNCHERS = { chromium: launchChromium, 'playwright-webkit': launchWebkit };
