// Page-level controls shared by census, scroll and seek: the bootstrap script (clock pin, seeded Math.random),
// a reload that keeps the inspector connection, and the rAF helpers.
import { sleep } from './sim.mjs';

/** Pinned date from the plan (§4.2): before the countdown target 2026-11-02. */
export const PINNED_ISO = '2026-10-01T00:00:00+07:00';

/**
 * Script run before any page script (Page.setBootstrapScript, CONFIRMED working on the iOS 27.0 Simulator when sent on
 * the same connection that then calls Page.reload; sent on a connection that is closed before the navigation it does
 * nothing). `clock: 'pinned'` freezes Date (Date.now() and `new Date()` with no argument); `'live'` leaves it alone.
 * Math.random is always seeded (mulberry32). performance.now and requestAnimationFrame stay native.
 */
export function bootstrapSource({ clock = 'pinned', seed = 0x2f6e2b1 } = {}) {
  const pin = clock === 'pinned'
    ? `const T0 = Date.parse(${JSON.stringify(PINNED_ISO)}); const RD = Date;
       class FD extends RD { constructor(...a) { if (a.length) super(...a); else super(T0); } static now() { return T0; } }
       globalThis.Date = FD;`
    : '';
  return `(() => { ${pin}
    let a = ${seed >>> 0};
    Math.random = () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
    window.__wkBootstrap = ${JSON.stringify(clock)};
  })();`;
}

/** Install the bootstrap script on this connection, then reload and wait for load + readyState complete. */
export async function loadFresh(c, { clock = 'pinned', settleMs = 6000 } = {}) {
  await c.enable('Page');
  await c.send('Page.setBootstrapScript', { source: bootstrapSource({ clock }) });
  // A load event only counts after this reload's frameNavigated (a load still in flight from before would
  // otherwise be taken for the reload's).
  let loaded = false, navigated = false;
  const off = c.on((m) => {
    if (m.method === 'Page.frameNavigated') navigated = true;
    else if (m.method === 'Page.loadEventFired' && navigated) loaded = true;
  });
  await c.send('Page.reload', {});
  for (let i = 0; i < 240 && !loaded; i++) await sleep(100);
  off();
  if (!loaded) throw new Error('Page.loadEventFired did not arrive in 24 s');
  for (let i = 0; i < 120; i++) { if ((await c.evaluate('document.readyState')) === 'complete') break; await sleep(100); }
  const mode = await c.evaluate('window.__wkBootstrap || null');
  if (mode !== clock) throw new Error(`bootstrap script did not run (got ${mode})`);
  await sleep(settleMs);
}

/** Wait n animation frames in the page (native requestAnimationFrame). Runs as a poll: evaluate ignores awaitPromise. */
export const RAF_HELPER = `const raf = () => new Promise((r) => requestAnimationFrame(() => r()));`;

/** Scroll to y instantly and wait two rAFs, inside the page. */
export async function scrollHold(c, y, { holdMs = 1500 } = {}) {
  await c.runAsync(`(async () => { ${RAF_HELPER} scrollTo({ top: ${Number(y)}, behavior: 'instant' }); await raf(); await raf(); return scrollY; })()`);
  await sleep(holdMs);
  return c.evaluate('Math.round(scrollY)');
}

export const pageInfo = (c) => c.evaluate(`JSON.stringify({ ua: navigator.userAgent, vw: innerWidth, vh: innerHeight, dpr: devicePixelRatio, docH: document.documentElement.scrollHeight, maxY: document.documentElement.scrollHeight - innerHeight, clock: window.__wkBootstrap || null })`).then(JSON.parse);
