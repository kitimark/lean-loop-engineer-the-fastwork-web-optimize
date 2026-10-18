import { describe, expect, it } from 'vitest';
import { createMenuController } from './controller';
import type { Phase } from './logic';

function fake() {
  const timers: { ms: number; cb: () => void; live: boolean }[] = [];
  const seen: Phase[] = [];
  const c = createMenuController({
    after: (ms, cb) => {
      const t = { ms, cb, live: true };
      timers.push(t);
      return () => {
        t.live = false;
      };
    },
    onPhase: (p) => seen.push(p),
  });
  return { c, timers, seen, fire: () => timers.filter((t) => t.live).forEach((t) => ((t.live = false), t.cb())) };
}

describe('menu controller', () => {
  it('open, close, and the 140 ms timer unmounts', () => {
    const f = fake();
    f.c.dispatch('toggle');
    f.c.dispatch('toggle');
    expect(f.c.phase()).toBe('closing');
    expect(f.timers.at(-1)?.ms).toBe(140);
    f.fire();
    expect(f.seen).toEqual(['open', 'closing', 'closed']);
  });
  it('re-opening while closing cancels the timer', () => {
    const f = fake();
    f.c.dispatch('toggle');
    f.c.dispatch('outside');
    f.c.dispatch('toggle');
    f.fire();
    expect(f.c.phase()).toBe('open');
  });
  it('select and outside are ignored when not open', () => {
    const f = fake();
    f.c.dispatch('select');
    f.c.dispatch('outside');
    expect(f.seen).toEqual([]);
  });
});
