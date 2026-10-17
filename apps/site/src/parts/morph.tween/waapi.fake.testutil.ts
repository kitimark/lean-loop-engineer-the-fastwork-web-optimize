import { createTweenDriver, type TweenEnv } from './driver';
import { createWaapiDriver, type AnimLike, type WaapiEnv } from './waapi.driver';

type Fn = (e: never) => void;
export interface Call {
  target: 'nav' | 'platform';
  keyframes: Record<string, string | number>[];
  options: unknown;
  anim: FakeAnim;
}
export interface FakeAnim extends AnimLike {
  cancelled: boolean;
  progress: number | null;
}

/** Test doubles for the `waapi` driver: fake elements whose `animate` records its calls, a settable timeline, listeners. */
export function waapiRun(over: Partial<{ reduced: boolean }> = {}) {
  const calls: Call[] = [];
  const listeners = new Map<string, Fn>();
  const settled: { value: number; props: unknown }[] = [];
  const hints: number[] = [];
  let timeline: number | null = 1234.5;
  let clockSubscribes = 0;
  const mk = (target: 'nav' | 'platform') => ({
    getBoundingClientRect: () => ({ height: 500, bottom: 800 }),
    animate(keyframes: Record<string, string | number>[], options: unknown) {
      const a: FakeAnim = { startTime: null, onfinish: null, cancelled: false, progress: 0, cancel() { a.cancelled = true; }, effect: { getComputedTiming: () => ({ progress: a.progress }) } };
      calls.push({ target, keyframes, options, anim: a });
      return a;
    },
  });
  const nav = mk('nav');
  const platform = mk('platform');
  const env: WaapiEnv = {
    timelineNow: () => timeline,
    reduced: () => over.reduced ?? false,
    viewportHeight: () => 800,
    nav: () => nav,
    platform: () => platform,
    scrollY: () => 0,
    scrollToInstant() {},
    addListener: (t, fn) => void listeners.set(t, fn),
    removeListener: (t) => void listeners.delete(t),
    settle: (value, props) => void settled.push({ value, props }),
    hint: (v) => void hints.push(v),
  };
  const d = createWaapiDriver(env);
  d.setNear(true);
  const wheel = (deltaY: number) => {
    let prevented = false;
    (listeners.get('wheel') as unknown as (e: unknown) => void)({ deltaY, preventDefault: () => (prevented = true) });
    return prevented;
  };
  return {
    d, calls, settled, hints, listeners, wheel,
    setTimeline: (t: number | null) => (timeline = t),
    clockSubscribes: () => clockSubscribes,
    finish: () => calls.filter((c) => !c.anim.cancelled).forEach((c) => c.anim.onfinish?.()),
  };
}

/** One wheel push on the faithful driver: how many frame callbacks it subscribes. */
export function faithfulSubscribes(): number {
  let subscribes = 0;
  const listeners = new Map<string, Fn>();
  const env: TweenEnv = {
    clock: { subscribe: () => (subscribes++, () => {}) },
    now: () => 0,
    reduced: () => false,
    viewportHeight: () => 800,
    platform: () => ({ getBoundingClientRect: () => ({ height: 500, bottom: 800 }), style: { pointerEvents: '', setProperty() {} } }),
    scrollY: () => 0,
    scrollToInstant() {},
    addListener: (t, fn) => void listeners.set(t, fn),
    removeListener: (t) => void listeners.delete(t),
    publish() {},
  };
  const d = createTweenDriver(env);
  d.setNear(true);
  (listeners.get('wheel') as unknown as (e: unknown) => void)({ deltaY: 100, preventDefault() {} });
  return subscribes;
}
