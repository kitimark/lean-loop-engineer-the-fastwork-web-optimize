import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { VT_SRC, TRACE_SRC } from '../src/vtime.mjs';

// A fake browser window: its native requestAnimationFrame is a queue that frame() drains (one "engine frame").
function fakeWindow() {
  const native = [];
  class Performance { now() { return 123456; } }
  const w = {
    Date, Performance, Math, Object, Reflect, Proxy, Array, Map, Number, TypeError, console,
    requestAnimationFrame: (fn) => { native.push(fn); return native.length; },
    setTimeout: (fn, d) => setTimeout(fn, d),
    cancelAnimationFrame: () => {},
  };
  w.window = w; w.performance = new Performance();
  vm.createContext(w);
  w.frame = () => { const q = native.splice(0); for (const f of q) f(0); return q.length; };
  return w;
}

test('vt: rAF callbacks get the virtual time, one frame is 1000/60 ms, timers fire on their frame', () => {
  const w = fakeWindow();
  vm.runInContext(VT_SRC, w);
  vm.runInContext(`
    var __log = [];
    requestAnimationFrame((t) => { globalThis.__ts = [t]; });
    setTimeout(() => __log.push('t0'), 0);
    setTimeout(() => __log.push('t50'), 50);
    var iv = setInterval(() => __log.push('i'), 100);
  `, w);
  w.frame();
  assert.ok(Math.abs(w.__ts[0] - 1000 / 60) < 1e-9);
  assert.deepEqual(Array.from(w.__log), ['t0']);
  for (let i = 0; i < 3; i++) w.frame(); // 4 frames = 66.7 ms: t50 is due
  assert.deepEqual(Array.from(w.__log), ['t0', 't50']);
  for (let i = 0; i < 6; i++) w.frame(); // 10 frames = 166.7 ms: the interval fired once at 100 ms
  assert.equal(w.__log.filter((x) => x === 'i').length, 1);
  assert.ok(Math.abs(vm.runInContext('performance.now()', w) - (10 * 1000) / 60) < 1e-6);
});

test('vt: clearTimeout, cancelAnimationFrame and Date', () => {
  const w = fakeWindow();
  vm.runInContext(VT_SRC, w);
  const r = vm.runInContext(`
    var n = 0;
    var a = setTimeout(() => n++, 10); clearTimeout(a);
    var b = requestAnimationFrame(() => { n += 100; }); cancelAnimationFrame(b);
    requestAnimationFrame(() => {});
    [typeof Date.now(), new Date() instanceof Date, typeof Date(), Date.now() === new Date().getTime()]
  `, w);
  for (let i = 0; i < 5; i++) w.frame();
  assert.equal(w.n, 0);
  assert.deepEqual(Array.from(r), ['number', true, 'string', true]);
  const t0 = vm.runInContext('Date.now()', w);
  vm.runInContext('setTimeout(() => {}, 2000)', w);
  for (let i = 0; i < 70; i++) w.frame();
  assert.ok(vm.runInContext('Date.now()', w) > t0);
});

test('vt: a throwing callback does not stop the others; the pump keeps going while timers are pending', () => {
  const w = fakeWindow();
  vm.runInContext(VT_SRC, w);
  vm.runInContext(`var ok = 0; requestAnimationFrame(() => { throw new Error('x'); }); requestAnimationFrame(() => { ok++; }); setTimeout(() => { ok += 10; }, 100);`, w);
  for (let i = 0; i < 8; i++) w.frame();
  assert.equal(w.ok, 11);
});

test('trace over vt: counts rAF callbacks, timers by delay, and observers', () => {
  const w = fakeWindow();
  w.IntersectionObserver = class { constructor(cb) { this.cb = cb; } };
  w.addEventListener = () => {};
  vm.runInContext(VT_SRC + TRACE_SRC, w);
  vm.runInContext(`requestAnimationFrame(() => {}); setTimeout(() => {}, 900); new IntersectionObserver(() => {}).cb([1, 2]);`, w);
  for (let i = 0; i < 70; i++) w.frame();
  const ev = vm.runInContext('Object.assign({}, __fwEv)', w);
  assert.equal(ev.raf, 1);
  assert.equal(ev.timer, 1);
  assert.equal(ev.timeout900, 1);
  assert.equal(ev.io, 1);
  assert.equal(ev.ioEntries, 2);
});
