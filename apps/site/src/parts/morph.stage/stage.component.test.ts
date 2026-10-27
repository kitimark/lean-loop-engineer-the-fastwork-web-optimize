// @vitest-environment jsdom
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Cb = () => void | (() => void);
const registered: { id: string; order: number; cb: Cb }[] = [];
vi.mock('../../engine/scroll', () => ({
  registerScroll: (id: string, order: number, cb: Cb) => {
    registered.push({ id, order, cb });
    return () => void registered.splice(0, registered.length);
  },
}));

import { MorphStage } from './index';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const golden = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/parts/morph-stage.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as { fn: string; out: { ops: { op: string; type?: string; passive?: boolean; kind?: string }[] } });
const ops = golden.find((r) => r.fn === 'morph.stage.const')!.out.ops;

describe('MorphStage in the DOM', () => {
  let root: Root | undefined;
  let container: HTMLElement;
  let scrollY = 0;
  const observed: string[] = [];
  let ioCb: ((e: { isIntersecting: boolean }[]) => void) | undefined;
  beforeEach(() => {
    registered.length = 0;
    observed.length = 0;
    scrollY = 0;
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        constructor(cb: typeof ioCb) {
          ioCb = cb;
          observed.push('IntersectionObserver');
        }
        observe() {}
        disconnect() {}
      },
    );
    vi.stubGlobal(
      'ResizeObserver',
      class {
        constructor() {
          observed.push('ResizeObserver');
        }
        observe() {}
        disconnect() {}
      },
    );
    vi.stubGlobal('CSS', { registerProperty: () => {} });
    Object.defineProperty(window, 'scrollY', { configurable: true, get: () => scrollY });
    Object.defineProperty(document.documentElement, 'scrollHeight', { configurable: true, get: () => 5800 });
    Object.defineProperty(window, 'innerHeight', { configurable: true, value: 800 });
    container = document.createElement('div');
    container.innerHTML = '<header data-fw="nav"></header><section data-fw="platform"></section><div data-fw="stage-track"></div>';
    document.body.appendChild(container);
    Object.defineProperty(container.querySelector('[data-fw="stage-track"]'), 'offsetHeight', { configurable: true, value: 600 });
  });
  afterEach(() => {
    if (root) act(() => root!.unmount());
    root = undefined;
    container.remove();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('adds no listener of its own, no scrollTo, and only the observers the Lean manifest lists', () => {
    const add = vi.spyOn(window, 'addEventListener');
    const addDoc = vi.spyOn(document, 'addEventListener');
    const scrollTo = vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
    const mount = vi.fn();
    root = createRoot(document.createElement('div'));
    act(() => root!.render(createElement(MorphStage, { onMount: mount })));
    expect(add.mock.calls.filter((c) => (c[2] as AddEventListenerOptions | undefined)?.passive === false)).toEqual([]);
    expect(add.mock.calls.map((c) => c[0]).filter((t) => t === 'touchmove' || t === 'wheel' || t === 'touchstart')).toEqual([]);
    expect(addDoc.mock.calls.map((c) => c[0]).filter((x) => x === 'touchmove' || x === 'wheel' || x === 'scroll')).toEqual([]);
    expect(observed.sort()).toEqual(ops.filter((o) => o.op === 'observe').map((o) => o.kind).sort());
    expect(registered.map((r) => r.id)).toEqual(['morph.stage']);
    for (const y of [4000, 4400, 4500, 4800, 5000, 4700, 4300]) {
      scrollY = y;
      const w = registered[0]!.cb();
      if (typeof w === 'function') w();
    }
    expect(scrollTo).not.toHaveBeenCalled();
    act(() => ioCb!([{ isIntersecting: true }]));
    expect(mount).toHaveBeenCalledTimes(1);
  });

  it('writes data-fw-morph and the platform pointer cut only at a state change', () => {
    const nav = container.querySelector<HTMLElement>('[data-fw="nav"]')!;
    const platform = container.querySelector<HTMLElement>('[data-fw="platform"]')!;
    root = createRoot(document.createElement('div'));
    act(() => root!.render(createElement(MorphStage, {})));
    const sets = vi.spyOn(platform.style, 'setProperty');
    const frame = (y: number) => {
      scrollY = y;
      const w = registered[0]!.cb();
      if (typeof w === 'function') w();
    };
    frame(4000);
    expect(nav.dataset.fwMorph).toBeUndefined();
    frame(4401);
    expect(Number(nav.dataset.fwMorph)).toBeGreaterThan(0.001);
    const at = nav.dataset.fwMorph;
    frame(4402);
    expect(nav.dataset.fwMorph).toBe(at);
    expect(platform.style.pointerEvents).toBe('');
    frame(4750);
    expect(platform.style.pointerEvents).toBe('none');
    frame(5000);
    expect(Number(nav.dataset.fwMorph)).toBe(1);
    frame(4400);
    expect(nav.dataset.fwMorph).toBe('0');
    expect(platform.style.pointerEvents).toBe('');
    expect(sets).not.toHaveBeenCalled();
  });
});

describe('morph.stage sources', () => {
  const text = [
    readFileSync(resolve(__dirname, 'index.tsx'), 'utf8'),
    readFileSync(resolve(__dirname, 'track.tsx'), 'utf8'),
    readFileSync(resolve(__dirname, 'driver.ts'), 'utf8'),
    readFileSync(resolve(__dirname, 'logic.ts'), 'utf8'),
  ].join('\n');
  it('call no scrollTo, no scrollBy, no scrollIntoView, no addEventListener and never pass passive: false', () => {
    expect(text).not.toMatch(/scrollTo|scrollBy|scrollIntoView|addEventListener|passive\s*:\s*false|preventDefault/);
  });
  it('the Lean manifest holds no scrollTo and no non-passive listener', () => {
    expect(ops.some((o) => o.op === 'scrollTo')).toBe(false);
    expect(ops.filter((o) => o.op === 'listen').every((o) => o.passive === true)).toBe(true);
  });
  it('App mounts the scroll-jack only through jackOn', () => {
    const app = readFileSync(resolve(__dirname, '../../App.tsx'), 'utf8');
    expect(app).toMatch(/jackOn\(stageV\) \? \(\s*<>\s*<MorphMount[\s\S]*<MorphTween[\s\S]*<\/>\s*\) : \(\s*<MorphStage/);
  });
});
