// The page-side recorder in a stub window: touches set the finger direction, scrollTo with instant is a pin write, r follows --morph.
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { START_JS, FETCH_JS } from '../src/throttle/finish-page.mjs';

test('the recorder reads the finger direction, the morph value and the pin writes per frame', () => {
  const listeners = {};
  const frames = [];
  const style = { v: '0', getPropertyValue: () => style.v };
  const nav = { isConnected: true, style };
  const win = {
    scrollY: 100, innerHeight: 800, visualViewport: { height: 800, scale: 1 },
    document: { documentElement: { scrollHeight: 1000 }, querySelector: () => nav },
    addEventListener: (n, f) => { (listeners[n] ??= []).push(f); },
    requestAnimationFrame: (f) => { frames.push(f); },
    scrollTo: (o) => { win.scrollY = o.top; },
  };
  win.window = win;
  const ctx = vm.createContext(win);
  Object.defineProperty(win, 'JSON', { value: JSON });
  assert.equal(vm.runInContext(START_JS, ctx), 'started');
  const fire = (n, e) => (listeners[n] ?? []).forEach((f) => f(e));
  const tick = (ts) => { frames.shift()(ts); };
  fire('scroll', {});
  tick(0);
  fire('touchstart', { touches: [{ clientY: 500 }] });
  fire('touchmove', { touches: [{ clientY: 480 }] });
  style.v = '0.4';
  win.scrollY = 105;
  tick(16);
  fire('touchmove', { touches: [{ clientY: 490 }] });
  style.v = '0.3';
  tick(32);
  win.scrollTo({ top: 106, behavior: 'instant' });
  tick(48);
  tick(64);
  const rec = JSON.parse(vm.runInContext(FETCH_JS, ctx));
  assert.deepEqual(rec.d.slice(0, 3), [0, -1, 1]);
  assert.deepEqual(rec.r.slice(0, 3), [0, 400, 300]);
  assert.equal(rec.wobble, 1);
  assert.equal(rec.moves, 2);
  assert.deepEqual(rec.ca, [[1060, 1, 3]]);
});
