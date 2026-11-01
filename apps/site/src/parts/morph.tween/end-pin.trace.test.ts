import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createTweenDriver, type PlatformEl, type TweenEnv } from './driver';
import { BASE } from './end.logic';
import * as logic from './end-pin.logic';
import { withPinTrace, type PinTraceHost } from './end-pin.trace';

vi.mock('./end-pin.logic', async (importOriginal) => {
  const m = await importOriginal<typeof import('./end-pin.logic')>();
  return { ...m, outcome: vi.fn(m.outcome), dueWhy: vi.fn(m.dueWhy) };
});

function arm(host: PinTraceHost) {
  let now = 0;
  let y = 0;
  const timers: { at: number; cb: () => void }[] = [];
  const writes: number[] = [];
  const listeners = new Map<string, (e: never) => void>();
  const platform: PlatformEl = { getBoundingClientRect: () => ({ height: 500, bottom: 800 }), style: { pointerEvents: '', setProperty: () => {} } };
  const env: TweenEnv = {
    clock: {
      subscribe: () => () => {},
      interval: (ms, cb) => {
        const t = { at: now + ms, cb };
        timers.push(t);
        return () => void (timers.includes(t) && timers.splice(timers.indexOf(t), 1));
      },
    },
    now: () => now,
    reduced: () => false,
    viewportHeight: () => 800,
    platform: () => platform,
    scrollY: () => y,
    scrollToInstant: (to) => void (writes.push(to), (y = to)),
    addListener: (t, fn) => void listeners.set(t, fn),
    removeListener: (t) => void listeners.delete(t),
    publish: () => {},
    hooks: { ...BASE, target: () => 0 },
    endPin: { touch: () => () => {} },
  };
  withPinTrace(env, host);
  const d = createTweenDriver(env);
  d.setNear(true);
  (listeners.get('wheel') as unknown as (e: { deltaY: number; defaultPrevented: boolean; preventDefault(): void }) => void)({ deltaY: 50, defaultPrevented: false, preventDefault: () => {} });
  const run = () => {
    y = 30;
    d.pin();
    y = 20;
    d.pin();
    now += logic.QUIET_MS + 1;
    for (const t of timers.splice(0)) t.cb();
    d.pin();
  };
  return { env, writes, run };
}

describe('the end-pin trace runs only with the page hook (window.__fwPinTrace)', () => {
  beforeEach(() => {
    vi.mocked(logic.outcome).mockClear();
    vi.mocked(logic.dueWhy).mockClear();
  });
  it('without the hook env.trace is unset and no reading computes outcome or dueWhy; the pin still writes', () => {
    const a = arm({});
    expect(a.env.trace).toBeUndefined();
    a.run();
    expect(a.writes).toEqual([0]);
    expect(logic.outcome).not.toHaveBeenCalled();
    expect(logic.dueWhy).not.toHaveBeenCalled();
  });
  it('a hook installed after mount is read at the next reading', () => {
    const host: PinTraceHost = {};
    const a = arm(host);
    const seen: object[] = [];
    host.__fwPinTrace = (e) => void seen.push(e);
    expect(a.env.trace).toBe(host.__fwPinTrace);
    a.run();
    expect(a.writes).toEqual([0]);
    expect(logic.outcome).toHaveBeenCalled();
    expect(seen.map((e) => (e as { op?: string }).op)).toContain('write');
  });
});
