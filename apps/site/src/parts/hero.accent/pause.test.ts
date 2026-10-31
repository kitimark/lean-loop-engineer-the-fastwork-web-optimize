import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as P from './pause';
import { FakeAnim, fakeIO } from './pause.testutil';

interface Fr {
  d: number;
  vis: boolean;
  rep: boolean;
}

const look = (t: number) => [P.shown(0, t), P.shown(1, t), P.shown(2, t)];

goldenConformance('hero-accent-pause', {
  const: () => ({ cycleMs: 600, flag: P.FLAG, variant: P.VARIANT }),
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

describe('hero.accent offscreen-pause', () => {
  it('shown mirrors the step-end plateaus of the three boxes', () => {
    expect(look(0)).toEqual([1, 0, 0]);
    expect(look(300)).toEqual([0, 1, 0]);
    expect(look(500)).toEqual([0, 0, 1]);
    expect(look(1100)).toEqual([0, 0, 1]);
  });
  it('pauses the running loops on a hidden report and resumes them with the saved start time', () => {
    const el = {} as Element;
    const loop = new FakeAnim(123);
    const { IO, report } = fakeIO();
    const stop = P.watchLoopPause([el], () => [loop] as unknown as Animation[], IO);
    report(el, true);
    expect(loop.log).toEqual(['pause']);
    report(el, true);
    expect(loop.log).toEqual(['pause']);
    report(el, false);
    expect(loop.log).toEqual(['pause', 'play']);
    expect(loop.startTime).toBe(123);
    stop();
  });
  it('leaves a loop the page cancelled while paused alone', () => {
    const el = {} as Element;
    const loop = new FakeAnim(7);
    const { IO, report } = fakeIO();
    P.watchLoopPause([el], () => [loop] as unknown as Animation[], IO);
    report(el, true);
    loop.playState = 'idle';
    report(el, false);
    expect(loop.log).toEqual(['pause']);
  });
  it('the cleanup resumes what is still paused', () => {
    const el = {} as Element;
    const loop = new FakeAnim(42);
    const { IO, report } = fakeIO();
    const stop = P.watchLoopPause([el], () => [loop] as unknown as Animation[], IO);
    report(el, true);
    stop();
    expect(loop.startTime).toBe(42);
    expect(loop.playState).toBe('running');
  });
  it('isLoop reads the iteration count: finite draw animations are not loops', () => {
    expect(P.isLoop(new FakeAnim(0, true) as unknown as Animation)).toBe(true);
    expect(P.isLoop(new FakeAnim(0, false) as unknown as Animation)).toBe(false);
  });
  it('loopsOf asks for the subtree and keeps the infinite ones', () => {
    const loop = new FakeAnim(1);
    const once = new FakeAnim(2, false);
    let opts: unknown;
    const el = { getAnimations: (o: unknown) => ((opts = o), [loop, once]) } as unknown as Element;
    expect(P.loopsOf(el)).toEqual([loop]);
    expect(opts).toEqual({ subtree: true });
  });
});
