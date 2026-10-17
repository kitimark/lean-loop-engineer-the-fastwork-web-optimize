import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as logic from './logic';

goldenConformance('commission', {
  smooth: (i) => logic.smooth(i.x),
  enterRaw: (i) => logic.enterRaw(i.top, i.h),
  exitRaw: (i) => logic.exitRaw(i.bottom, i.h),
  target: (i) => logic.target(i.reduced, i.x),
  frame: (i) => logic.frame({ n: i.n, r: i.r }, i.top, i.bottom, i.h, i.reduced, i.compact),
  compact: (i) => logic.compact(i.width, i.deviceWidth, i.touch),
  titleWrapped: (i) => logic.titleWrapped(i.compact, i.rects),
  ulFire: (i) => logic.ulFire(i.isIntersecting, i.ratio),
  ulStart: (i) => logic.ulStart(i.reduced),
  sceneActive: (i) => logic.sceneActive(i.top, i.bottom, i.h),
});

describe('commission constants (restated from the original)', () => {
  it('bands, gain and snap', () => {
    expect(logic.GAIN).toBe(0.22);
    expect(logic.EPS).toBe(8e-4);
    expect(logic.UL_DELAY).toBe(900);
  });
  it('the underline timer settles on idle', () => {
    expect(logic.ulTimer(logic.ulStart(false))).toBe('idle');
    expect(logic.ulTimer('idle')).toBe('idle');
  });
});
