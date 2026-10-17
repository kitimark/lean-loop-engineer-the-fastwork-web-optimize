// Clock shim, injected before any page script (Page.addScriptToEvaluateOnNewDocument). Virtual time only:
// Date, setTimeout/setInterval/clear*, requestIdleCallback and performance.now come from one virtual clock that the
// driver advances once per virtual frame. NATIVE requestAnimationFrame, CSS animations and transitions are kept: they
// are driven by the BeginFrame the driver sends (HeadlessExperimental.beginFrame), so rAF callbacks fire inside the
// rendering steps as in real life. Math.random is seeded (mulberry32). The date is pinned to 2026-10-01T00:00:00+07:00.
// Written for this experiment from the public specs; contains no site code.
(() => {
  if (globalThis.__fwclock) return;
  const cfg = globalThis.__FW_CFG || { epochMs: Date.UTC(2026, 8, 30, 17, 0, 0), seed: 0x5eed1234 };
  const NativeDate = Date;
  const EPOCH = cfg.epochMs; // 2026-09-30T17:00:00Z = 2026-10-01T00:00:00+07:00
  let vnow = 0; // virtual ms, also what performance.now() returns
  let seq = 0;
  const timers = new Map(); // id -> { at, seq, fn, args, every }
  let nextId = 1;

  function FakeDate(...a) {
    if (!new.target) return new NativeDate(EPOCH + vnow).toString();
    return a.length ? new NativeDate(...a) : new NativeDate(EPOCH + vnow);
  }
  FakeDate.prototype = NativeDate.prototype;
  FakeDate.now = () => EPOCH + vnow;
  FakeDate.UTC = NativeDate.UTC;
  FakeDate.parse = NativeDate.parse;
  Object.defineProperty(NativeDate.prototype, 'constructor', { value: FakeDate, writable: true, configurable: true });
  globalThis.Date = FakeDate;

  const perfNow = () => vnow;
  Object.defineProperty(Performance.prototype, 'now', { value: perfNow, writable: true, configurable: true });

  function add(fn, delay, args, every) {
    if (typeof fn !== 'function') { const src = String(fn); fn = () => (0, eval)(src); }
    let d = Number(delay); if (!(d >= 1)) d = 1; // 1 ms floor (nested timers clamp to 4 ms in browsers)
    const id = nextId++;
    timers.set(id, { at: vnow + d, seq: ++seq, fn, args, every: every ? d : 0 });
    return id;
  }
  globalThis.setTimeout = (fn, d, ...a) => add(fn, d, a, false);
  globalThis.setInterval = (fn, d, ...a) => add(fn, d, a, true);
  globalThis.clearTimeout = globalThis.clearInterval = (id) => { timers.delete(id); };
  globalThis.requestIdleCallback = (fn) => add(() => fn({ didTimeout: false, timeRemaining: () => 10 }), 1, [], false);
  globalThis.cancelIdleCallback = (id) => { timers.delete(id); };

  function mulberry32(a) {
    return () => { a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }
  Math.random = mulberry32(cfg.seed);

  // Run every timer due at or before `to`, in (at, seq) order; then set the clock to `to`. Returns how many fired.
  function advanceTo(to) {
    let fired = 0;
    for (;;) {
      let best = null, bestId = 0;
      for (const [id, t] of timers) if (t.at <= to && (!best || t.at < best.at || (t.at === best.at && t.seq < best.seq))) { best = t; bestId = id; }
      if (!best) break;
      if (best.at > vnow) vnow = best.at;
      if (best.every) { best.at += best.every; best.seq = ++seq; } else timers.delete(bestId);
      fired++;
      try { best.fn(...best.args); } catch (e) { setTimeout.__errors = (setTimeout.__errors || 0) + 1; queueMicrotask(() => { throw e; }); }
      if (fired > 100000) throw new Error('fw clock: runaway timers');
    }
    if (to > vnow) vnow = to;
    return fired;
  }
  // requestAnimationFrame stays native (callbacks run inside the rendering steps of the BeginFrame the driver sends).
  // Only the timestamp argument is replaced by the virtual frame time: the native value is ticks minus the document's
  // time origin, and that origin differs from run to run, which would leak into any page code that uses it.
  const nativeRaf = globalThis.requestAnimationFrame.bind(globalThis);
  globalThis.requestAnimationFrame = (cb) => nativeRaf(() => cb(vnow));
  globalThis.__fwclock = { advanceTo, now: () => vnow, pending: () => timers.size, epochMs: EPOCH };
})();
