import { describe, expect, it } from 'vitest';
import type { MotionClock } from '../../engine/clock';
import { createLoop } from '../people.carousel/driver';
import type { State } from '../people.carousel/logic';
import { createOpener, type OFlags } from '../people.o/driver';

/** A manual clock: `interval` timers run when `advance` passes their time; nothing else. */
function fakeClock() {
  let now = 0;
  const timers = new Map<number, { at: number; ms: number; cb: () => void }>();
  let id = 0;
  const clock: MotionClock = {
    subscribe: () => () => undefined,
    interval(ms, cb) {
      const k = ++id;
      timers.set(k, { at: now + ms, ms, cb });
      return () => timers.delete(k);
    },
  };
  return {
    clock,
    get live() {
      return timers.size;
    },
    advance(ms: number) {
      const end = now + ms;
      for (;;) {
        const next = [...timers.entries()].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        now = next[1].at;
        next[1].cb(); // an interval cancels itself in its callback (people/shared `after`)
        if (timers.has(next[0])) next[1].at += next[1].ms;
      }
      now = end;
    },
  };
}

describe('carousel loop', () => {
  it('swaps at 800 ms, advances at 1020 ms, and follows the closed form', () => {
    const f = fakeClock();
    const seen: State[] = [];
    const loop = createLoop({ clock: f.clock, onState: (s) => seen.push(s) });
    loop.setActive(true);
    loop.start();
    f.advance(799);
    expect(loop.state).toEqual({ x: 0, swapping: false });
    f.advance(1);
    expect(loop.state).toEqual({ x: 0, swapping: true });
    f.advance(220);
    expect(loop.state).toEqual({ x: 1, swapping: false });
    f.advance(1020 * 5);
    expect(loop.state).toEqual({ x: 0, swapping: false }); // six steps: back to the start
    loop.dispose();
    expect(f.live).toBe(0);
  });
  it('waits while inactive and never advances on a lost swap', () => {
    const f = fakeClock();
    const loop = createLoop({ clock: f.clock, onState: () => undefined });
    loop.start();
    f.advance(5000);
    expect(loop.state).toEqual({ x: 0, swapping: false });
    loop.setActive(true);
    f.advance(800);
    expect(loop.state.swapping).toBe(true);
    loop.setActive(false);
    expect(loop.state.swapping).toBe(false);
    f.advance(220);
    expect(loop.state.x).toBe(0);
  });
});

describe('o opener', () => {
  it('stacks after 1300 ms and opens 120 ms later; leaving closes it', () => {
    const f = fakeClock();
    let flags: OFlags = { stack: false, expanded: false };
    const o = createOpener({ clock: f.clock, reduced: false, standalone: false, onFlags: (x) => (flags = x), onReset: () => undefined });
    o.visibility(true);
    f.advance(1299);
    expect(flags).toEqual({ stack: false, expanded: false });
    f.advance(1);
    expect(flags).toEqual({ stack: true, expanded: false });
    f.advance(120);
    expect(flags).toEqual({ stack: true, expanded: true });
    o.visibility(false);
    expect(flags).toEqual({ stack: false, expanded: false });
  });
  it('reduced motion opens at once', () => {
    const f = fakeClock();
    let flags: OFlags = { stack: false, expanded: false };
    const o = createOpener({ clock: f.clock, reduced: true, standalone: false, onFlags: (x) => (flags = x), onReset: () => undefined });
    o.visibility(true);
    expect(flags).toEqual({ stack: true, expanded: true });
    expect(f.live).toBe(0);
  });
});
