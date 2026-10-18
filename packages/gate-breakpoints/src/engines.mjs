// Engine adapters. Both expose the same small surface:
//   engine.open(env, { origin, path, init, frozen }) -> session { evaluate(fn, arg), resize(env), mouse(x, y), close(),
//     and when `frozen`: advance(ms), holdTo(abs), clockMs() }
// `env` = { width, height, deviceWidth, deviceHeight, dpr, hover, pointer, reducedMotion, colorScheme }.
//
// The frozen clock (`frozen: true`, gate-shard-balance round 2; Lean Fw.Gate.Freeze, src/freeze.mjs): Playwright's page clock
// (page.clock, playwright-core 1.64.1) is installed at the pinned instant and paused BEFORE the page loads, in both engines, so
// Date, timers, requestAnimationFrame and performance.now only move when the harness moves them (advance / holdTo, or the page's
// own `window.__fwClock` binding, which page.mjs KIT_SRC wraps). It does not fake CSS animations (the document timeline stays
// real: page.mjs freezeAnimations pins those) or MessageChannel (React's scheduler, so hydration proceeds in real time). After
// every advance one real rendering frame is confirmed (a Web Animation's `ready` on the document element), so observers
// (ResizeObserver, IntersectionObserver) have run; a frame not confirmed in 250 real ms answers false and is not counted.
//
// How each engine emulates the probe environment (CONFIRMED by running it, see the handoff):
//
// Chromium (Google Chrome or Chrome Headless Shell through playwright-core since round 2 [before: puppeteer-core], headless, no
// touch events, not "mobile"; the viewport is still set through CDP, `viewport: null` leaves Playwright out of it):
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
import { chromium, webkit } from 'playwright-core';

const CHROME_DEFAULT = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
/** Whole CSS px the engine is asked for: the width itself, or the next whole px for a fractional width. */
const hostWidth = (env) => Math.ceil(env.width);
/** The instant the page clock is frozen at: page.mjs PIN_SRC pins Date to the same one. */
const CLOCK_T0 = Date.parse('2026-10-01T00:00:00+07:00');
/** Real ms a frame confirmation may take before it answers false. */
const CONFIRM_MS = 250;

/**
 * Install the frozen page clock on `page` (before it navigates) and expose `window.__fwClock(op, n)`. Returns the node-side API:
 * advance(ms) moves the fake clock by ms and confirms one real frame; holdTo(abs) moves it to the absolute fake time abs (ms
 * since the freeze; no move when it is already past); clockMs() is the fake time now.
 */
async function freezeClock(page) {
  let elapsed = 0;
  const confirm = () => Promise.race([
    page.evaluate(() => {
      const a = document.documentElement.animate([{ opacity: 1 }, { opacity: 1 }], { duration: 1 });
      return a.ready.then(() => { a.cancel(); return true; }, () => false);
    }).catch(() => false),
    new Promise((r) => setTimeout(() => r(false), CONFIRM_MS)),
  ]);
  const advance = async (ms) => {
    if (ms > 0) { await page.clock.runFor(ms); elapsed += ms; }
    return confirm();
  };
  const holdTo = (abs) => advance(Math.max(0, abs - elapsed));
  await page.clock.install({ time: CLOCK_T0 - 60000 });
  await page.clock.pauseAt(CLOCK_T0);
  await page.exposeBinding('__fwClock', async (_src, op, n) => {
    if (op === 'step') return advance(n);
    if (op === 'holdTo') return holdTo(n);
    if (op === 'real') { if (n > 0) await new Promise((r) => setTimeout(r, n)); return Date.now(); }
    throw new Error(`__fwClock: unknown op ${op}`);
  });
  return { advance, holdTo, clockMs: () => elapsed };
}

export async function launchChromium({ chromePath = process.env.CHROME_PATH ?? CHROME_DEFAULT } = {}) {
  const browsers = new Map();
  const HOVER = { none: 1, hover: 2 };
  const POINTER = { none: 1, coarse: 2, fine: 4 };
  const browserFor = (env) => {
    const key = `${env.hover}/${env.pointer}`;
    if (!browsers.has(key)) {
      browsers.set(key, chromium.launch({
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
    async open(env, { origin, path, init, frozen = false }) {
      const browser = await browserFor(env);
      const context = await browser.newContext({ viewport: null });
      const page = await context.newPage();
      const cdp = await context.newCDPSession(page);
      await cdp.send('Emulation.setDeviceMetricsOverride', metrics(env, hostWidth(env)));
      await cdp.send('Emulation.setEmulatedMedia', media(env));
      const clock = frozen ? await freezeClock(page) : null;
      await page.addInitScript(init);
      // The pointer starts at (0,0) of a fresh page, over the top-left card of hero.orbit; parking it before the navigation
      // leaves no pointer over the page while it loads (runs 39101532038 and 39105279831).
      if (env.hover === 'hover') await page.mouse.move(-1, -1);
      await page.goto(origin + path, { waitUntil: 'load' });
      const frame = page.mainFrame();
      return {
        evaluate: (fn, arg) => frame.evaluate(fn, arg),
        async resize(next) { await cdp.send('Emulation.setDeviceMetricsOverride', metrics(next, hostWidth(next))); },
        async mouse(x, y) { await page.mouse.move(x, y); },
        ...(clock ? { advance: clock.advance, holdTo: clock.holdTo, clockMs: clock.clockMs } : {}),
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
    async open(env, { origin, path, init, frozen = false }) {
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
      const clock = frozen ? await freezeClock(page) : null;
      await page.addInitScript(init);
      await page.goto(origin + path, { waitUntil: 'load' });
      const frame = page.mainFrame();
      return {
        evaluate: (fn, arg) => frame.evaluate(fn, arg),
        async resize(next) { await page.setViewportSize({ width: next.width, height: next.height }); },
        async mouse(x, y) { await page.mouse.move(x, y); },
        ...(clock ? { advance: clock.advance, holdTo: clock.holdTo, clockMs: clock.clockMs } : {}),
        async close() { await context.close(); },
      };
    },
    async close() { await browser.close(); },
  };
}

export const LAUNCHERS = { chromium: launchChromium, 'playwright-webkit': launchWebkit };
