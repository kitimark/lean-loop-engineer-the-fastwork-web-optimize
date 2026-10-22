import { describe, expect, it } from 'vitest';
import { createRafClock, type ClockEnv } from '../../engine/clock';
import { rafRegistrationsPerFrame, timerRegistrations } from '../../engine/clock.logic';
import { createCountdownDriver, startFaithful, type DigitHandle, type Writable } from './driver';
import { digitAt, remainingSeconds, springStep, unitsFromSeconds } from './logic';

const TARGET = Date.parse('2026-11-02T12:00:00+07:00');
const node = (): Writable => ({ style: { transform: '' } });

const mkEnv = () => {
  const raf = new Map<number, (t: number) => void>();
  const timers = new Map<number, () => void>();
  let id = 0;
  const env: ClockEnv = {
    raf: (cb) => (raf.set(++id, cb), id),
    caf: (h) => void raf.delete(h),
    setInterval: (cb) => (timers.set(++id, cb), id),
    clearInterval: (h) => void timers.delete(h as number),
  };
  const frame = (t: number) => {
    const cbs = [...raf.values()];
    raf.clear();
    cbs.forEach((cb) => cb(t));
  };
  return { env, raf, timers, frame };
};
const digits = (n: number): DigitHandle[] =>
  Array.from({ length: n }, (_, k) => ({ unit: 3, place: 10 ** (n - k - 1), nodes: Array.from({ length: 10 }, node) }));

const original = (env: ClockEnv, nowRef: { v: number }, n: number, perf: () => number) => {
  const target = Array.from({ length: n }, () => -1);
  const chain = Array.from({ length: n }, () => 0);
  const spring = Array.from({ length: n }, () => ({ value: 0, velocity: 0 }));
  const last = Array.from({ length: n }, () => 0);
  const refresh = () => {
    const u = unitsFromSeconds(remainingSeconds(nowRef.v));
    for (let i = 0; i < n; i++) {
      const t = digitAt(u[3], 10 ** (n - i - 1));
      if (t === target[i]) continue;
      const first = target[i] === -1;
      target[i] = t;
      if (chain[i]) env.caf(chain[i]!);
      spring[i] = first ? { value: t, velocity: 0 } : { value: spring[i]!.value, velocity: 0 };
      const loop = (now: number) => {
        const r = springStep(spring[i]!, t, now - last[i]!);
        last[i] = now;
        spring[i] = r.state;
        chain[i] = r.done ? 0 : env.raf(loop);
      };
      last[i] = perf();
      chain[i] = env.raf(loop);
    }
  };
  refresh();
  env.setInterval(refresh, 1000);
};

const clk = { t: 0 };
const counts = (e: ReturnType<typeof mkEnv>) => ({ raf: e.raf.size, timers: e.timers.size });

describe('faithful scheduling counts vs the original structure', () => {
  it('same timers and same rAF registrations per frame, from mount to settle', () => {
    const N = 2;
    const nowA = { v: TARGET - 15000 };
    const nowB = { v: TARGET - 15000 };
    const a = mkEnv();
    const b = mkEnv();
    const driver = createCountdownDriver({ variant: 'faithful', digits: digits(N), dateNow: () => nowA.v, reduced: () => false });
    startFaithful({ clock: createRafClock(a.env), driver, perfNow: () => clk.t });
    original(b.env, nowB, N, () => clk.t);
    expect(counts(a)).toEqual(counts(b));
    expect(counts(a)).toEqual({ raf: N, timers: 1 });
    expect(rafRegistrationsPerFrame(0, N)).toBe(N);
    expect(timerRegistrations(1)).toBe(1);

    let t = 0;
    for (let f = 0; f < 3; f++) {
      a.frame((t = clk.t = t + 16));
      b.frame(t);
      expect(a.raf.size).toBe(b.raf.size);
    }
    expect(counts(a)).toEqual({ raf: 0, timers: 1 });


    nowA.v += 1000;
    nowB.v += 1000;
    a.timers.forEach((cb) => cb());
    b.timers.forEach((cb) => cb());
    expect(counts(a)).toEqual(counts(b));
    expect(a.raf.size).toBe(1);
    for (let f = 0; f < 200 && (a.raf.size || b.raf.size); f++) {
      a.frame((t = clk.t = t + 16.667));
      b.frame(t);
      expect(a.raf.size).toBe(b.raf.size);
    }
    expect(a.raf.size).toBe(0);
    expect(a.timers.size).toBe(1);
  });

  it('a tens carry restarts two chains in both', () => {
    const nowA = { v: TARGET - 20000 };
    const nowB = { v: TARGET - 20000 };
    const a = mkEnv();
    const b = mkEnv();
    const driver = createCountdownDriver({ variant: 'faithful', digits: digits(2), dateNow: () => nowA.v, reduced: () => false });
    startFaithful({ clock: createRafClock(a.env), driver, perfNow: () => clk.t });
    original(b.env, nowB, 2, () => clk.t);
    clk.t = 16;
    a.frame(16);
    b.frame(16);
    nowA.v += 1000;
    nowB.v += 1000;
    a.timers.forEach((cb) => cb());
    b.timers.forEach((cb) => cb());
    expect(a.raf.size).toBe(2);
    expect(b.raf.size).toBe(2);
  });

  it('strip runs the faithful scheduling: no rAF callback in a still frame, same registrations as the original', () => {
    const nowA = { v: TARGET - 15000 };
    const nowB = { v: TARGET - 15000 };
    const a = mkEnv();
    const b = mkEnv();
    const strips = Array.from({ length: 2 }, (_, k) => ({ unit: 3, place: 10 ** (1 - k), nodes: [node()] }));
    const driver = createCountdownDriver({ variant: 'strip', digits: strips, dateNow: () => nowA.v, reduced: () => false });
    driver.setCell(0, 38);
    driver.setCell(1, 38);
    startFaithful({ clock: createRafClock(a.env), driver, perfNow: () => clk.t });
    original(b.env, nowB, 2, () => clk.t);
    expect(counts(a)).toEqual(counts(b));
    let t = 0;
    for (let f = 0; f < 3; f++) {
      a.frame((t = clk.t = t + 16));
      b.frame(t);
      expect(a.raf.size).toBe(b.raf.size);
    }
    expect(counts(a)).toEqual({ raf: 0, timers: 1 });
    nowA.v += 1000;
    nowB.v += 1000;
    a.timers.forEach((cb) => cb());
    b.timers.forEach((cb) => cb());
    expect(a.raf.size).toBe(1);
    const before = strips[1]!.nodes[0]!.style.transform;
    for (let f = 0; f < 200 && (a.raf.size || b.raf.size); f++) {
      a.frame((t = clk.t = t + 16.667));
      b.frame(t);
      expect(a.raf.size).toBe(b.raf.size);
    }
    expect(counts(a)).toEqual({ raf: 0, timers: 1 });
    expect(strips[1]!.nodes[0]!.style.transform).not.toBe(before);
  });

  it('cleanup cancels the interval and every chain', () => {
    const e = mkEnv();
    const nowRef = { v: TARGET - 5000 };
    const driver = createCountdownDriver({ variant: 'faithful', digits: digits(2), dateNow: () => nowRef.v, reduced: () => false });
    const stop = startFaithful({ clock: createRafClock(e.env), driver, perfNow: () => clk.t });
    stop();
    expect(counts(e)).toEqual({ raf: 0, timers: 0 });
  });
});
