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

class Pend extends FakeAnim {
  private done: (() => void) | null = null;
  readonly ready: Promise<unknown>;
  constructor(st: number | null) {
    super(st);
    this.ready = new Promise<void>((r) => {
      this.done = r;
    });
  }
  settle(t: number) {
    this.startTime = t;
    this.done?.();
  }
}

const mkEl = (list: () => FakeAnim[]) => {
  const ls = new Map<string, () => void>();
  const el = {
    getAnimations: list,
    addEventListener: (n: string, f: () => void) => ls.set(n, f),
    removeEventListener: (n: string) => ls.delete(n),
  } as unknown as Element;
  return { el, fire: (n: string) => ls.get(n)?.(), ls };
};

describe('platform.sweep watchSweepPause', () => {
  it('a pending play stays running until its start time exists, then pauses and resumes at the saved time', async () => {
    const loop = new Pend(null);
    const { el } = mkEl(() => [loop]);
    const { IO, report } = fakeIO();
    P.watchSweepPause([el], IO);
    report(el, true);
    expect(loop.log).toEqual([]);
    loop.settle(50);
    await Promise.resolve();
    await Promise.resolve();
    expect(loop.log).toEqual(['pause']);
    report(el, false);
    expect(loop.log).toEqual(['pause', 'play']);
    expect(loop.startTime).toBe(50);
  });
  it('a pending play that becomes ready after the element is visible again stays running', async () => {
    const loop = new Pend(null);
    const { el } = mkEl(() => [loop]);
    const { IO, report } = fakeIO();
    P.watchSweepPause([el], IO);
    report(el, true);
    report(el, false);
    loop.settle(50);
    await Promise.resolve();
    await Promise.resolve();
    expect(loop.log).toEqual([]);
  });
  it('an animation created after the first hidden report is paused when it starts (the old snapshot missed it)', () => {
    const late = new FakeAnim(77);
    let made = false;
    const { el, fire } = mkEl(() => (made ? [late] : []));
    const { IO, report } = fakeIO();
    P.watchSweepPause([el], IO);
    report(el, true);
    made = true;
    fire('animationstart');
    expect(late.log).toEqual(['pause']);
    report(el, false);
    expect(late.log).toEqual(['pause', 'play']);
    expect(late.startTime).toBe(77);
  });
  it('a new animation is not touched while the element is visible', () => {
    const late = new FakeAnim(77);
    const { el, fire } = mkEl(() => [late]);
    const { IO } = fakeIO();
    P.watchSweepPause([el], IO);
    fire('animationstart');
    expect(late.log).toEqual([]);
  });
  it('pauses a running animation, resumes it with the saved start time, and the stop function detaches the listener', () => {
    const loop = new FakeAnim(123);
    const { el, ls } = mkEl(() => [loop]);
    const { IO, report } = fakeIO();
    const stop = P.watchSweepPause([el], IO);
    report(el, true);
    report(el, false);
    expect(loop.log).toEqual(['pause', 'play']);
    expect(loop.startTime).toBe(123);
    stop();
    expect(ls.size).toBe(0);
  });
});
