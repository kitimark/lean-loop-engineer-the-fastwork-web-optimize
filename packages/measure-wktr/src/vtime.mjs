// Virtual time for the page (variant `vt`), and the cause trace (`trace`). Both are page scripts as strings; they run
// before any page script (the harness is the first child of <head>).
//
// WHY. WKTR gives no BeginFrame control: the engine renders at its own pace and the page reads real time. Everything
// the page schedules from real time (performance.now / rAF timestamps in spring tweens, setTimeout / setInterval
// delays) therefore lands on a different frame in every pass. The Chromium lane removes that with a virtual clock the
// driver advances once per frame (packages/measure-chromium/src/clock-shim.js); this is the same idea for WebKit.
//
// WHAT vt DOES. One virtual clock `vnow` (ms) that advances by 1000/60 per native animation frame.
//   - requestAnimationFrame / cancelAnimationFrame are wrapped on top of the NATIVE requestAnimationFrame: one native
//     frame callback (the pump) advances the clock, runs the timers that are due, then runs the page's rAF callbacks in
//     registration order with timestamp `vnow`. The native frame is still the engine's; nothing is seeked or replayed.
//   - setTimeout / setInterval / clear* / requestIdleCallback run on the same clock: a timer with delay d fires in the
//     first pump with vnow >= creation vnow + d (so setTimeout(f, 0) fires on the next frame).
//   - performance.now() and Date.now() / new Date() return the virtual time (Date is the pinned date + vnow).
//   NOT touched: CSS animations / transitions / document.timeline (WebKit's own animation clock), IntersectionObserver
//   and ResizeObserver delivery, image decode and network arrival, microtasks, MessageChannel. If the counts still drift
//   with vt, those are the remaining real-time sources (the trace says which events moved).
// Limitation: timers run inside the rAF phase, not as separate tasks before the rendering update.
//
// Exposes window.__fwVt = { now(), frames(), fired() } when active.
import { PINNED_ISO } from '../../measure-webkit/src/page.mjs';

export const VT_SRC = `(() => {
  const FRAME = 1000 / 60;
  const nRAF = window.requestAnimationFrame.bind(window);
  const nST = window.setTimeout.bind(window);
  const RD = Date;
  const T0 = RD.parse(${JSON.stringify(PINNED_ISO)});
  let vnow = 0, frames = 0, rseq = 0, tseq = 0, scheduled = false, firedTimers = 0;
  const rafQ = new Map();
  const timers = new Map();
  const report = (e) => { try { if (typeof reportError === 'function') reportError(e); else console.error(String(e)); } catch (_) {} };
  const hooks = { onRaf: null, onTimer: null };
  window.__fwHooks = hooks;
  const dueTimers = () => {
    for (let guard = 0; guard < 10000; guard++) {
      let best = null;
      for (const t of timers.values()) if (t.at <= vnow && (best === null || t.at < best.at || (t.at === best.at && t.seq < best.seq))) best = t;
      if (best === null) return;
      if (best.every > 0) { best.at += best.every; best.seq = ++tseq; } else timers.delete(best.id);
      firedTimers++;
      if (hooks.onTimer) hooks.onTimer(best.delay, best.every > 0);
      try { best.fn(...best.args); } catch (e) { report(e); }
    }
  };
  const pump = () => {
    scheduled = false;
    frames++;
    vnow += FRAME;
    dueTimers();
    const cbs = Array.from(rafQ);
    rafQ.clear();
    for (const [, fn] of cbs) { if (hooks.onRaf) hooks.onRaf(); try { fn(vnow); } catch (e) { report(e); } }
    if (timers.size > 0 || rafQ.size > 0) kick();
  };
  function kick() { if (!scheduled) { scheduled = true; nRAF(pump); } }
  window.requestAnimationFrame = (fn) => { if (typeof fn !== 'function') throw new TypeError('requestAnimationFrame: callback is not a function'); const id = ++rseq; rafQ.set(id, fn); kick(); return id; };
  window.cancelAnimationFrame = (id) => { rafQ.delete(id); };
  const mk = (every) => (fn, d, ...args) => {
    if (typeof fn !== 'function') return nST(fn, d);
    const delay = Math.max(0, Number(d) || 0), id = ++tseq;
    timers.set(id, { id, fn, args, delay, at: vnow + delay, every: every ? Math.max(delay, 1) : 0, seq: id });
    kick();
    return id;
  };
  window.setTimeout = mk(false);
  window.setInterval = mk(true);
  window.clearTimeout = window.clearInterval = (id) => { timers.delete(id); };
  if (typeof window.requestIdleCallback === 'function') {
    window.requestIdleCallback = (fn) => window.setTimeout(() => fn({ didTimeout: false, timeRemaining: () => 10 }), 1);
    window.cancelIdleCallback = (id) => window.clearTimeout(id);
  }
  Object.defineProperty(Performance.prototype, 'now', { value: function now() { return vnow; }, writable: true, configurable: true });
  const vdate = () => T0 + Math.floor(vnow);
  window.Date = new Proxy(RD, {
    construct: (t, a, nt) => Reflect.construct(t, a.length ? a : [vdate()], nt),
    get: (t, p) => (p === 'now' ? vdate : Reflect.get(t, p, t)),
  });
  window.__fwVt = { now: () => vnow, frames: () => frames, fired: () => firedTimers, native: { raf: nRAF, setTimeout: nST } };
})();`;

