import { describe, expect, it } from 'vitest';
import { createNavDriver, type NavEnv } from './driver';
import type { View } from './logic';

function fake(over: Partial<NavEnv> = {}) {
  const applied: { v: View; e: { tabOff: boolean; ariaHidden: boolean } }[] = [];
  const timers: { ms: number; cb: () => void; live: boolean }[] = [];
  let hero: { top: number; height: number } | null = { top: 0, height: 2000 };
  let morph = 0;
  const env: NavEnv = {
    reduced: () => false,
    narrow: () => false,
    hero: () => hero,
    innerHeight: () => 800,
    sticky: () => ({ present: false, isSticky: false, hasSection: false, top: null, itemTop: 0, itemBottom: 0, sectionBottom: 0 }),
    splashDone: () => false,
    morph: () => morph,
    apply: (v, e) => applied.push({ v, e }),
    after: (ms, cb) => {
      const t = { ms, cb, live: true };
      timers.push(t);
      return () => {
        t.live = false;
      };
    },
    ...over,
  };
  return { env, applied, timers, setHero: (h: typeof hero) => (hero = h), setMorph: (m: number) => (morph = m) };
}

describe('nav driver', () => {
  it('mounts as the hero pill, not ready, and arms the 1140 ms timer', () => {
    const f = fake();
    createNavDriver(f.env).mount();
    expect(f.timers[0]?.ms).toBe(1140);
    expect(f.applied.at(-1)?.v).toMatchObject({ heroPill: true, ready: false });
    expect(f.applied.at(-1)?.e).toEqual({ tabOff: true, ariaHidden: true });
  });
  it('chrome is ready at once under reduced motion', () => {
    const f = fake({ reduced: () => true });
    createNavDriver(f.env).mount();
    expect(f.timers).toHaveLength(0);
    expect(f.applied.at(-1)?.v.ready).toBe(true);
  });
  it('the timer sets ready; a query change sets it earlier and cancels the timer', () => {
    const f = fake();
    const d = createNavDriver(f.env);
    d.mount();
    f.timers[0]!.cb();
    expect(f.applied.at(-1)?.v.ready).toBe(true);
    const g = fake({ narrow: () => false });
    const d2 = createNavDriver(g.env);
    d2.mount();
    (g.env as { narrow: () => boolean }).narrow = () => true;
    d2.queryChanged();
    expect(g.timers[0]?.live).toBe(false);
    expect(g.applied.at(-1)?.v.ready).toBe(true);
  });
  it('measure returns a writer only when past-hero changes, and writes on change only', () => {
    const f = fake();
    const d = createNavDriver(f.env);
    d.mount();
    expect(d.measure()).toBeUndefined();
    f.setHero({ top: -900, height: 2000 }); // 900 / 1200 = 0.75
    const w = d.measure();
    expect(w).toBeTypeOf('function');
    const n = f.applied.length;
    w!();
    expect(f.applied.length).toBe(n + 1);
    expect(f.applied.at(-1)?.v.heroPill).toBe(false);
    expect(d.measure()).toBeUndefined();
  });
  it('the morph turns the pill off and morphing on; a repeated value writes nothing', () => {
    const f = fake();
    const d = createNavDriver(f.env);
    d.mount();
    f.setMorph(0.5);
    d.morphChanged();
    expect(f.applied.at(-1)?.v).toMatchObject({ heroPill: false, morphing: true });
    const n = f.applied.length;
    f.setMorph(0.6);
    d.morphChanged();
    expect(f.applied.length).toBe(n + 1); // earn aria changes at 0.55
    f.setMorph(0.7);
    d.morphChanged();
    expect(f.applied.length).toBe(n + 1);
  });
  it('locale open sets the class flag', () => {
    const f = fake();
    const d = createNavDriver(f.env);
    d.mount();
    d.setLocaleOpen(true);
    expect(f.applied.at(-1)?.v.localeOpen).toBe(true);
  });
});
