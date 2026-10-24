// @vitest-environment jsdom
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MorphMount, type MorphMountHandle } from './index';

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

describe('MorphMount arm-late in the DOM', () => {
  let root: Root | undefined;
  let container: HTMLElement;
  let bottom = 5000;
  beforeEach(() => {
    ioCallbacks = [];
    vi.stubGlobal('IntersectionObserver', FakeIntersectionObserver);
    container = document.createElement('div');
    document.body.appendChild(container);
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(
      () => ({ height: 600, bottom, top: bottom - 600, left: 0, right: 0, width: 0, x: 0, y: 0, toJSON: () => ({}) }) as DOMRect,
    );
  });
  afterEach(() => {
    if (root) act(() => root!.unmount());
    root = undefined;
    container.remove();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  const flags = (add: { mock: { calls: unknown[][] } }, type: string) =>
    add.mock.calls.filter((c) => c[0] === type).map((c) => (c[2] as AddEventListenerOptions).passive);

  it('attaches the wheel and touchmove listeners passive outside the band and non-passive inside it', () => {
    const add = vi.spyOn(window, 'addEventListener');
    let handle: MorphMountHandle | null = null;
    root = createRoot(container);
    act(() => root!.render(createElement(MorphMount, { variant: 'arm-late', onReady: (h) => (handle = h) })));
    act(() => ioCallbacks[0]!([{ isIntersecting: true }]));
    expect(flags(add, 'wheel')).toEqual([true]);
    expect(flags(add, 'touchmove')).toEqual([true]);
    expect(flags(add, 'touchstart')).toEqual([true]);
    bottom = 900;
    act(() => handle!.refresh());
    expect(flags(add, 'wheel')).toEqual([true, false]);
    expect(flags(add, 'touchmove')).toEqual([true, false]);
    expect(flags(add, 'touchstart')).toEqual([true]);
  });

  it('keeps the original registration for the faithful variant: non-passive from the first near entry', () => {
    const add = vi.spyOn(window, 'addEventListener');
    root = createRoot(container);
    act(() => root!.render(createElement(MorphMount, { variant: 'faithful' })));
    act(() => ioCallbacks[0]!([{ isIntersecting: true }]));
    expect(flags(add, 'wheel')).toEqual([false]);
    expect(flags(add, 'touchmove')).toEqual([false]);
  });
});
