import { describe, expect, it } from 'vitest';
import { createTweenDriver, type PlatformEl, type TweenEnv } from './driver';

type Fn = (e: never) => void;

function setup(over: Partial<{ reduced: boolean; rect: { height: number; bottom: number }; vh: number }> = {}) {
  const o = { reduced: false, rect: { height: 500, bottom: 800 }, vh: 800, ...over };
  let now = 0;
  const frames = new Set<(t: number) => void>();
  let subscribes = 0;
  const listeners = new Map<string, Fn>();
  const props: Record<string, string> = {};
  const platform: PlatformEl = {
    getBoundingClientRect: () => o.rect,
    style: { pointerEvents: '', setProperty: (n, v) => void (props[n] = v) },
  };
  const published: number[] = [];
  let scrollY = 1200;
  const scrolls: number[] = [];
  let activated = 0;
  const env: TweenEnv = {
    clock: {
      subscribe(tick) {
        subscribes++;
        frames.add(tick);
        return () => void frames.delete(tick);
      },
    },
    now: () => now,
    reduced: () => o.reduced,
    viewportHeight: () => o.vh,
    platform: () => platform,
    scrollY: () => scrollY,
    scrollToInstant: (y) => void scrolls.push(y),
    addListener: (t, fn) => void listeners.set(t, fn),
    removeListener: (t) => void listeners.delete(t),
    publish: (v) => void published.push(v),
    onActivate: () => void activated++,
  };
  const d = createTweenDriver(env);
  const step = (t: number) => {
    now = t;
    for (const f of [...frames]) f(t);
  };
  const wheel = (deltaY: number) => {
    let prevented = 0;
    (listeners.get('wheel') as unknown as (e: { deltaY: number; preventDefault(): void }) => void)?.({ deltaY, preventDefault: () => void prevented++ });
    return prevented;
  };
  return { d, o, step, wheel, listeners, props, published, platform, frames, subs: () => subscribes, scrolls, setY: (y: number) => void (scrollY = y), activated: () => activated, setNow: (t: number) => void (now = t) };
}

describe('morph.tween driver', () => {
  it('listens only while near or active; wheel is capture/non-passive', () => {
    const s = setup();
    expect(s.listeners.size).toBe(0);
    s.d.setNear(true);
    expect([...s.listeners.keys()].sort()).toEqual(['touchmove', 'touchstart', 'wheel']);
    s.d.setNear(false);
    expect(s.listeners.size).toBe(0);
  });
  it('at rest only a downward push on an armed platform is taken', () => {
    const s = setup();
    s.d.setNear(true);
    expect(s.wheel(-50)).toBe(0);
    expect(s.wheel(0.5)).toBe(1); // taken (armed, delta > 0) and prevented, but inside the dead zone: no tween
    expect(s.d.state().target).toBe(0);
    const t = setup({ rect: { height: 300, bottom: 800 } });
    t.d.setNear(true);
    expect(t.wheel(50)).toBe(0); // 300 < 0.45 x 800
    expect(s.wheel(50)).toBe(1);
    expect(s.d.state().target).toBe(1);
  });
  it('runs 680 ms on its own rAF registration and ends on 1 with the registration released', () => {
    const s = setup();
    s.d.setNear(true);
    s.setNow(1000);
    s.wheel(50);
    expect(s.frames.size).toBe(1);
    let t = 1000;
    let n = 0;
    while (s.frames.size > 0 && n < 200) {
      t += 1000 / 60;
      s.step(t);
      n++;
    }
    expect(s.published.at(-1)).toBe(1);
    expect(n).toBe(41); // ceil(680 / 16.667) frames, the last one lands on 1
    expect(s.props['--morph-fade']).toBe('0');
    expect(s.platform.style.pointerEvents).toBe('none');
    expect(s.d.attached()).toBe(true); // still active (value 1)
  });
  it('a reversal mid-flight cancels the frame and registers a new one, value continuous', () => {
    const s = setup();
    s.d.setNear(true);
    s.setNow(0);
    s.wheel(50);
    s.step(100);
    const v = s.published.at(-1)!;
    expect(v).toBeGreaterThan(0);
    s.setNow(100);
    s.wheel(-50);
    expect(s.frames.size).toBe(1);
    s.step(100);
    expect(s.published.at(-1)).toBeCloseTo(v, 12);
    expect(s.subs()).toBe(2);
  });
  it('the same direction again is ignored while heading there', () => {
    const s = setup();
    s.d.setNear(true);
    s.wheel(50);
    const n = s.subs();
    expect(s.wheel(80)).toBe(1); // still prevented (active)
    expect(s.subs()).toBe(n);
  });
  it('reduced motion jumps with no frame', () => {
    const s = setup({ reduced: true });
    s.d.setNear(true);
    s.wheel(50);
    expect(s.frames.size).toBe(0);
    expect(s.published).toEqual([1]);
    expect(s.d.state().value).toBe(1);
    s.wheel(-50);
    expect(s.published).toEqual([1, 0]);
    expect(s.d.attached()).toBe(true); // near
  });
  it('listeners are released when the morph ends at rest and the platform is far', () => {
    const s = setup();
    s.d.setNear(true);
    s.wheel(50);
    s.step(100);
    s.d.setNear(false);
    expect(s.d.attached()).toBe(true); // active
    s.wheel(-50);
    s.step(100);
    s.step(900);
    expect(s.d.state().value).toBe(0);
    expect(s.d.attached()).toBe(false);
  });
  it('pins the page while the morph runs', () => {
    const s = setup();
    s.d.setNear(true);
    s.wheel(50);
    s.setY(1300);
    s.d.pin();
    expect(s.scrolls).toEqual([1200]);
    const r = setup();
    r.setY(5);
    r.d.pin();
    expect(r.scrolls).toEqual([]);
  });
  it('touch: delta is previous minus current clientY', () => {
    const s = setup();
    s.d.setNear(true);
    const start = s.listeners.get('touchstart') as unknown as (e: { touches: { clientY: number }[] }) => void;
    const move = s.listeners.get('touchmove') as unknown as (e: { touches: { clientY: number }[]; preventDefault(): void }) => void;
    let prevented = 0;
    start({ touches: [{ clientY: 400 }] });
    move({ touches: [{ clientY: 420 }], preventDefault: () => void prevented++ }); // finger down: delta -20, at rest, ignored
    expect(prevented).toBe(0);
    move({ touches: [{ clientY: 380 }], preventDefault: () => void prevented++ }); // finger up: delta +40
    expect(prevented).toBe(1);
    expect(s.d.state().target).toBe(1);
  });
});
