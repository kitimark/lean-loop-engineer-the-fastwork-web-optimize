import { describe, expect, it } from 'vitest';
import { remainingSeconds, TARGET_MS } from './logic';
import { delayToAim, nextAim, startAligned } from './aligned';

describe('hero.countdown clock-aligned timer (ledger n=8)', () => {
  it('nextAim is on the T0 grid and strictly after now', () => {
    for (const t0 of [0, 17.3, 5000])
      for (let now = t0; now < t0 + 9000; now += 123.7) {
        const a = nextAim(t0, now);
        expect(a).toBeGreaterThan(now);
        expect(a - now).toBeLessThanOrEqual(1000);
        expect((a - t0) % 1000).toBeCloseTo(0, 6);
        expect(delayToAim(t0, now)).toBeGreaterThan(0);
      }
  });
  it('a late timer does not drift: ticks land on T0 + k * 1000 and every second is shown (vs drift_skips)', () => {
    // virtual world: each timeout fires `lag` ms late
    const lag = 7;
    let now = 1000;
    const pending: { at: number; cb: () => void }[] = [];
    const shown: number[] = [];
    const stop = startAligned({
      clock: {
        interval: (ms, cb) => {
          const e = { at: now + ms + lag, cb };
          pending.push(e);
          return () => void pending.splice(pending.indexOf(e), 1);
        },
      },
      now: () => now,
      refresh: () => shown.push(remainingSeconds(now, TARGET_MS)),
    });
    for (let i = 0; i < 400; i += 1) {
      const e = pending.shift()!;
      now = e.at;
      e.cb();
    }
    stop();
    for (let i = 1; i < shown.length; i += 1) expect(shown[i - 1]! - shown[i]!).toBe(1);
    expect(pending.length).toBe(0);
  });
  it('the drifting interval of the same world skips a second (the Lean counterexample, restated)', () => {
    let now = 1000;
    const shown = [remainingSeconds(now, TARGET_MS)];
    for (let i = 0; i < 400; i += 1) {
      now += 1000 + 7;
      shown.push(remainingSeconds(now, TARGET_MS));
    }
    expect(shown.some((s, i) => i > 0 && shown[i - 1]! - s === 2)).toBe(true);
  });
  it('cleanup cancels the pending timeout', () => {
    let live = 0;
    const stop = startAligned({
      clock: {
        interval: () => {
          live += 1;
          return () => void (live -= 1);
        },
      },
      now: () => 0,
      refresh: () => {},
    });
    expect(live).toBe(1);
    stop();
    expect(live).toBe(0);
  });
});
