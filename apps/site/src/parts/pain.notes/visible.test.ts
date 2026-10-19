import { describe, expect, it } from 'vitest';
import { createNotesDriver, type NotesEnv } from './driver';
import type { Note } from './logic';

/** A virtual clock: `interval` is a repeating timer; `advance(ms)` fires timers in time order. */
function world(over: Partial<NotesEnv> = {}, late = 0) {
  let now = 0;
  let nextId = 1;
  const timers = new Map<number, { at: number; ms: number; cb: () => void }>();
  let last: { extras: Note[] } = { extras: [] };
  const state = { narrow: false, card: null as number | null };
  const env: NotesEnv = {
    stageRect: () => ({ top: 0, width: 780, height: 528 }),
    copyRect: () => ({ top: -200, height: 100, width: 100 }),
    cardTop: () => state.card,
    innerHeight: () => 900,
    narrow: () => state.narrow,
    reduced: () => false,
    c860: () => false,
    interval: (ms, cb) => {
      const id = nextId++;
      timers.set(id, { at: now + ms, ms, cb });
      return () => void timers.delete(id);
    },
    now: () => now,
    frame: (cb) => {
      cb();
      return () => {};
    },
    commit: (v) => {
      last = v;
    },
    writeNote: () => {},
    ...over,
  };
  const advance = (ms: number) => {
    const end = now + ms;
    for (;;) {
      let pick: [number, { at: number; ms: number; cb: () => void }] | null = null;
      for (const e of timers) if (e[1].at + late <= end && (!pick || e[1].at < pick[1].at)) pick = e;
      if (!pick) break;
      now = pick[1].at + late;
      pick[1].at += Math.max(1, pick[1].ms);
      pick[1].cb();
    }
    now = end;
  };
  return { env, state, advance, extras: () => last.extras.length, timers, clock: () => now };
}

describe('pain.notes variant visible: the interval exists only while armed', () => {
  it('visible start: first tick 3000 ms after the section came into view, as the original', () => {
    const w = world();
    const d = createNotesDriver(w.env, 1, { armWhenVisible: true });
    d.start();
    d.intersect(true, 1);
    w.advance(2999);
    expect(w.extras()).toBe(0);
    w.advance(1);
    expect(w.extras()).toBe(1);
    w.advance(3000);
    expect(w.extras()).toBe(2);
  });
  it('narrow: no timer at all (the original keeps one that does nothing); leaving narrow resumes on the original grid', () => {
    const w = world();
    const d = createNotesDriver(w.env, 1, { armWhenVisible: true });
    d.start();
    d.intersect(true, 1);
    w.advance(1000);
    w.state.narrow = true;
    d.sync();
    expect(w.timers.size).toBe(0);
    w.advance(3500);
    w.state.narrow = false;
    d.sync();
    expect(w.timers.size).toBe(1);
    expect(w.extras()).toBe(0);
    w.advance(1499);
    expect(w.extras()).toBe(0);
    w.advance(1);
    expect(w.extras()).toBe(1); // t = 6000: the original's second tick
  });
  it('covered: the timer is dropped on scroll and re-armed on the grid when uncovered', () => {
    const w = world();
    const d = createNotesDriver(w.env, 1, { armWhenVisible: true });
    d.start();
    d.intersect(true, 1);
    w.advance(3000);
    expect(w.extras()).toBe(1);
    w.state.card = 800;
    d.onScroll();
    expect(w.extras()).toBe(0);
    expect(w.timers.size).toBe(0);
    w.advance(1000);
    w.state.card = null;
    d.onScroll();
    w.advance(1999);
    expect(w.extras()).toBe(0);
    w.advance(1);
    expect(w.extras()).toBe(1); // t = 6000
  });
  it('out of view: disarmed, extras cleared, grid restarts at the next entry', () => {
    const w = world();
    const d = createNotesDriver(w.env, 1, { armWhenVisible: true });
    d.start();
    d.intersect(true, 1);
    w.advance(3000);
    d.intersect(false, 0);
    expect(w.timers.size).toBe(0);
    expect(w.extras()).toBe(0);
    w.advance(1000);
    d.intersect(true, 1); // t0 = 4000
    w.advance(2999);
    expect(w.extras()).toBe(0);
    w.advance(1);
    expect(w.extras()).toBe(1);
  });
  it('faithful (no option) keeps one repeating timer regardless of narrow', () => {
    const w = world();
    const d = createNotesDriver(w.env, 1);
    d.start();
    d.intersect(true, 1);
    w.state.narrow = true;
    d.sync();
    expect(w.timers.size).toBe(1);
  });
});

describe('pain.notes variant visible: ticks stay on the absolute grid when every timer fires late', () => {
  it.each([1, 7, 250, 2999])('timer %i ms late: tick k fires at t0 + 3000k', (late) => {
    const fired: number[] = [];
    const w = world({}, late);
    const d = createNotesDriver({ ...w.env, commit: () => fired.push(w.clock()) }, 1, { armWhenVisible: true });
    d.start();
    d.intersect(true, 1);
    fired.length = 0;
    w.advance(3000 * 8 + late);
    expect(fired.length).toBe(8);
    fired.forEach((t, i) => expect(t - late).toBe(3000 * (i + 1)));
  });
});
