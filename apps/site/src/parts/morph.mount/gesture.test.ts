import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { armed } from './logic';
import { FIRST, gestureOpt, isOverscrollLock, lockOp, lockWanted, ONCE, step, type Gesture, type GestureOpt } from './gesture';

const opt = (n: string): GestureOpt => (n === 'orig' ? { first: false, once: false } : n === 'touch-first' ? FIRST : ONCE);

type Move = { active: boolean; delta: number; geom: boolean; cancelable: boolean };

goldenConformance('morph-mount-toolbar', {
  step: (i) => {
    const r = step(opt(i.opt), i.g as Gesture, i.active, i.delta, i.geom, i.cancelable);
    return { take: r.take, next: r.next };
  },
  run: (i) => {
    let g: Gesture = 'fresh';
    let opens = 0;
    const out = (i.steps as Move[]).map((m) => {
      const r = step(opt(i.opt), g, m.active, m.delta, m.geom, m.cancelable);
      if (!m.active && r.take) opens++;
      g = r.next;
      return { take: r.take, next: r.next };
    });
    return { out, opens };
  },
  armPair: (i) => ({
    small: armed({ height: i.height, bottom: i.bottom }, i.vh),
    large: armed({ height: i.height, bottom: i.bottom }, i.vh + i.toolbar),
  }),
  lockWanted: (i) => lockWanted(i.near, i.geom, i.active),
  lockOp: (i) => lockOp(i.cur, i.want),
});

describe('gesture', () => {
  it('names its variants', () => {
    expect(gestureOpt('touch-first')).toEqual(FIRST);
    expect(gestureOpt('open-once')).toEqual(ONCE);
    expect(gestureOpt('faithful')).toBeUndefined();
    expect(isOverscrollLock('overscroll-lock')).toBe(true);
  });

  it('never starts a push in a native gesture, and never takes more than the original', () => {
    for (const o of [FIRST, ONCE])
      for (const g of ['fresh', 'native', 'pushing', 'spent'] as Gesture[])
        for (const act of [false, true])
          for (const d of [-1, 1])
            for (const geom of [false, true])
              for (const c of [false, true]) {
                const t = step(o, g, act, d, geom, c).take;
                if (t) expect(act || (d > 0 && geom)).toBe(true);
                if (g === 'native' && !act) expect(t).toBe(false);
                if (act) expect(t).toBe(true);
              }
  });
});