// Cause trace (variant flag `trace`): counts of the events that can restyle or lay out the page, so that the steps whose
// recalc counts differ between passes can be compared with the events that differ. Wraps (never replaces) page-visible
// APIs: callbacks are counted then called; IntersectionObserver / ResizeObserver subclass the native ones. Counters are
// monotone and read by the harness's samples as `ev`.
export const TRACE_SRC = `(() => {
  const ev = Object.create(null);
  const bump = (k, n = 1) => { ev[k] = (ev[k] || 0) + n; };
  window.__fwEv = ev;
  const h = window.__fwHooks;
  if (h) { h.onRaf = () => bump('raf'); h.onTimer = (d, rep) => { bump('timer'); bump((rep ? 'interval' : 'timeout') + d); }; }
  else {
    const nRAF = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = (fn) => nRAF((t) => { bump('raf'); return fn(t); });
    const nST = window.setTimeout.bind(window), nSI = window.setInterval.bind(window);
    window.setTimeout = (fn, d, ...a) => (typeof fn === 'function' ? nST(() => { bump('timer'); bump('timeout' + Math.max(0, Number(d) || 0)); return fn(...a); }, d) : nST(fn, d));
    window.setInterval = (fn, d, ...a) => (typeof fn === 'function' ? nSI(() => { bump('timer'); bump('interval' + Math.max(0, Number(d) || 0)); return fn(...a); }, d) : nSI(fn, d));
  }
  const wrapObs = (name, key) => {
    const N = window[name];
    if (typeof N !== 'function') return;
    window[name] = class extends N { constructor(cb, o) { super((...a) => { bump(key); bump(key + 'Entries', a[0] ? a[0].length : 0); return cb(...a); }, o); } };
  };
  wrapObs('IntersectionObserver', 'io');
  wrapObs('ResizeObserver', 'ro');
  wrapObs('MutationObserver', 'mo');
  for (const [type, key] of [['scroll', 'scrollEv'], ['transitionrun', 'transitionrun'], ['transitionstart', 'transitionstart'], ['transitionend', 'transitionend'],
    ['animationstart', 'animationstart'], ['animationiteration', 'animationiteration'], ['animationend', 'animationend'], ['load', 'load'], ['error', 'error'], ['resize', 'resizeEv']]) {
    window.addEventListener(type, () => bump(key), { capture: true, passive: true });
  }
})();`;
