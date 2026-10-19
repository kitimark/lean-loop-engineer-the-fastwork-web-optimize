import { describe, expect, it } from 'vitest';
import type { MotionClock } from '../../engine/clock';
import { createCardDriver, type CardEnv } from './driver';

/** Variant `mq` (Lean PeopleCardOpt `stepV`, `gate_leE`): in the c860 band no `--future-shrink` write, no re-request. */
function rig(gate: boolean | undefined) {
  const writes: string[] = [];
  let pending: (() => void) | null = null;
  let requests = 0;
  const clock = {
    subscribe: (cb: () => void) => {
      requests += 1;
      pending = cb;
      return () => {
        pending = null;
      };
    },
  } as unknown as MotionClock;
  const env: CardEnv = {
    reduced: () => false,
    narrow: () => false,
    vh: () => 900,
    track: () => ({ top: -1500, height: 1800 }),
    cardBottom: () => 200,
    headerTop: () => 500,
    painPresent: () => true,
    write: {
      revealed: (on) => writes.push(`revealed ${on}`),
      shrink: (v) => writes.push(`shrink ${v.toFixed(3)}`),
      shrinking: (on) => writes.push(`cls ${on}`),
      painDark: (on) => writes.push(`dark ${on}`),
    },
  };
  const d = createCardDriver(env, clock, gate === undefined ? {} : { gate: () => gate });
  return { d, writes, requests: () => requests, run: () => pending?.() };
}

describe('people.card variant mq', () => {
  it('outside the band it is the faithful driver: shrink written, frames re-requested until the lerp settles', () => {
    const f = rig(false);
    const g = rig(undefined);
    f.d.runNow();
    g.d.runNow();
    for (let i = 0; i < 100; i += 1) {
      f.run();
      g.run();
    }
    expect(f.writes).toEqual(g.writes);
    expect(f.writes.some((w) => w.startsWith('shrink'))).toBe(true);
    expect(f.d.shrink).toBe(g.d.shrink);
  });
  it('in the band: no shrink write, no re-request, the class and the other writes unchanged', () => {
    const f = rig(true);
    const g = rig(undefined);
    f.d.runNow();
    g.d.runNow();
    expect(f.writes.some((w) => w.startsWith('shrink'))).toBe(false);
    expect(f.requests()).toBe(0);
    expect(g.requests()).toBe(1);
    expect(f.writes.filter((w) => !w.startsWith('shrink'))).toEqual(g.writes.filter((w) => !w.startsWith('shrink')));
    expect(f.d.shrink).toBe(0);
  });
});
