import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { attached, blocking, createArm, edge, inBand, isArmLate, mode, ops, type ArmEnv, type ListenType } from './armLate';

type Step = { near: boolean; bottom: number; active: boolean };

function recorder() {
  const log: string[] = [];
  const env: ArmEnv = {
    add: (type: ListenType, _fn, passive) => log.push(`+${type}:${type === 'touchstart' ? 'x' : passive ? 'passive' : 'blocking'}`),
    remove: (type: ListenType) => log.push(`-${type}`),
  };
  return { log, env };
}

const handlers = { touchstart: () => {}, wheel: () => {}, touchmove: () => {} };

goldenConformance('morph-mount-arm-late', {
  edge: (i) => edge(i.vh),
  inBand: (i) => inBand(i.vh, i.bottom),
  attached: (i) => attached(i.near, i.active),
  blocking: (i) => blocking(i.near, i.band, i.active),
  mode: (i) => mode(i.near, i.band, i.active),
  ops: (i) => ops(i.cur, i.next),
  run: (i) => {
    const { log, env } = recorder();
    const arm = createArm(env, handlers);
    return (i.steps as Step[]).map((s) => {
      log.length = 0;
      arm.set(s.near, inBand(i.vh, s.bottom), s.active);
      // touchstart is always passive: the golden names it by its sign only
      return { mode: arm.mode(), ops: log.map((o) => o.replace('touchstart:x', 'touchstart')) };
    });
  },
});

describe('arm-late', () => {
  it('names its variant', () => {
    expect(isArmLate('arm-late')).toBe(true);
    expect(isArmLate('band')).toBe(false);
  });

  it('never registers a listener the original does not have, and is passive outside the band while idle', () => {
    for (const near of [false, true])
      for (const band of [false, true])
        for (const act of [false, true]) {
          const m = mode(near, band, act);
          expect(m === 'none').toBe(!attached(near, act));
          if (m === 'blocking') expect(attached(near, act)).toBe(true);
          if (!band && !act) expect(m).not.toBe('blocking');
        }
  });

  // Listener-armed frames per zone on one scroll sweep (deterministic replay, not a browser measurement): the platform
  // bottom runs from far below to far above the viewport in 16 px steps; `near` is the 200 % observer.
  it('arms fewer non-passive frames than the original on a full sweep', () => {
    const vh = 800;
    const height = 900;
    const frames = { far: 0, approach: 0, band: 0, past: 0 };
    const orig = { far: 0, approach: 0, band: 0, past: 0 };
    for (let bottom = 9000; bottom >= -2600; bottom -= 16) {
      const top = bottom - height;
      const near = top < vh + 2 * vh && bottom > -2 * vh;
      const band = inBand(vh, bottom);
      const zone = !near ? 'far' : bottom > edge(vh) ? 'approach' : bottom > vh + 8 ? 'band' : 'past';
      if (blocking(near, band, false)) frames[zone]++;
      if (attached(near, false)) orig[zone]++;
    }
    expect(frames.far).toBe(0);
    expect(orig.far).toBe(0);
    expect(frames.approach).toBe(0);
    expect(orig.approach).toBeGreaterThan(0);
    expect(frames.band).toBe(orig.band);
    expect(frames.past).toBe(orig.past);
    expect(orig).toEqual({ far: 0, approach: 93, band: 62, past: 151 });
    expect(frames).toEqual({ far: 0, approach: 0, band: 62, past: 151 });
  });
});
