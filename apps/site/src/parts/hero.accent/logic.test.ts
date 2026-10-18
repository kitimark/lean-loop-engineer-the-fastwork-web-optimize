import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { mediaCondition } from '../../breakpoints';
import { startAccentChain } from './driver';
import * as L from './logic';
import { MEDIA_IDS } from './media';

goldenConformance('hero.accent', {
  next: (i) => L.next({ c: i.c as number }),
  cursorAfter: (i) => L.cursorAfter({ j: i.j as number }),
  widthOf: (i) => L.widthOf({ c: i.c as number }),
  chainAt: (i) => L.chainAt({ e: i.e as number }),
  idleFrame: (i) => L.idleFrame({ e: i.e as number }),
});

/** A fake timer clock: `interval` registers a repeating timer on virtual time. */
function fakeClock() {
  let now = 0;
  let nextId = 1;
  const timers = new Map<number, { at: number; ms: number; cb: () => void }>();
  return {
    api: {
      interval(ms: number, cb: () => void) {
        const id = nextId++;
        timers.set(id, { at: now + ms, ms, cb });
        return () => void timers.delete(id);
      },
    },
    get pending() {
      return timers.size;
    },
    advance(to: number) {
      for (;;) {
        const due = [...timers.entries()].filter(([, t]) => t.at <= to).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) break;
        now = due[1].at;
        due[1].at += due[1].ms;
        due[1].cb();
      }
      now = to;
    },
  };
}

describe('hero.accent driver follows the Lean timeline', () => {
  it('state and cursor at sampled times equal chainAt', () => {
    const clock = fakeClock();
    let state: L.AccentState = 'idle';
    let cursor = -1;
    const chain = startAccentChain({ clock: clock.api, hooks: { onState: (s) => (state = s), onCursor: (c) => (cursor = c) } });
    for (const e of [0, 2199, 2200, 3099, 3100, 3999, 4000, 5249, 5250, 6200, 24000, 45000, 70000]) {
      clock.advance(e);
      // boundary instants fire in the same tick the model switches on
      expect({ state, cursor }, `t=${e}`).toEqual(L.chainAt({ e }));
    }
    chain.stop();
    expect(clock.pending).toBe(0);
  });
  it('one pending timer at a time; leaving the viewport cancels, returning restarts the wait', () => {
    const clock = fakeClock();
    const states: string[] = [];
    const chain = startAccentChain({ clock: clock.api, hooks: { onState: (s) => states.push(s), onCursor: () => {} } });
    expect(clock.pending).toBe(1);
    chain.setVisible(false);
    expect(clock.pending).toBe(0);
    clock.advance(10000);
    expect(states).toEqual([]);
    chain.setVisible(true); // restarts the idle wait: first idle already used (cursor < 0 and first flag cleared) -> 1250
    clock.advance(10000 + 1249);
    expect(states).toEqual([]);
    clock.advance(10000 + 1250);
    expect(states).toEqual(['draw-out']);
  });
});

describe('hero.accent media', () => {
  const css = readFileSync(resolve(__dirname, 'accent.module.css'), 'utf8');
  it('the CSS @media blocks are byte-equal to the generated conditions', () => {
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => m[1]!.trim().replace(/\s+/g, ' '));
    expect(found).toEqual(MEDIA_IDS.map((id) => mediaCondition(id)));
  });
});
