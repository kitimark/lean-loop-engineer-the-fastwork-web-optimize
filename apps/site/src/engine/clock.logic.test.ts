import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { createRafClock, type ClockEnv } from './clock';
import * as logic from './clock.logic';

const GOLDEN = new URL('../../../../packages/contracts/golden/parts/engine.clock.jsonl', import.meta.url);

describe.skipIf(!existsSync(GOLDEN))('engine.clock golden conformance', () => {
  const lines = existsSync(GOLDEN) ? readFileSync(GOLDEN, 'utf8').split('\n').filter((l) => l.trim()) : [];
  it.each(lines.map((l, i) => [i + 1, JSON.parse(l) as { fn: string; in: Record<string, unknown>; out: unknown }] as const))('line %i', (_i, v) => {
    const i = v.in;
    const out =
      v.fn === 'sharedLoopAction' ? logic.sharedLoopAction(i.sharedSubs as number, i.loopActive as boolean)
      : v.fn === 'rafRegistrationsPerFrame' ? logic.rafRegistrationsPerFrame(i.sharedSubs as number, i.ownSubs as number)
      : v.fn === 'rerequest' ? logic.rerequest(i.kind as 'shared' | 'own', i.sharedSubs as number, i.stillSubscribed as boolean)
      : v.fn === 'timerRegistrations' ? logic.timerRegistrations(i.intervals as number)
      : v.fn === 'validInterval' ? logic.validInterval(i.ms as number)
      : (() => { throw new Error(`unknown fn ${v.fn}`); })();
    expect(out).toEqual(v.out);
  });
});

describe('clock scheduling decisions', () => {
  it('shared loop starts on the first and stops on the last', () => {
    expect(logic.sharedLoopAction(1, false)).toBe('start');
    expect(logic.sharedLoopAction(2, true)).toBe('none');
    expect(logic.sharedLoopAction(0, true)).toBe('stop');
    expect(logic.sharedLoopAction(0, false)).toBe('none');
  });
  it('rAF registrations: one shared plus one per own subscriber', () => {
    expect(logic.rafRegistrationsPerFrame(0, 0)).toBe(0);
    expect(logic.rafRegistrationsPerFrame(5, 0)).toBe(1);
    expect(logic.rafRegistrationsPerFrame(5, 3)).toBe(4);
    expect(logic.rafRegistrationsPerFrame(0, 6)).toBe(6);
  });
  it('rerequest and interval validity', () => {
    expect(logic.rerequest('shared', 1, false)).toBe(true);
    expect(logic.rerequest('shared', 0, true)).toBe(false);
    expect(logic.rerequest('own', 0, true)).toBe(true);
    expect(logic.rerequest('own', 3, false)).toBe(false);
    expect(logic.timerRegistrations(2)).toBe(2);
    expect(logic.validInterval(1000)).toBe(true);
    expect(logic.validInterval(-1)).toBe(false);
    expect(logic.validInterval(Number.NaN)).toBe(false);
  });
});

function fakeEnv() {
  let next = 1;
  const pending = new Map<number, (t: number) => void>();
  const timers = new Map<number, () => void>();
  let rafCalls = 0;
  const env: ClockEnv = {
    raf: (cb) => (rafCalls++, pending.set(next, cb), next++),
    caf: (h) => void pending.delete(h),
    setInterval: (cb) => (timers.set(next, cb), next++),
    clearInterval: (h) => void timers.delete(h as number),
  };
  const frame = (t: number) => {
    const run = [...pending];
    pending.clear();
    for (const [, cb] of run) cb(t);
  };
  return { env, frame, pending, timers, rafCalls: () => rafCalls };
}

describe('clock behaviour', () => {
  it('shared subscribers use one rAF callback per frame', () => {
    const f = fakeEnv();
    const c = createRafClock(f.env);
    let n = 0;
    for (let i = 0; i < 5; i++) c.subscribe(() => void n++);
    expect(f.pending.size).toBe(1);
    f.frame(16);
    expect(n).toBe(5);
    expect(f.pending.size).toBe(1);
  });
  it('own subscribers hold one rAF callback each, and release it on unsubscribe', () => {
    const f = fakeEnv();
    const c = createRafClock(f.env);
    const offs = [0, 1, 2].map(() => c.subscribe(() => {}, { own: true }));
    expect(f.pending.size).toBe(3);
    f.frame(16);
    expect(f.pending.size).toBe(3);
    offs[0]!();
    expect(f.pending.size).toBe(2);
    f.frame(32);
    expect(f.pending.size).toBe(2);
    offs[1]!();
    offs[2]!();
    expect(f.pending.size).toBe(0);
  });
  it('an own tick that unsubscribes itself stops requesting frames', () => {
    const f = fakeEnv();
    const c = createRafClock(f.env);
    let off = () => {};
    let n = 0;
    off = c.subscribe(() => (n++, off()), { own: true });
    f.frame(16);
    f.frame(32);
    expect(n).toBe(1);
    expect(f.pending.size).toBe(0);
  });
  it('subscribing during a shared frame does not double register', () => {
    const f = fakeEnv();
    const c = createRafClock(f.env);
    let added = false;
    c.subscribe(() => {
      if (!added) (added = true, c.subscribe(() => {}));
    });
    f.frame(16);
    expect(f.pending.size).toBe(1);
  });
  it('interval is a real timer, cancelable', () => {
    const f = fakeEnv();
    const c = createRafClock(f.env);
    let n = 0;
    const off = c.interval(1000, () => void n++);
    expect(f.timers.size).toBe(1);
    [...f.timers.values()][0]!();
    expect(n).toBe(1);
    off();
    expect(f.timers.size).toBe(0);
    expect(() => c.interval(Number.NaN, () => {})).toThrow();
  });
});
