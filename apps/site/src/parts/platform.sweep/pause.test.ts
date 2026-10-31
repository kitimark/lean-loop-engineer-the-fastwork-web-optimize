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

class Timed extends FakeAnim {
  currentTime: number | null = 0;
  constructor(st: number | null, cur: number | null = 0) {
    super(st);
    this.currentTime = cur;
  }
}

const mkEl = (list: () => FakeAnim[]) => ({ el: { getAnimations: list } as unknown as Element });

describe('platform.sweep watchSweepPause', () => {
  it('a play with no start time yet is paused too and resumes at its time plus the time spent paused', () => {
    const loop = new Timed(null, 0);
    const { el } = mkEl(() => [loop]);
    const { IO, report } = fakeIO();
    let t = 1000;
    P.watchSweepPause([el], IO, () => t);
    report(el, true);
    expect(loop.log).toEqual(['pause']);
    t = 3500;
    report(el, false);
    expect(loop.log).toEqual(['pause', 'play']);
    expect(loop.currentTime).toBe(2500);
  });
  it('resumeTime adds the paused time to the saved time', () => {
    expect(P.resumeTime({ start: null, cur: 40, at: 10 }, 110)).toBe(140);
  });
  it('an animation created after mount and before the report is paused (the old mount-time list missed it)', () => {
    const late = new Timed(77);
    let made = false;
    const { el } = mkEl(() => (made ? [late] : []));
    const { IO, report } = fakeIO();
    P.watchSweepPause([el], IO);
    made = true;
    report(el, true);
    expect(late.log).toEqual(['pause']);
    report(el, false);
    expect(late.log).toEqual(['pause', 'play']);
    expect(late.startTime).toBe(77);
  });
  it('a hidden report with nothing to pause does not stop a later report from pausing', () => {
    const late = new Timed(5);
    let made = false;
    const { el } = mkEl(() => (made ? [late] : []));
    const { IO, report } = fakeIO();
    P.watchSweepPause([el], IO);
    report(el, true);
    report(el, false);
    made = true;
    report(el, true);
    expect(late.log).toEqual(['pause']);
  });
  it('pauses a running animation and resumes it with the saved start time', () => {
    const loop = new Timed(123);
    const { el } = mkEl(() => [loop]);
    const { IO, report } = fakeIO();
    P.watchSweepPause([el], IO);
    report(el, true);
    report(el, false);
    expect(loop.log).toEqual(['pause', 'play']);
    expect(loop.startTime).toBe(123);
  });
  it('leaves an animation the page cancelled while paused alone', () => {
    const loop = new Timed(123);
    const { el } = mkEl(() => [loop]);
    const { IO, report } = fakeIO();
    P.watchSweepPause([el], IO);
    report(el, true);
    loop.playState = 'idle';
    report(el, false);
    expect(loop.log).toEqual(['pause']);
  });
  it('a scene attribute change holds a reported element whose CSS play started again (the section paused rule flips to active)', () => {
    const loop = new Timed(null, 145);
    loop.playState = 'paused';
    const { el } = mkEl(() => [loop]);
    const { IO, report } = fakeIO();
    let fire: () => void = () => undefined;
    let watched: unknown = null;
    class MO {
      constructor(cb: () => void) {
        fire = cb;
      }
      observe(t: unknown, o: unknown) {
        watched = [t, o];
      }
      disconnect() {}
    }
    const host = {} as Element;
    let t = 10;
    P.watchSweepPause([el], IO, () => t, host, MO as unknown as typeof MutationObserver);
    expect(watched).toEqual([host, { attributes: true, attributeFilter: ['data-fw-scene'] }]);
    report(el, true);
    expect(loop.log).toEqual([]);
    loop.playState = 'running';
    t = 20;
    fire();
    expect(loop.log).toEqual(['pause']);
    t = 520;
    report(el, false);
    expect(loop.log).toEqual(['pause', 'play']);
    expect(loop.currentTime).toBe(645);
  });
  it('an attribute change leaves an element that is on screen alone', () => {
    const loop = new Timed(9);
    const { el } = mkEl(() => [loop]);
    const { IO } = fakeIO();
    let fire: () => void = () => undefined;
    class MO {
      constructor(cb: () => void) {
        fire = cb;
      }
      observe() {}
      disconnect() {}
    }
    P.watchSweepPause([el], IO, () => 0, {} as Element, MO as unknown as typeof MutationObserver);
    fire();
    expect(loop.log).toEqual([]);
  });
});
