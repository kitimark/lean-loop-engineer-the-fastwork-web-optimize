import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

const st = (o: Record<string, unknown>) => o as unknown as L.St;

goldenConformance('morph.tween', {
  ease: (i) => L.ease({ x: i.x as number }),
  tween: (i) => L.tween({ from: i.from as number, to: i.to as number, elapsed: i.elapsed as number }),
  dir: (i) => L.dir({ delta: i.delta as number }),
  armed: (i) => L.armed({ rectHeight: i.rectHeight as number, rectBottom: i.rectBottom as number, viewportHeight: i.viewportHeight as number }),
  taken: (i) => L.taken({ active: i.active as boolean, delta: i.delta as number, armed: i.armed as boolean }),
  active: (i) => L.active({ target: i.target as number, value: i.value as number }),
  fade: (i) => L.fade({ m: i.m as number }),
  pointerNone: (i) => L.pointerNone({ m: i.m as number }),
  push: (i) => L.push({ state: st(i.state), goal: i.goal as number, reduced: i.reduced as boolean, now: i.now as number }),
  frame: (i) => L.frame({ state: st(i.state), now: i.now as number }),
});

describe('morph.tween logic', () => {
  it('the curve is the ease-out cubic over 680 ms', () => {
    expect(L.DURATION_MS).toBe(680);
    expect(L.tween({ from: 0, to: 1, elapsed: 340 }).value).toBeCloseTo(0.875, 12);
    expect(L.tween({ from: 0, to: 1, elapsed: 679.99 }).done).toBe(false);
    expect(L.tween({ from: 0, to: 1, elapsed: 680 })).toEqual({ value: 1, done: true });
  });
  it('thresholds are strict where the original is', () => {
    expect(L.dir({ delta: 0.99 })).toBeNull();
    expect(L.dir({ delta: -1 })).toBe(0);
    expect(L.active({ target: 0.001, value: 0.001 })).toBe(false);
    expect(L.armed({ rectHeight: 360, rectBottom: 808, viewportHeight: 800 })).toBe(true);
    expect(L.pointerNone({ m: 0.5225 })).toBe(false);
  });
  it('a reversal restarts from the current value with the full duration', () => {
    const open = L.push({ state: L.REST, goal: 1, reduced: false, now: 0 });
    const mid = L.frame({ state: open, now: 100 });
    const back = L.push({ state: mid, goal: 0, reduced: false, now: 100 });
    expect(L.frame({ state: back, now: 100 }).value).toBe(mid.value);
    expect(L.frame({ state: back, now: 779 }).pending).toBe(true);
    expect(L.frame({ state: back, now: 780 })).toMatchObject({ value: 0, pending: false });
  });
});
