// Page-level controls shared by census, scroll and seek: the bootstrap script (clock pin, seeded Math.random),
// a reload that keeps the inspector connection, and the rAF helpers.
import { sleep } from './sim.mjs';
import { T } from './timeouts.mjs';

/** Pinned date from the plan (§4.2): before the countdown target 2026-11-02. */
export const PINNED_ISO = '2026-10-01T00:00:00+07:00';

/**
 * Script run before any page script (Page.setBootstrapScript, CONFIRMED working on the iOS 27.0 Simulator when sent on
 * the same connection that then calls Page.reload; sent on a connection that is closed before the navigation it does
 * nothing). `clock: 'pinned'` freezes Date (Date.now() and `new Date()` with no argument); `'live'` leaves it alone.
 * Math.random is always seeded (mulberry32). performance.now and requestAnimationFrame stay native.
 */
export function bootstrapSource({ clock = 'pinned', seed = 0x2f6e2b1, timers = 'live' } = {}) {
  const pin = clock === 'pinned'
    ? `const T0 = Date.parse(${JSON.stringify(PINNED_ISO)}); const RD = Date;
       class FD extends RD { constructor(...a) { if (a.length) super(...a); else super(T0); } static now() { return T0; } }
       globalThis.Date = FD;`
    : '';
  return `(() => { ${pin}
    let a = ${seed >>> 0};
    Math.random = () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
    window.__wkBootstrap = ${JSON.stringify(clock)};
  })(); ${timers === 'hold' ? TIMER_HOLD_SRC : ''}`;
}

/**
 * Timer hold (per-step determinism experiment (b)). The page's own setTimeout/setInterval/requestIdleCallback are
 * wrapped. Until `__wk.hold()` they run on the native timers as usual (the page needs them to finish loading) and are
 * only tracked. After `hold()` every pending timer moves to a virtual queue and nothing the page scheduled with a timer
 * fires by itself: `__wk.advance(ms)` moves virtual time and runs the due callbacks in (due time, creation order).
 * requestAnimationFrame, performance.now, Date (pinned or not), MessageChannel, observers and WebKit's internal timers
 * are NOT touched: native rAF scheduling stays.
 */
export const TIMER_HOLD_SRC = `(() => {
  const nST = setTimeout.bind(globalThis), nCT = clearTimeout.bind(globalThis), nSI = setInterval.bind(globalThis), nCI = clearInterval.bind(globalThis);
  const nRIC = globalThis.requestIdleCallback ? globalThis.requestIdleCallback.bind(globalThis) : null;
  let seq = 0, held = false, vnow = 0, fired = 0, installedLive = 0;
  const live = new Map();
  const queue = [];
  const stats = () => ({ held, vnow, fired, installedLive, live: live.size, queued: queue.length });
  const mk = (repeat) => (fn, d, ...args) => {
    if (typeof fn !== 'function') return (repeat ? nSI : nST)(fn, d, ...args);
    const delay = Math.max(0, Number(d) || 0), id = ++seq;
    if (held) { queue.push({ id, fn, args, t: vnow + delay, repeat: repeat ? Math.max(delay, 1) : 0 }); return id; }
    const e = { id, fn, args, delay, repeat, due: performance.now() + delay, h: 0 };
    if (repeat) e.h = nSI(() => { e.due = performance.now() + delay; fn(...args); }, delay);
    else e.h = nST(() => { live.delete(id); fn(...args); }, delay);
    live.set(id, e); installedLive++;
    return id;
  };
  const clear = (id) => {
    const e = live.get(id);
    if (e) { (e.repeat ? nCI : nCT)(e.h); live.delete(id); }
    const i = queue.findIndex((q) => q.id === id);
    if (i >= 0) queue.splice(i, 1);
  };
  globalThis.setTimeout = mk(false); globalThis.setInterval = mk(true);
  globalThis.clearTimeout = clear; globalThis.clearInterval = clear;
  if (nRIC) {
    globalThis.requestIdleCallback = (fn, o) => {
      if (!held) return nRIC(fn, o);
      const id = ++seq; queue.push({ id, fn: () => fn({ didTimeout: true, timeRemaining: () => 0 }), args: [], t: vnow, repeat: 0 }); return id;
    };
  }
  globalThis.__wk = {
    stats,
    hold() {
      const now = performance.now();
      for (const e of live.values()) {
        (e.repeat ? nCI : nCT)(e.h);
        queue.push({ id: e.id, fn: e.fn, args: e.args, t: vnow + Math.max(0, e.due - now), repeat: e.repeat ? Math.max(e.delay, 1) : 0 });
      }
      live.clear(); held = true; return stats();
    },
    advance(ms) {
      vnow += ms; let n = 0;
      for (;;) {
        let b = -1;
        for (let i = 0; i < queue.length; i++) if (queue[i].t <= vnow && (b < 0 || queue[i].t < queue[b].t || (queue[i].t === queue[b].t && queue[i].id < queue[b].id))) b = i;
        if (b < 0 || n >= 10000) break;
        const e = queue[b];
        if (e.repeat) e.t += e.repeat; else queue.splice(b, 1);
        n++; fired++;
        try { e.fn(...e.args); } catch (err) { queueMicrotask(() => { throw err; }); }
      }
      return n;
    },
  };
})();`;

/** Install the bootstrap script on this connection, then reload and wait for load + readyState complete. */
export async function loadFresh(c, { clock = 'pinned', settleMs = 6000, timers = 'live' } = {}) {
  await c.enable('Page');
  await c.send('Page.setBootstrapScript', { source: bootstrapSource({ clock, timers }) });
  // A load event only counts after this reload's frameNavigated (a load still in flight from before would
  // otherwise be taken for the reload's).
  let loaded = false, navigated = false;
  const off = c.on((m) => {
    if (m.method === 'Page.frameNavigated') navigated = true;
    else if (m.method === 'Page.loadEventFired' && navigated) loaded = true;
  });
  await c.send('Page.reload', {});
  for (let i = 0; i < T(240) && !loaded; i++) await sleep(100);
  off();
  if (!loaded) throw new Error(`Page.loadEventFired did not arrive in ${Math.round(T(240) / 10)} s`);
  for (let i = 0; i < T(120); i++) { if ((await c.evaluate('document.readyState')) === 'complete') break; await sleep(100); }
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

export const pageInfo = (c) => c.evaluate(`JSON.stringify({ ua: navigator.userAgent, vw: innerWidth, vh: innerHeight, dpr: devicePixelRatio, docH: document.documentElement.scrollHeight, maxY: document.documentElement.scrollHeight - innerHeight, clock: window.__wkBootstrap || null, fw: window.__fw ? { configHash: window.__fw.configHash, mode: window.__fw.mode, hydrated: window.__fw.hydrated, hydrationErrors: window.__fw.hydrationErrors, buildId: window.__fw.buildId, styleMisses: window.__fw.styleMisses } : null })`).then(JSON.parse);
