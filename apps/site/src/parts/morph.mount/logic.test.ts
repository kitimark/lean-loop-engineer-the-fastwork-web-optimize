import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as logic from './logic';

goldenConformance('morph.mount', {
  armed: (i) => logic.armed({ height: i.height, bottom: i.bottom }, i.vh),
  active: (i) => logic.active(i.target, i.value),
  takes: (i) => logic.takes(i.active, i.delta, i.geom),
  touchDelta: (i) => logic.touchDelta(i.prev, i.cur),
  viewportHeight: (i) => logic.viewportHeight(i.visual, i.inner),
  wanted: (i) => logic.wanted(i.near, i.active),
  action: (i) => logic.action(i.attached, i.wanted),
  mountNext: (i) => logic.mountNext(i.mounted, i.intersecting, i.pushed),
  repin: (i) => logic.repin(i.active, i.y, i.pin),
});

describe('variant shift (Lean MorphMountOpt.mountV)', () => {
  it('warm counts as an intersecting entry; monotone', () => {
    expect(logic.mountNextWarm(false, false, false, true)).toBe(true);
    expect(logic.mountNextWarm(false, false, false, false)).toBe(false);
    expect(logic.mountNextWarm(true, false, false, false)).toBe(true);
    for (const m of [false, true])
      for (const n of [false, true])
        for (const p of [false, true]) if (logic.mountNext(m, n, p)) expect(logic.mountNextWarm(m, n, p, false)).toBe(true);
  });
  it('still means idle morph and a quiet gap', () => {
    expect(logic.warmStill(false, logic.WARM_QUIET_MS)).toBe(true);
    expect(logic.warmStill(true, 1e6)).toBe(false);
    expect(logic.warmStill(false, logic.WARM_QUIET_MS - 1)).toBe(false);
    // boundary: exactly 150 ms is still
    expect(logic.WARM_QUIET_MS).toBe(150);
    expect(logic.warmStill(false, 150)).toBe(true);
    expect(logic.warmStill(false, 149.999)).toBe(false);
  });
});

describe('morph.mount constants (restated from the original)', () => {
  it('observer margin and arm thresholds', () => {
    expect(logic.IO_ROOT_MARGIN).toBe('200% 0px');
    expect(logic.ARM_MIN_FRACTION).toBe(0.45);
    expect(logic.ARM_BOTTOM_SLACK).toBe(8);
  });
  it('a push when idle needs forward and geometry', () => {
    expect(logic.takes(false, 1, false)).toBe(false);
    expect(logic.takes(false, -1, true)).toBe(false);
    expect(logic.takes(false, 1, true)).toBe(true);
    expect(logic.takes(true, -1, false)).toBe(true);
  });
});
