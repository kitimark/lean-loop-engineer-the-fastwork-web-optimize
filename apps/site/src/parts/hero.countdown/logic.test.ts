import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';
import { GOLDEN_ARGS } from './logic';

describe('hero.countdown logic', () => {
  it('TARGET_MS is 2026-11-02T12:00+07:00', () => {
    expect(L.TARGET_MS).toBe(Date.parse('2026-11-02T12:00:00+07:00'));
  });
  it('remainingSeconds ceil, clamp, non-finite', () => {
    expect(L.remainingSeconds(0, 1)).toBe(1);
    expect(L.remainingSeconds(0, 1000)).toBe(1);
    expect(L.remainingSeconds(0, 1001)).toBe(2);
    expect(L.remainingSeconds(5000, 1000)).toBe(0);
    expect(L.remainingSeconds(Number.NaN, 1000)).toBe(0);
    expect(L.remainingSeconds(0, Number.POSITIVE_INFINITY)).toBe(0);
  });
  it('unitsFromSeconds', () => {
    expect(L.unitsFromSeconds(0)).toEqual([0, 0, 0, 0]);
    expect(L.unitsFromSeconds(86400 + 3600 * 2 + 60 * 3 + 4)).toEqual([1, 2, 3, 4]);
    expect(L.unitsFromSeconds(86399)).toEqual([0, 23, 59, 59]);
  });
  it('digitPlaces / digitAt', () => {
    expect(L.digitPlaces(0, false)).toEqual([1]);
    expect(L.digitPlaces(0, true)).toEqual([10, 1]);
    expect(L.digitPlaces(123, true)).toEqual([100, 10, 1]);
    expect(L.digitPlaces(-7.9, true)).toEqual([10, 1]);
    expect(L.digitAt(1234, 100)).toBe(2);
    expect(L.digitAt(-1234.9, 1)).toBe(5);
    expect(L.digitAt(5, 10)).toBe(0);
    expect(L.digitAt(7, 0)).toBe(0); // place 0: Lean gives 0, never NaN
  });
  it('faceDelta is the signed shortest distance', () => {
    expect(L.faceDelta(3, 3)).toBe(0);
    expect(L.faceDelta(9, 0)).toBe(-1);
    expect(L.faceDelta(0, 9)).toBe(1);
    expect(L.faceDelta(5, 0)).toBe(5); // range is (-5, 5]: the half turn is +5
    expect(L.faceDelta(5, 10)).toBe(5);
    expect(L.faceDelta(0, 5)).toBe(5);
    expect(L.faceDelta(6, 0)).toBe(-4);
    expect(L.faceDelta(0, -0.5)).toBeCloseTo(0.5);
    for (let f = 0; f < 10; f++)
      for (const a of [-13.2, 0, 4.4, 9.99, 27.5]) {
        const d = L.faceDelta(f, a);
        expect(d).toBeGreaterThan(-5);
        expect(d).toBeLessThanOrEqual(5);
      }
  });
  it('springStep settles on the target and is exact when done', () => {
    let s = { value: 4, velocity: 0 };
    let done = false;
    for (let i = 0; i < 400 && !done; i++) ({ state: s, done } = L.springStep(s, 3, 16.667));
    expect(done).toBe(true);
    expect(s).toEqual({ value: 3, velocity: 0 });
    const first = L.springStep({ value: 4, velocity: 0 }, 3, 16);
    expect(first.done).toBe(false);
    expect(first.state.value).toBeLessThan(4);
    expect(L.springStep({ value: 3, velocity: 0 }, 3, 0)).toEqual({ state: { value: 3, velocity: 0 }, done: true });
  });
  it('springStep slices 16 ms steps', () => {
    const a = L.springStep({ value: 0, velocity: 0 }, 1, 32).state;
    const b = L.springStep(L.springStep({ value: 0, velocity: 0 }, 1, 16).state, 1, 16).state;
    expect(a.value).toBeCloseTo(b.value, 12);
    expect(a.velocity).toBeCloseTo(b.velocity, 12);
  });
  it('metrics by condition; <=400 wins when both match', () => {
    expect(L.countdownMetrics(false, false)).toMatchObject({ fontPx: 40, cellPx: 52, unitPx: 120 });
    expect(L.countdownMetrics(false, true)).toMatchObject({ fontPx: 28, cellPx: 36, unitPx: 88 });
    expect(L.countdownMetrics(true, true)).toMatchObject({ fontPx: 24, cellPx: 31, unitPx: 74 });
    expect(L.countdownMetrics(true, false)).toEqual(L.countdownMetrics(true, true));
  });
  it('strip equals the faithful faces in the visible window', () => {
    for (const a of [0, 0.3, 4.5, 8.7, 9.99, 10.2, -0.4, -3.1, 23.6]) {
      const m = ((a % 10) + 10) % 10;
      const top = L.stripOffsetCells(a);
      expect(top).toBeCloseTo(-(1 + m));
      for (let j = 0; j < 12; j++) {
        const y = j + top;
        if (Math.abs(y) >= 1) continue;
        expect(L.faceDelta(L.stripEntryDigit(j), a)).toBeCloseTo(y, 9);
      }
    }
  });
  it('ariaLabel joins', () => {
    expect(L.ariaLabel([1, 2, 3, 4], ['a', 'b', 'c', 'd'])).toBe('1 a, 2 b, 3 c, 4 d');
  });
});

goldenConformance('hero.countdown', Object.fromEntries(
  Object.entries(GOLDEN_ARGS).map(([fn, names]) => [
    fn,
    (i: Record<string, unknown>) => (L as unknown as Record<string, (...a: unknown[]) => unknown>)[fn]!(...names.map((k) => i[k])),
  ]),
));
