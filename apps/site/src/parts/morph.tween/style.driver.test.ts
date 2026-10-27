import { describe, expect, it } from 'vitest';
import { createTweenDriver, type TweenEnv } from './driver';

function drv(flip: boolean) {
  let now = 0;
  const timers: { at: number; cb: () => void }[] = [];
  const calls: string[] = [];
  const env: TweenEnv = {
    clock: {
      subscribe: () => () => {},
      interval: (ms, cb) => {
        const t = { at: now + ms, cb };
        timers.push(t);
        return () => void timers.splice(timers.indexOf(t) >>> 0, 1);
      },
    },
    now: () => now,
    reduced: () => false,
    viewportHeight: () => 800,
    platform: () => ({
      getBoundingClientRect: () => ({ height: 500, bottom: 800 }),
      style: { pointerEvents: '', setProperty: (n, v) => void calls.push(`platform ${n} ${v}`) },
    }),
    scrollY: () => 1200,
    scrollToInstant() {},
    addListener: (t, fn) => void (t === 'wheel' && (wheel = fn as never)),
    removeListener() {},
    publish: (v) => void calls.push(`publish ${v}`),
    flip: () => flip,
    syncMorph: (v) => void calls.push(`nav --morph ${v}`),
    timed: {
      take: () => true,
      push() {},
      settle: (m) => void calls.push(`settle ${m}`),
      dispose() {},
    },
  };
  let wheel: (e: { deltaY: number; defaultPrevented: boolean; preventDefault(): void }) => void = () => {};
  const d = createTweenDriver(env);
  d.setNear(true);
  const run = (to: number) => {
    while (timers.length && Math.min(...timers.map((t) => t.at)) <= to) {
      timers.sort((a, b) => a.at - b.at);
      const t = timers.shift()!;
      now = t.at;
      t.cb();
    }
    now = to;
  };
  return { d, run, calls, push: (dy: number) => wheel({ deltaY: dy, defaultPrevented: false, preventDefault() {} }) };
}

describe('the timed leave: the inline values are current before the flip class goes', () => {
  it('a push down and back up to 0 writes --morph and --morph-fade, then settles', () => {
    const s = drv(true);
    s.push(50);
    s.run(1000);
    s.push(-50);
    s.run(3000);
    const i = s.calls.lastIndexOf('settle 0');
    expect(i).toBeGreaterThan(1);
    expect(s.calls.slice(i - 2, i + 1)).toEqual(['nav --morph 0', 'platform --morph-fade 1', 'settle 0']);
  });

  it('settle at 1 does not sync (the flip stays on)', () => {
    const s = drv(true);
    s.push(50);
    s.run(1000);
    expect(s.calls).toContain('settle 1');
    expect(s.calls.some((c) => c.startsWith('nav --morph'))).toBe(false);
  });

  it('flip off (base look): no sync write, as before', () => {
    const s = drv(false);
    s.push(50);
    s.run(1000);
    s.push(-50);
    s.run(3000);
    expect(s.calls.some((c) => c.startsWith('nav --morph'))).toBe(false);
  });

  it('skips the platform fade variable while the flip is on and m > 0', () => {
    const on = drv(true);
    on.push(50);
    on.run(1000);
    const off = drv(false);
    off.push(50);
    off.run(1000);
    const fadeWrites = (c: string[]) => c.filter((x) => x.startsWith('platform --morph-fade')).length;
    expect(fadeWrites(on.calls)).toBeLessThan(fadeWrites(off.calls));
  });
});
