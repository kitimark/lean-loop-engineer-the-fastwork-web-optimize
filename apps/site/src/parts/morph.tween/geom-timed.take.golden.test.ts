import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { createTweenDriver, type TweenEnv } from './driver';
import { idealAt } from './geom-timed.logic';

type Row = { fn: string; in: { name: string; events: { e: number; g: number }[]; darks: boolean[][] }; out: { taken: (number | null)[]; m: number[] } };
const rows = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/morph-geom-timed.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row)
  .filter((l) => l.fn === 'take');

const TICK = 17;

function replay(sc: Row['in']) {
  let now = 0;
  let push = -1;
  let anims = false;
  let tick = null as ((t: number) => void) | null;
  const timers: { at: number; cb: () => void }[] = [];
  const taken: (number | null)[] = sc.events.map(() => null);
  const m: number[] = sc.events.map(() => 0);
  const ticksAfterTake: number[] = sc.events.map(() => 0);
  let wheel: (e: { deltaY: number; defaultPrevented: boolean; preventDefault(): void }) => void = () => {};
  const env: TweenEnv = {
    clock: {
      subscribe: (cb) => ((tick = cb), () => void (tick = null)),
      interval: (ms, cb) => {
        const t = { at: now + ms, cb };
        timers.push(t);
        return () => void timers.splice(timers.indexOf(t) >>> 0, 1);
      },
    },
    now: () => now,
    reduced: () => false,
    viewportHeight: () => 800,
    platform: () => ({ getBoundingClientRect: () => ({ height: 500, bottom: 800 }), style: { pointerEvents: '', setProperty() {} } }),
    scrollY: () => 1200,
    scrollToInstant() {},
    addListener: (t, fn) => void (t === 'wheel' && (wheel = fn as never)),
    removeListener() {},
    publish() {},
    timed: {
      take: (f, t, s) => {
        const k = Math.round((now - s) / TICK);
        const ok = anims || (sc.darks[push]?.[k] ?? false);
        if (ok) {
          anims = true;
          taken[push] ??= k;
          m[push] = idealAt(f, t, now - s);
        }
        return ok;
      },
      push() {},
      settle() {},
      dispose() {},
    },
  };
  const d = createTweenDriver(env);
  d.setNear(true);
  const end = sc.events.at(-1)!.e + 1500;
  for (now = 0; now <= end; now += TICK) {
    timers.sort((a, b) => a.at - b.at);
    while (timers.length && timers[0].at <= now) timers.shift()!.cb();
    const live = tick;
    const ev = sc.events[push + 1];
    if (ev && ev.e === now) {
      push++;
      wheel({ deltaY: ev.g === 1 ? 50 : -50, defaultPrevented: false, preventDefault() {} });
    } else if (live) live(now);
    if (push >= 0 && taken[push] !== null && tick !== null) ticksAfterTake[push]++;
  }
  d.dispose();
  return { taken, m, ticksAfterTake };
}

describe('the take rule with retry against the Lean golden', () => {
  it('has the seven scenarios', () => expect(rows.length).toBe(7));
  for (const r of rows) {
    it(`${r.in.name}: taken frame and value equal Lean; no frame subscription once taken`, () => {
      const got = replay(r.in);
      expect(got.taken).toEqual(r.out.taken);
      got.m.forEach((v, i) => expect(v, `push ${i}`).toBeCloseTo(r.out.m[i], 5));
      expect(got.ticksAfterTake.every((n) => n === 0)).toBe(true);
    });
  }
});
