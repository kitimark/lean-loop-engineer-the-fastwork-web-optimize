import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as P from './pause';
import { FakeAnim, fakeIO } from '../hero.accent/pause.testutil';

interface Fr {
  d: number;
  vis: boolean;
  rep: boolean;
}

goldenConformance('platform-sweep-pause', {
  const: () => ({ periodMs: P.PERIOD_MS, flag: P.FLAG, variant: P.VARIANT }),
  trace: (i) => {
    let s = P.init(i.off as number);
    return (i.frames as Fr[]).map((f) => {
      const a = P.seek(s, f.rep);
      s = P.tick(a, f.d, f.rep);
      return { loc: a.loc, phase: P.phase({ t: a.loc }), ticks: P.ticks(f.rep), paused: a.paused };
    });
  },
  orig: (i) => P.orig(i.off as number, (i.frames as Fr[]).map((f) => f.d)),
});

describe('platform.sweep offscreen-pause', () => {
  it('reportAction mirrors seek: pause on the first report, resume on the first unreported, else none', () => {
    expect(P.reportAction(false, true)).toBe('pause');
    expect(P.reportAction(true, true)).toBe('none');
    expect(P.reportAction(true, false)).toBe('resume');
    expect(P.reportAction(false, false)).toBe('none');
  });
  it('a reported frame never ticks the animation', () => {
    const s = P.init(5);
    expect(P.step(s, 16, true).loc).toBe(5);
    expect(P.ticks(true)).toBe(0);
  });
});

describe('platform.sweep watchSweepPause pending play', () => {
  const mk = (st: number | null) => {
    const el = { getAnimations: () => [loop] } as unknown as Element;
    const loop = new FakeAnim(st);
    return { el, loop };
  };
  it('leaves an animation whose play is still pending (startTime null) running', () => {
    const { el, loop } = mk(null);
    const { IO, report } = fakeIO();
    P.watchSweepPause([el], IO);
    report(el, true);
    expect(loop.log).toEqual([]);
    expect(loop.playState).toBe('running');
  });
  it('pauses a running animation and resumes it with the saved start time', () => {
    const { el, loop } = mk(123);
    const { IO, report } = fakeIO();
    P.watchSweepPause([el], IO);
    report(el, true);
    report(el, false);
    expect(loop.log).toEqual(['pause', 'play']);
    expect(loop.startTime).toBe(123);
  });
});
