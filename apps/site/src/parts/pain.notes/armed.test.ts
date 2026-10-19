import { describe, expect, it } from 'vitest';
import { armed, resumeAt, tickAt, ticksIn } from './armed';

describe('pain.notes variant visible (Lean PainNotesOpt)', () => {
  it('armed: in view, not narrow, not covered (all 8 contexts, wide_armed_iff)', () => {
    for (const inView of [false, true])
      for (const narrow of [false, true])
        for (const covered of [false, true]) expect(armed({ inView, narrow, covered })).toBe(inView && !narrow && !covered);
  });
  it('resumeAt restates the #guard rows', () => {
    expect(resumeAt(0, 4000)).toBe(6000);
    expect(resumeAt(0, 6000)).toBe(6000);
    expect(resumeAt(0, 6001)).toBe(9000);
    expect(resumeAt(0, 0)).toBe(3000);
    expect(resumeAt(500, 100)).toBe(3500);
    expect(resumeAt(0, 3000)).toBe(3000);
    expect(resumeAt(1000, 4001)).toBe(7000);
  });
  it('resumeAt_on_grid and resumeAt_least over a sweep', () => {
    for (const t0 of [0, 1, 500, 2999, 12345])
      for (let now = 0; now < 20000; now += 137) {
        const r = resumeAt(t0, now);
        expect((r - t0) % 3000).toBe(0);
        expect(r).toBeGreaterThanOrEqual(now);
        expect(r).toBeGreaterThan(t0);
        expect(r - 3000 < now || r === tickAt(t0, 0)).toBe(true);
      }
  });
  it('naive_rearm_shifts: a fresh period at 4000 misses the 6000 tick; resumeAt keeps it', () => {
    expect(ticksIn(0, 4000, 6500)).toBe(1);
    expect(ticksIn(4000, 4000, 6500)).toBe(0);
    expect(resumeAt(0, 4000)).toBe(6000);
  });
});
