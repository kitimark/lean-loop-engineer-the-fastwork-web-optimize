import { describe, expect, it } from 'vitest';
import { createOrbitDriver, type StyleTarget } from './driver';
import { PIECES } from './data';
import { place, ringIndex } from './logic';

function target<E extends object>(extra: E = {} as E) {
  const vars = new Map<string, string>();
  const attrs = new Map<string, string>();
  const t = {
    vars,
    attrs,
    style: {
      setProperty: (n: string, v: string) => void vars.set(n, v),
      removeProperty: (n: string) => {
        const old = vars.get(n) ?? '';
        vars.delete(n);
        return old;
      },
    },
    setAttribute: (n: string, v: string) => void attrs.set(n, v),
    removeAttribute: (n: string) => void attrs.delete(n),
    ...extra,
  };
  return t as typeof t & StyleTarget & E;
}

function setup(skip = false, width = 1512) {
  let now = 0;
  const ticks: ((t: number) => void)[] = [];
  const timers: { at: number; cb: () => void }[] = [];
  let rafCount = 0;
  let timerCount = 0;
  const orbit = target({ clientWidth: width });
  const hero = target({ offsetWidth: 0 });
  const cards = PIECES.map(() => target());
  const driver = createOrbitDriver({
    clock: {
      subscribe(tick) {
        ticks.push(tick);
        rafCount++;
        return () => void ticks.splice(ticks.indexOf(tick), 1);
      },
      interval(ms, cb) {
        const t = { at: now + ms, cb };
        timers.push(t);
        timerCount++;
        return () => void timers.splice(timers.indexOf(t), 1);
      },
    },
    orbit,
    hero,
    cards,
    pieces: PIECES,
    ring: ringIndex(PIECES),
    innerWidth: () => width,
    perfNow: () => now,
    skip: () => skip,
  });
  const advance = (to: number) => {
    // one frame per 16 ms, timers fire in order
    for (let t = Math.floor(now / 16) * 16 + 16; t <= to; t += 16) {
      for (const x of [...timers]) if (x.at <= t) x.cb();
      now = t;
      for (const f of [...ticks]) f(t);
    }
  };
  return { driver, orbit, hero, cards, advance, ticks, timers, counts: () => ({ rafCount, timerCount }) };
}

describe('hero.orbit driver (the original p / f / d)', () => {
  it('reset: prep then run, start offsets from the ring, a loop and one 1820 ms timer', () => {
    const s = setup();
    s.driver.reset();
    expect(s.hero.attrs.get('data-splash')).toBe('run');
    const ring = ringIndex(PIECES);
    const p0 = PIECES[0]!;
    const want = place({ left: p0.left, top: p0.top, width: p0.width, height: p0.height, idx: ring[0]!, n: 1512, e: 0, expanded: false });
    expect(s.cards[0]!.vars.get('--orbit-enter-x')).toBe(`${want.x}px`);
    expect(s.cards[0]!.vars.get('--orbit-start-rot')).toBe(`${want.rotTenths / 10}deg`);
    expect(s.counts()).toEqual({ rafCount: 1, timerCount: 1 });
  });
  it('expands at 1164 ms and ends at 1820 ms with the loop cancelled and the blur variable removed', () => {
    const s = setup();
    s.driver.reset();
    s.advance(1100);
    expect(s.orbit.attrs.has('data-expand')).toBe(false);
    expect(s.orbit.vars.has('--ring-motion-blur')).toBe(true);
    s.advance(1180);
    expect(s.orbit.attrs.has('data-expand')).toBe(true);
    expect(s.orbit.attrs.has('data-done')).toBe(false);
    s.advance(1840);
    expect(s.orbit.attrs.has('data-done')).toBe(true);
    expect(s.hero.attrs.get('data-splash')).toBe('done');
    expect(s.orbit.vars.has('--ring-motion-blur')).toBe(false);
    expect(s.ticks.length).toBe(0);
    expect(s.timers.length).toBe(0);
  });
  it('skip (reduced motion or width <= 600): done at once, no loop, no timer', () => {
    const s = setup(true);
    s.driver.reset();
    expect(s.hero.attrs.get('data-splash')).toBe('done');
    expect(s.orbit.attrs.has('data-done')).toBe(true);
    expect(s.counts()).toEqual({ rafCount: 0, timerCount: 0 });
  });
  it('a restart (pageshow persisted) clears the flags and starts again', () => {
    const s = setup();
    s.driver.reset();
    s.advance(1900);
    s.driver.reset();
    expect(s.orbit.attrs.has('data-done')).toBe(false);
    expect(s.orbit.attrs.has('data-expand')).toBe(false);
    expect(s.hero.attrs.get('data-splash')).toBe('run');
    expect(s.ticks.length).toBe(1);
    expect(s.timers.length).toBe(1);
  });
  it('writes 3 variables per card per frame plus the blur', () => {
    const s = setup();
    s.driver.reset();
    let writes = 0;
    for (const c of s.cards) {
      const orig = c.style.setProperty;
      c.style.setProperty = (n: string, v: string) => {
        writes++;
        orig(n, v);
      };
    }
    s.advance(48);
    expect(writes).toBe(3 * 10 * 3);
  });
});
