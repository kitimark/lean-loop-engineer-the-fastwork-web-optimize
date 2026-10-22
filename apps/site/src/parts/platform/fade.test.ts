import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { createTweenDriver, type TweenEnv } from '../morph.tween/driver';
import { ease } from '../morph.tween/logic';
import { createThreadedFade, type FadeAnim, type FadeEl } from './fade.driver';
import { blurOf, constants, EASING_CSS, keyframes } from './fade.logic';

goldenConformance('platform-fade', {
  const: () => constants(),
  keyframes: (i) => keyframes(i.from as number, i.to as number),
});

interface Anim extends FadeAnim {
  kfs: { offset: number; opacity: number; filter: string }[];
  opts: { duration: number; easing: string; fill: 'both' };
  cancelled: boolean;
}

function sample(a: Anim, T: number): { opacity: number; blur: number } {
  const p = ease({ x: Math.min(1, Math.max(0, (T - (a.startTime ?? T)) / a.opts.duration)) });
  const i = Math.max(0, a.kfs.findIndex((k) => p <= k.offset) - 1);
  const [k0, k1] = [a.kfs[i]!, a.kfs[i + 1]!];
  const u = (p - k0.offset) / (k1.offset - k0.offset);
  const px = (k: { filter: string }) => Number(/blur\((.*)px\)/.exec(k.filter)![1]);
  return { opacity: k0.opacity + (k1.opacity - k0.opacity) * u, blur: px(k0) + (px(k1) - px(k0)) * u };
}

type Ev = { wheel: number } | { frame: number } | { reduced: boolean };

function rig(threaded: boolean) {
  let now = 0;
  let reduced = false;
  const frames = new Set<(t: number) => void>();
  let wheel: ((e: { deltaY: number; preventDefault(): void }) => void) | undefined;
  const props: Record<string, string> = {};
  const writes: string[] = [];
  const anims: Anim[] = [];
  const el: FadeEl = {
    animate(kfs, opts) {
      const a: Anim = { kfs, opts, startTime: null, cancelled: false, cancel: () => void (a.cancelled = true) };
      anims.push(a);
      return a;
    },
    style: { setProperty: (n, v) => void ((props[n] = v), writes.push(n)) },
  };
  const env: TweenEnv = {
    clock: { subscribe: (tick) => (frames.add(tick), () => void frames.delete(tick)) },
    now: () => now,
    reduced: () => reduced,
    viewportHeight: () => 800,
    platform: () => ({ getBoundingClientRect: () => ({ height: 500, bottom: 800 }), style: { pointerEvents: '', setProperty: el.style.setProperty } }),
    scrollY: () => 1200,
    scrollToInstant: () => {},
    addListener: (t, fn) => void (t === 'wheel' && (wheel = fn as never)),
    removeListener: () => {},
    publish: () => {},
    fade: threaded ? createThreadedFade(() => el) : undefined,
  };
  const d = createTweenDriver(env);
  d.setNear(true);
  const shown = (T: number) => {
    const live = anims.filter((a) => !a.cancelled).at(-1);
    if (live) return sample(live, T);
    const v = Number(props['--morph-fade'] ?? '1');
    return { opacity: v, blur: blurOf(v) };
  };
  const run = (ev: Ev) => {
    if ('wheel' in ev) wheel?.({ deltaY: ev.wheel, preventDefault: () => {} });
    else if ('reduced' in ev) reduced = ev.reduced;
    else {
      now = ev.frame;
      for (const f of [...frames]) f(ev.frame);
    }
  };
  return { run, shown, writes, anims, setNow: (t: number) => void (now = t) };
}

const ticks = (from: number, to: number) => Array.from({ length: Math.floor((to - from) / 16) + 1 }, (_, k) => ({ frame: from + 16 * k }));

function play(events: Array<[number, Ev]>) {
  const base = rig(false);
  const thr = rig(true);
  const out: Array<{ T: number; base: { opacity: number; blur: number }; thr: { opacity: number; blur: number } }> = [];
  for (const [t, ev] of events) {
    for (const r of [base, thr]) {
      r.setNow(t);
      r.run(ev);
    }
    if ('frame' in ev) out.push({ T: t, base: base.shown(t), thr: thr.shown(t) });
  }
  return { out, base, thr };
}

const at = (evs: Ev[]): Array<[number, Ev]> => evs.map((e) => ['frame' in e ? e.frame : 0, e]);

describe('platform variant fade-threaded (Lean PlatformFade)', () => {
  it('shows the original fade and blur on every frame of an open and a close (threaded_eq, frame_blur_eq)', () => {
    const evs: Array<[number, Ev]> = [[3, { wheel: 50 }], ...at(ticks(8, 900)), [905, { wheel: -50 }], ...at(ticks(910, 1800))];
    const { out } = play(evs);
    for (const o of out) {
      expect(o.thr.opacity, `T=${o.T}`).toBeCloseTo(o.base.opacity, 9);
      expect(o.thr.blur, `T=${o.T}`).toBeCloseTo(o.base.blur, 9);
    }
    expect(out.some((o) => o.base.opacity > 0 && o.base.opacity < 1)).toBe(true);
  });

  it('a retarget mid-push starts its effect at the shown fade (retarget_from_shown)', () => {
    const evs: Array<[number, Ev]> = [[3, { wheel: 50 }], ...at(ticks(8, 120)), [130, { wheel: -50 }], ...at(ticks(136, 900))];
    const { out, thr } = play(evs);
    for (const o of out) expect(o.thr.opacity, `T=${o.T}`).toBeCloseTo(o.base.opacity, 9);
    expect(thr.anims).toHaveLength(2);
    expect(thr.anims[1]!.kfs[0]!.opacity).toBeCloseTo(out.findLast((o) => o.T < 130)!.thr.opacity, 9);
  });

  it('writes --morph-fade only when a push settles or jumps, never per frame', () => {
    const evs: Array<[number, Ev]> = [[3, { wheel: 50 }], ...at(ticks(8, 900))];
    const { base, thr } = play(evs);
    expect(base.writes.filter((w) => w === '--morph-fade').length).toBeGreaterThan(40);
    expect(thr.writes.filter((w) => w === '--morph-fade')).toHaveLength(1);
    expect(thr.anims[0]!.opts).toEqual({ duration: 680, easing: EASING_CSS, fill: 'both' });
    expect(thr.anims[0]!.startTime).toBe(3);
  });

  it('a reduced-motion push jumps: no effect, the end fade inline', () => {
    const evs: Array<[number, Ev]> = [[0, { reduced: true }], [3, { wheel: 50 }], ...at(ticks(8, 100))];
    const { out, thr } = play(evs);
    expect(thr.anims).toHaveLength(0);
    for (const o of out) expect(o.thr).toEqual(o.base);
  });
});
