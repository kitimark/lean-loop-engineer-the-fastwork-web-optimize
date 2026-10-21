import { createTweenDriver, type TweenEnv } from './driver';
import { DURATION_MS, ease } from './logic';
import { createWaapiDriver, type AnimLike, type WaapiEnv } from './waapi.driver';
import type { WaapiArm } from './waapi.logic';

type Fn = (e: never) => void;
export interface Call {
  target: 'nav' | 'platform';
  keyframes: Record<string, string | number>[];
  options: unknown;
  anim: FakeAnim;
}
export interface FakeAnim extends AnimLike {
  cancelled: boolean;
  fired: boolean;
  progress: number | null;
}
export interface FakeMarker extends AnimLike {
  cancelled: boolean;
  duration: number;
  fired: boolean;
}

/** Test doubles for the `waapi` driver: fake elements whose `animate` records its calls, a settable timeline, listeners,
 * markers and frame callbacks; `frameAt(T)` runs one frame at timeline time `T` (finish events, then frame callbacks);
 * `bases` logs the base `--morph` writes with their timeline time, `scriptFrames` counts the frames that ran script. */
export function waapiRun(over: Partial<{ reduced: boolean; arm: WaapiArm }> = {}) {
  const calls: Call[] = [];
  const listeners = new Map<string, Fn>();
  const settled: { value: number; props: unknown }[] = [];
  const hints: number[] = [];
  const bases: { t: number | null; value: number }[] = [];
  let timeline: number | null = 1234.5;
  let clockSubscribes = 0;
  let scriptRuns = 0;
  let scriptFrames = 0;
  const markers: FakeMarker[] = [];
  const frameCbs = new Set<() => void>();
  const mk = (target: 'nav' | 'platform') => ({
    getBoundingClientRect: () => ({ height: 500, bottom: 800 }),
    animate(keyframes: Record<string, string | number>[], options: unknown) {
      const a: FakeAnim = { startTime: null, onfinish: null, cancelled: false, fired: false, progress: 0, cancel() { a.cancelled = true; }, effect: { getComputedTiming: () => ({ progress: a.progress }) } };
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
    base: (value) => void bases.push({ t: timeline, value }),
    marker: (duration, startTime) => {
      const m: FakeMarker = { startTime, onfinish: null, cancelled: false, duration, fired: false, cancel() { m.cancelled = true; }, effect: null };
      markers.push(m);
      return m;
    },
    everyFrame: (cb) => {
      clockSubscribes++;
      frameCbs.add(cb);
      return () => void frameCbs.delete(cb);
    },
  };
  const d = createWaapiDriver(env, over.arm ?? 'waapi');
  d.setNear(true);
  const wheel = (deltaY: number) => {
    let prevented = false;
    (listeners.get('wheel') as unknown as (e: unknown) => void)({ deltaY, preventDefault: () => (prevented = true) });
    return prevented;
  };
  return {
    d, calls, settled, hints, bases, listeners, wheel,
    setTimeline: (t: number | null) => (timeline = t),
    clockSubscribes: () => clockSubscribes,
    finish: () => calls.filter((c) => !c.anim.cancelled).forEach((c) => c.anim.onfinish?.()),
    markers,
    scriptRuns: () => scriptRuns,
    scriptFrames: () => scriptFrames,
    frameAt: (T: number) => {
      timeline = T;
      const runsBefore = scriptRuns;
      const live = calls.filter((c) => !c.anim.cancelled);
      for (const c of live) c.anim.progress = ease({ x: (T - (c.anim.startTime ?? T)) / DURATION_MS });
      const done = live.filter((c) => !c.anim.fired && T >= (c.anim.startTime ?? T) + DURATION_MS);
      for (const c of done) c.anim.fired = true;
      const due = markers.filter((m) => !m.cancelled && !m.fired && T >= (m.startTime ?? T) + m.duration);
      for (const m of due) m.fired = true;
      for (const c of done) if (c.anim.onfinish) (scriptRuns++, c.anim.onfinish());
      for (const m of due) if (m.onfinish) (scriptRuns++, m.onfinish());
      for (const cb of [...frameCbs]) (scriptRuns++, cb());
      if (scriptRuns > runsBefore) scriptFrames++;
    },
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
