import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { FakeAnim, fakeIO } from '../hero.accent/pause.testutil';
import * as P from './pause';

interface Fr {
  d: number;
  vis: boolean;
  rep: boolean;
}

const look = (t: number) => P.cueY((p) => p, t);

goldenConformance('hero-cue-pause', {
  const: () => ({ cycleMs: P.CYCLE_MS_CUE, flag: P.FLAG, variant: P.VARIANT }),
  trace: (i) => {
    let s = P.init(i.off as number);
    return (i.frames as Fr[]).map((f) => {
      const a = P.seek(s, f.rep);
      s = P.tick(a, f.d, f.rep);
      return { loc: a.loc, look: look(a.loc), ticks: P.ticks(f.rep), paused: a.paused };
    });
  },
  orig: (i) => {
    const loc = P.orig(i.off as number, (i.frames as Fr[]).map((f) => f.d));
    return { loc, look: look(loc) };
  },
});

describe('hero.cue offscreen-pause', () => {
  it('cueY runs 0, -8, 0 over the 2.2 s cycle', () => {
    expect(look(0) + 0).toBe(0);
    expect(look(1100)).toBe(-8);
    expect(look(2200) + 0).toBe(0);
    expect(look(550)).toBe(-4);
  });
  it('pauses the float loop off screen and restores its start time on return', () => {
    const el = {} as Element;
    const loop = new FakeAnim(55);
    const { IO, report } = fakeIO();
    const stop = P.watchLoopPause([el], () => [loop] as unknown as Animation[], IO);
    report(el, true);
    expect(loop.playState).toBe('paused');
    report(el, false);
    expect(loop.playState).toBe('running');
    expect(loop.startTime).toBe(55);
    stop();
  });
});
