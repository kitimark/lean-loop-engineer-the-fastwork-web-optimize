// @vitest-environment jsdom
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { NavHitTest, ON_DARK_CLASS } from './index';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: Root | undefined;
let nav: HTMLElement;

beforeEach(() => {
  nav = document.createElement('header');
  nav.dataset.fw = 'nav';
  document.body.appendChild(nav);
  // jsdom has no layout: the probe finds no element, so the hit answer is false and only the morph can make the nav dark.
  (document as unknown as { elementFromPoint: () => null }).elementFromPoint = () => null;
});

afterEach(() => {
  if (root) act(() => root!.unmount());
  root = undefined;
  nav.remove();
});

const flush = () => act(async () => { await Promise.resolve(); });
const morph = async (v: number) => {
  nav.dataset.fwMorph = String(v);
  await flush();
};

describe('nav.hitTest follows the morph signal (original: is-on-dark = g || morph > .2, N2:13228)', () => {
  it('turns on above 0.2 and off again with no scroll frame in between (a push moves the morph, not the scroll)', async () => {
    root = createRoot(document.createElement('div'));
    act(() => root!.render(createElement(NavHitTest, { variant: 'faithful' })));
    expect(nav.classList.contains(ON_DARK_CLASS)).toBe(false);
    await morph(0.2); // strictly above
    expect(nav.classList.contains(ON_DARK_CLASS)).toBe(false);
    await morph(0.21);
    expect(nav.classList.contains(ON_DARK_CLASS)).toBe(true);
    await morph(1);
    expect(nav.classList.contains(ON_DARK_CLASS)).toBe(true);
    await morph(0.19);
    expect(nav.classList.contains(ON_DARK_CLASS)).toBe(false);
  });

  it('stops observing on unmount', async () => {
    root = createRoot(document.createElement('div'));
    act(() => root!.render(createElement(NavHitTest, { variant: 'faithful' })));
    act(() => root!.unmount());
    root = undefined;
    await morph(1);
    expect(nav.classList.contains(ON_DARK_CLASS)).toBe(false);
  });
});
