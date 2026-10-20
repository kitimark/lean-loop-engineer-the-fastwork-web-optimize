// @vitest-environment jsdom
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { HeroExit } from './index';
import { SCOPE_ATTR, SCOPED } from './scope';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

type Cb = (f: { vh: number }) => void | (() => void);
const registered: Cb[] = [];

vi.mock('../../engine/scroll', () => ({
  getScrollEngine: () => ({
    variant: 'batched',
    register: (_id: string, _order: number, cb: Cb) => {
      registered.push(cb);
      return () => {};
    },
  }),
}));
vi.mock('../../engine/clock', () => ({ getClock: () => ({ subscribe: () => () => {} }) }));

let root: Root | undefined;
let container: HTMLElement | undefined;

beforeEach(() => {
  registered.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
});

afterEach(() => {
  if (root) act(() => root!.unmount());
  root = undefined;
  container?.remove();
});

describe('the mounted hero.exit:scoped driver', () => {
  it('writes --exit-opacity inline on a reader appended after mount, at the next writer call', async () => {
    root = createRoot(container!);
    act(() => root!.render(createElement(HeroExit, { variant: SCOPED }, createElement('div', { 'data-fw': 'hero-deck' }))));
    const stage = container!.querySelector<HTMLElement>(`[${SCOPE_ATTR}]`)!;
    const deck = stage.querySelector<HTMLElement>('[data-fw="hero-deck"]')!;
    const article = document.createElement('article');
    deck.appendChild(article);
    await Promise.resolve(); // let the observer queue its record
    expect(article.style.getPropertyValue('--exit-opacity')).toBe('');
    const write = registered[0]!({ vh: 800 });
    expect(typeof write).toBe('function');
    (write as () => void)();
    expect(article.style.getPropertyValue('--exit-opacity')).not.toBe('');
    expect(article.style.getPropertyValue('--exit-scatter')).not.toBe('');
  });
});
