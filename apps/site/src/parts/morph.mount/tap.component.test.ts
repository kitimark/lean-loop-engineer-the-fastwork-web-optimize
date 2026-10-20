// @vitest-environment jsdom
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MorphMount, type MorphMountHandle } from './index';
import { WARM_QUIET_MS } from './logic';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

type IoCallback = (entries: { isIntersecting: boolean }[]) => void;
let ioCallbacks: IoCallback[] = [];
class FakeIntersectionObserver {
  constructor(cb: IoCallback) {
    ioCallbacks.push(cb);
  }
  observe() {}
  disconnect() {}
}

let clock = 0;
let root: Root | undefined;
let container: HTMLElement | undefined;

beforeEach(() => {
  ioCallbacks = [];
  clock = 1000;
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  vi.stubGlobal('IntersectionObserver', FakeIntersectionObserver);
  vi.spyOn(performance, 'now').mockImplementation(() => clock);
  container = document.createElement('div');
  document.body.appendChild(container);
});

afterEach(() => {
  if (root) act(() => root!.unmount());
  root = undefined;
  container?.remove();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function render(variant: string, isActive: () => boolean = () => false) {
  const add = vi.spyOn(window, 'addEventListener');
  const remove = vi.spyOn(window, 'removeEventListener');
  const onMount = vi.fn();
  let handle: MorphMountHandle | null = null;
  root = createRoot(container!);
  act(() => {
    root!.render(createElement(MorphMount, { variant, isActive, onMount, onReady: (h) => (handle = h) }));
  });
  const engine = new Set(add.mock.calls.filter((c) => c[0] === 'resize').map((c) => c[1]));
  const scrollAdds = add.mock.calls.filter((c) => c[0] === 'scroll' && !engine.has(c[1]));
  const listener = scrollAdds[0]?.[1];
  const scrollRemovals = () => remove.mock.calls.filter((c) => c[0] === 'scroll' && c[1] === listener).length;
  const stamps = () => {
    const before = vi.mocked(performance.now).mock.calls.length;
    window.dispatchEvent(new Event('scroll'));
    return vi.mocked(performance.now).mock.calls.length - before;
  };
  return { scrollAdds, listener, scrollRemovals, stamps, onMount, handle: () => handle };
}

describe.each(['shift', 'shift-dormant'])('MorphMount %s: the scroll stamp listener is removed exactly at mount', (variant) => {
  it('mount by the first intersecting entry', () => {
    const r = render(variant);
    expect(r.scrollAdds).toHaveLength(1);
    expect(r.scrollAdds[0]![2]).toEqual({ passive: true });
    expect(r.stamps()).toBe(1);
    expect(r.scrollRemovals()).toBe(0);
    act(() => ioCallbacks[0]!([{ isIntersecting: true }]));
    expect(r.onMount).toHaveBeenCalledTimes(1);
    expect(r.scrollRemovals()).toBe(1);
    expect(r.stamps()).toBe(0);
    act(() => root!.unmount());
    root = undefined;
    expect(r.scrollRemovals()).toBe(2);
  });

  it('mount by a taken push', () => {
    const r = render(variant, () => true);
    act(() => r.handle()!.refresh());
    expect(r.stamps()).toBe(1);
    expect(r.scrollRemovals()).toBe(0);
    act(() => {
      window.dispatchEvent(new WheelEvent('wheel', { deltaY: 40, cancelable: true }));
    });
    expect(r.onMount).toHaveBeenCalledTimes(1);
    expect(r.scrollRemovals()).toBe(1);
    expect(r.stamps()).toBe(0);
  });

  it('mount by the warm check at a still moment', () => {
    const r = render(variant);
    clock += WARM_QUIET_MS - 1;
    expect(r.stamps()).toBe(1);
    act(() => vi.advanceTimersByTime(WARM_QUIET_MS));
    expect(r.onMount).toHaveBeenCalledTimes(0);
    expect(r.scrollRemovals()).toBe(0);
    clock += WARM_QUIET_MS;
    act(() => vi.advanceTimersByTime(WARM_QUIET_MS));
    expect(r.onMount).toHaveBeenCalledTimes(1);
    expect(r.scrollRemovals()).toBe(1);
    expect(r.stamps()).toBe(0);
  });
});

describe('MorphMount faithful', () => {
  it('adds no scroll stamp listener', () => {
    const r = render('faithful');
    expect(r.scrollAdds).toHaveLength(0);
    act(() => ioCallbacks[0]!([{ isIntersecting: true }]));
    expect(r.onMount).toHaveBeenCalledTimes(1);
  });
});
