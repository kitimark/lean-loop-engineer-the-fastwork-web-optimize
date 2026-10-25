import { describe, expect, it } from 'vitest';
import { REST_ATTR } from '../morph.panel/rest.logic';
import { createTweenDriver, type PlatformEl, type TweenEnv } from './driver';

function setup(rest: boolean) {
  let now = 0;
  const frames = new Set<(t: number) => void>();
  const attrs = new Set<string>();
  const platform: PlatformEl = {
    getBoundingClientRect: () => ({ height: 500, bottom: 800 }),
    style: { pointerEvents: '', setProperty: () => undefined },
    hasAttribute: (n) => attrs.has(n),
    toggleAttribute: (n, force) => {
      if (force) attrs.add(n);
      else attrs.delete(n);
      return force;
    },
  };
  let wheel: ((e: { deltaY: number; preventDefault(): void }) => void) | undefined;
  const env: TweenEnv = {
    clock: { subscribe: (tick) => (frames.add(tick), () => void frames.delete(tick)) },
    now: () => now,
    reduced: () => false,
    viewportHeight: () => 800,
    platform: () => platform,
    scrollY: () => 1200,
    scrollToInstant: () => undefined,
    addListener: (t, fn) => void (t === 'wheel' && (wheel = fn as never)),
    removeListener: () => undefined,
    publish: () => undefined,
    rest,
  };
  const d = createTweenDriver(env);
  d.setNear(true);
  const run = (ms: number) => {
    const end = now + ms;
    for (let t = now + 16; t <= end; t += 16) {
      now = t;
      for (const f of [...frames]) f(t);
    }
  };
  return { d, run, push: (dy: number) => wheel?.({ deltaY: dy, preventDefault: () => undefined }), on: () => attrs.has(REST_ATTR) };
}

describe('morph.panel:rest in the tween driver', () => {
  it('clears the mark from the first frame past rest and sets it again when the tween returns to rest', () => {
    const s = setup(true);
    s.push(200);
    s.run(100);
    expect(s.d.state().value).toBeGreaterThan(0);
    expect(s.on()).toBe(false);
    s.run(2000);
    expect(s.d.state().value).toBe(1);
    expect(s.on()).toBe(false);
    s.push(-200);
    s.run(3000);
    expect(s.d.state().value).toBe(0);
    expect(s.on()).toBe(true);
  });
  it('writes nothing to the section without the flag', () => {
    const s = setup(false);
    s.push(200);
    s.run(3000);
    expect(s.on()).toBe(false);
    s.push(-200);
    s.run(3000);
    expect(s.on()).toBe(false);
  });
});
