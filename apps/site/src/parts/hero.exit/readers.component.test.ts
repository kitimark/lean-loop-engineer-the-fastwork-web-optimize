// @vitest-environment jsdom
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Hero } from '../hero';
import golden from '../../../../../packages/contracts/golden/parts/hero.exit.scoped.json';
import { liveReaders, READER_SELECTOR, SCOPE_ATTR, SCOPED } from './scope';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

class FakeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
}

let root: Root | undefined;
let container: HTMLElement | undefined;

beforeEach(() => {
  vi.stubGlobal('IntersectionObserver', FakeObserver);
  vi.stubGlobal('ResizeObserver', FakeObserver);
  container = document.createElement('div');
  document.body.appendChild(container);
});

afterEach(() => {
  if (root) act(() => root!.unmount());
  root = undefined;
  container?.remove();
  vi.unstubAllGlobals();
});

const stage = (): HTMLElement => container!.querySelector<HTMLElement>(`[${SCOPE_ATTR}]`)!;
const written = (el: HTMLElement): boolean => el.style.getPropertyValue('--exit-opacity') !== '';

function mount() {
  root = createRoot(container!);
  act(() => root!.render(createElement(Hero, { variants: { 'hero.exit': SCOPED } })));
}

describe('the scoped exit writes every reader present at the write', () => {
  it('after the parts mount the stage holds the golden reader count and each got the inline write', () => {
    mount();
    const readers = [...stage().querySelectorAll<HTMLElement>(READER_SELECTOR)];
    expect(readers.length).toBe(golden.inline.narrow.touched - 1);
    expect(readers.every(written)).toBe(true);
  });

  it('liveReaders adds a reader mounted later and drops a removed one', () => {
    mount();
    const list = liveReaders(stage());
    const first = list.get();
    expect(first.length).toBe(golden.inline.narrow.touched - 1);
    const deck = stage().querySelector('[data-fw="hero-deck"]')!;
    const late = document.createElement('article');
    deck.appendChild(late);
    expect(list.get()).toContain(late);
    expect(list.get().length).toBe(first.length + 1);
    const gone = first[0]!;
    gone.remove();
    expect(list.get()).not.toContain(gone);
    expect(list.get().length).toBe(first.length);
    list.stop();
  });

  it('liveReaders keeps its list while nothing below the stage changes', () => {
    mount();
    const list = liveReaders(stage());
    expect(list.get()).toBe(list.get());
    list.stop();
  });
});
