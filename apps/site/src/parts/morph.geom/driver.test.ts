import { describe, expect, it } from 'vitest';
import { createGeomDriver, M_DURATION, timeOf, type AnimHandle, type GeomEnv } from './driver';
import { TIME_END, type Anim, type Layout } from './tracks';
import { tween } from '../morph.tween/logic';

const layout: Layout = { eng: 'webkit', a: 0, b: 1, inset: 24, logoW: 160, lw: 144, w0: 176, gL: 0, imgs: [[[0, 200]]] };

function fake(allowed = true) {
  const log: string[] = [];
  const handles: (AnimHandle & { a: Anim; duration: number; cancelled: boolean })[] = [];
  const env: GeomEnv = {
    allowed: () => allowed,
    enter: () => (log.push('enter'), { vp: { w: 1280, h: 800 }, layout }),
    leave: () => void log.push('leave'),
    animate: (a, kf, duration) => {
      if (a.el === 'earnClip') return null;
      expect(kf[0].offset).toBe(0);
      const h = { a, duration, currentTime: -1, cancelled: false, cancel: () => void (h.cancelled = true) };
      handles.push(h);
      return h;
    },
  };
  return { env, log, handles };
}

describe('morph.geom driver', () => {
  it('stays out of the way at m = 0, on the fallback guard, and enters once', () => {
    const f = fake();
    const d = createGeomDriver(f.env);
    d.apply(0);
    expect(f.log).toEqual([]);
    d.apply(0.3);
    d.apply(0.5);
    expect(f.log).toEqual(['enter']);
    const g = fake(false);
    createGeomDriver(g.env).apply(0.5);
    expect(g.log).toEqual([]);
  });

  it('writes currentTime only: 1000 m on m tracks, the tween time on time tracks', () => {
    const f = fake();
    const d = createGeomDriver(f.env);
    d.apply(0.5);
    const m = f.handles.find((h) => h.a.ks === 'unit')!;
    const t = f.handles.find((h) => h.a.ks === 'time')!;
    expect(m.duration).toBe(M_DURATION);
    expect(m.currentTime).toBe(500);
    expect(t.duration).toBe(TIME_END);
    expect(tween({ from: 0, to: 1, elapsed: t.currentTime }).value).toBeCloseTo(0.5, 9);
  });

  it('timeOf inverts the tween and clamps', () => {
    for (const m of [0, 0.1, 0.5, 0.99]) expect(tween({ from: 0, to: 1, elapsed: timeOf(m) }).value).toBeCloseTo(m, 9);
    expect(timeOf(1)).toBe(680);
    expect(timeOf(7)).toBe(680);
  });

  it('m back at 0 cancels every effect and leaves; dispose does the same', () => {
    const f = fake();
    const d = createGeomDriver(f.env);
    d.apply(1);
    d.apply(0);
    expect(f.handles.every((h) => h.cancelled)).toBe(true);
    expect(f.log).toEqual(['enter', 'leave']);
    expect(d.active()).toBe(false);
    d.apply(0.2);
    d.dispose();
    expect(f.log).toEqual(['enter', 'leave', 'enter', 'leave']);
  });
});
