import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('platform.glint', {
  sample: (i) => L.sample({ side: i.side as L.Side, elapsed: i.elapsed as number }),
  step: (i) => L.step({ state: i.state as L.St, now: i.now as number, event: i.event as L.Ev }),
  view: (i) => L.view({ state: i.state as L.St, side: i.side as L.Side, now: i.now as number }),
  const: () => ({ durMs: L.DUR_MS, startDelayMs: L.START_DELAY_MS, minRatio: L.MIN_RATIO }),
});

describe('platform.glint logic', () => {
  it('becoming visible arms a 1 s timer and the timer starts the animation', () => {
    const a = L.step({ state: L.init(false), now: 0, event: { kind: 'ratio', ratio: 0.4 } });
    expect(a.timer).toBe(1000);
    const b = L.step({ state: a, now: 999, event: { kind: 'fire' } });
    expect(b.v).toBe(false);
    const c = L.step({ state: a, now: 1000, event: { kind: 'fire' } });
    expect(c).toMatchObject({ v: true, t0: 1000, timer: null });
  });
  it('reduced motion never plays', () => {
    const a = L.step({ state: L.init(true), now: 0, event: { kind: 'ratio', ratio: 0.6 } });
    expect(a.timer).toBeNull();
    expect(L.step({ state: a, now: 5000, event: { kind: 'fire' } }).v).toBe(false);
  });
});
