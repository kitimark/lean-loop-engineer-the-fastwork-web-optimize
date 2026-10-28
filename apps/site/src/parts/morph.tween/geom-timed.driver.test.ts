import { describe, expect, it } from 'vitest';
import type { Layout } from '../morph.geom/tracks';
import { createTweenDriver, type TweenEnv } from './driver';
import { createTimedGeom, GOAL_ATTR, type TimedAnim } from './geom-timed.driver';

const layout: Layout = { eng: 'webkit', a: 0, b: 1, inset: 24, logoW: 160, lw: 144, w0: 176, gL: 0, imgs: [[[0, 200]]] };

function setup(allowed = true) {
  const log: string[] = [];
  const handles: (TimedAnim & { opts: { duration: number; easing: string; fill: string }; cancelled: boolean })[] = [];
  let goal: string | null = null;
  const timed = createTimedGeom({
    allowed: () => allowed,
    enter: () => (log.push('enter'), { vp: { w: 1280, h: 800 }, layout }),
    leave: () => void log.push('leave'),
    fresh: () => true,
    animate: (_a, _kf, opts) => {
      const h = { startTime: null as number | null, opts, cancelled: false, cancel: () => void (h.cancelled = true), pause: () => void 0 };
      handles.push(h);
      return h;
    },
    goal: (r) => void (goal = r),
  });
  return { timed, log, handles, goal: () => goal };
}

describe('createTimedGeom', () => {
  it('a push is one animation per track on one shared start, 680 ms; the goal style is the base for a push up', () => {
    const s = setup();
    expect(s.timed.take(0, 1, 1234)).toBe(true);
    expect(s.log).toEqual(['enter']);
    expect(new Set(s.handles.map((h) => h.startTime))).toEqual(new Set([1234]));
    expect(new Set(s.handles.map((h) => h.opts.duration))).toEqual(new Set([680]));
    expect(s.handles.some((h) => h.opts.easing.startsWith('cubic-bezier(0.3333'))).toBe(true);
    expect(s.goal()).toContain(`html[${GOAL_ATTR}] [data-mg="panel"]`);
    expect(new Set(s.handles.map((h) => h.opts.fill))).toEqual(new Set(['backwards']));
  });
  it('a reversal cancels the set in flight and starts a new one on the event time; settle at 0 leaves', () => {
    const s = setup();
    s.timed.take(0, 1, 0);
    const n = s.handles.length;
    s.timed.take(0.4, 0, 300);
    expect(s.handles.slice(0, n).every((h) => h.cancelled)).toBe(true);
    expect(s.handles.slice(n).every((h) => h.startTime === 300 && !h.cancelled && h.opts.fill === 'both')).toBe(true);
    expect(s.goal()).toBeNull();
    s.timed.settle(1);
    expect(s.log).toEqual(['enter']);
    s.timed.settle(0);
    expect(s.log).toEqual(['enter', 'leave']);
    expect(s.handles.every((h) => h.cancelled)).toBe(true);
    expect(s.timed.live()).toBe(false);
  });
  it('settle at 1 drops the animations and keeps the geometry; falls back (false) where geom is not allowed', () => {
    const s = setup();
    s.timed.take(0, 1, 0);
    s.timed.settle(1);
    expect(s.handles.every((h) => h.cancelled)).toBe(true);
    expect(s.timed.live()).toBe(true);
    expect(s.goal()).toContain(`html[${GOAL_ATTR}]`);
    expect(setup(false).timed.take(0, 1, 0)).toBe(false);
    expect(setup().timed.take(1, 0, 0)).toBe(true);
    expect(setup(false).timed.take(1, 0, 0)).toBe(false);
  });
});

describe('tween driver with the timed geometry', () => {
  function drv() {
    let now = 0;
    const timers: { ms: number; at: number; cb: () => void }[] = [];
    const published: number[] = [];
    const calls: string[] = [];
    let rafs = 0;
    const env: TweenEnv = {
      clock: {
        subscribe: () => (rafs++, () => {}),
        interval: (ms, cb) => {
          const t = { ms, at: now + ms, cb };
          timers.push(t);
          return () => void timers.splice(timers.indexOf(t) >>> 0, 1);
        },
      },
      now: () => now,
      reduced: () => false,
      viewportHeight: () => 800,
      platform: () => ({ getBoundingClientRect: () => ({ height: 500, bottom: 800 }), style: { pointerEvents: '', setProperty() {} } }),
      scrollY: () => 1200,
      scrollToInstant() {},
      addListener: (t, fn) => void (t === 'wheel' && (wheel = fn as never)),
      removeListener() {},
      publish: (v) => void published.push(v),
      timed: {
        take: (f, t, s) => (calls.push(`take ${f.toFixed(3)} ${t} ${s}`), true),
        push() {},
        settle: (m) => void calls.push(`settle ${m}`),
        warm: () => void calls.push('warm'),
        cool: () => void calls.push('cool'),
        dispose() {},
      },
    };
    let wheel: (e: { deltaY: number; defaultPrevented: boolean; preventDefault(): void }) => void = () => {};
    const d = createTweenDriver(env);
    d.setNear(true);
    calls.length = 0;
    const run = (to: number) => {
      while (timers.length && timers.reduce((a, t) => Math.min(a, t.at), Infinity) <= to) {
        timers.sort((a, b) => a.at - b.at);
        const t = timers.shift()!;
        now = t.at;
        t.cb();
      }
      now = to;
    };
    return { d, run, published, calls, rafs: () => rafs, push: (dy: number) => wheel({ deltaY: dy, defaultPrevented: false, preventDefault() {} }), setNow: (t: number) => void (now = t) };
  }
  it('no animation frame between push and end; thresholds and the end are published once each', () => {
    const s = drv();
    s.push(50);
    expect(s.rafs()).toBe(0);
    expect(s.calls).toEqual(['take 0.000 1 0']);
    s.run(1000);
    expect(s.published.at(-1)).toBe(1);
    expect(s.published.length).toBe(1 + 7 + 1);
    expect(s.calls.at(-1)).toBe('settle 1');
    expect(s.d.state().pending).toBe(false);
  });
  it('a reversal at 300 ms starts from the event-time value, not the last published one', () => {
    const s = drv();
    s.push(50);
    s.run(300);
    s.push(-50);
    const m = 1 - (1 - 300 / 680) ** 3;
    expect(s.calls.at(-1)).toBe(`take ${m.toFixed(3)} 0 300`);
    s.run(2000);
    expect(s.published.at(-1)).toBe(0);
    expect(s.calls.slice(-2)).toEqual(['settle 0', 'warm']);
  });
  it('warms when the platform is near and the page rests; the end of a flip back to 0 warms again; leaving the range cools', () => {
    const s = drv();
    s.d.pin();
    expect(s.calls).toEqual(['warm']);
    s.push(50);
    s.run(1000);
    s.push(-50);
    s.run(3000);
    expect(s.calls.filter((c) => c === 'warm').length).toBe(2);
    expect(s.calls.at(-1)).toBe('warm');
    s.d.setNear(false);
    expect(s.calls.at(-1)).toBe('cool');
  });
  it('does not warm while a flip is in flight', () => {
    const s = drv();
    s.push(50);
    s.d.pin();
    expect(s.calls).toEqual(['take 0.000 1 0']);
  });
});
