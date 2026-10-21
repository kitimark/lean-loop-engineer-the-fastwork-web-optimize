// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { scrollLockOf } from './index';

const queries: string[] = [];
function stubMatchMedia(matches: boolean | 'throw') {
  vi.stubGlobal('matchMedia', (q: string) => {
    queries.push(q);
    if (matches === 'throw') throw new Error('matchMedia unavailable');
    return { matches, media: q } as MediaQueryList;
  });
}

afterEach(() => {
  queries.length = 0;
  vi.unstubAllGlobals();
});

describe('morph.tween:scroll-lock hover gate (Lean hoverNoneOf, engage_unread, engage_read_touch)', () => {
  const root = () => document.documentElement;
  it('installs the lock when (hover: none) reads as not matching', () => {
    stubMatchMedia(false);
    expect(scrollLockOf('scroll-lock', root())).toBeDefined();
    expect(queries).toEqual(['(hover: none)']);
  });
  it('does not install the lock when (hover: none) matches', () => {
    stubMatchMedia(true);
    expect(scrollLockOf('scroll-lock', root())).toBeUndefined();
    expect(queries).toEqual(['(hover: none)']);
  });
  it('does not install the lock when matchMedia throws', () => {
    stubMatchMedia('throw');
    expect(scrollLockOf('scroll-lock', root())).toBeUndefined();
    expect(queries).toEqual(['(hover: none)']);
  });
  it('other variants never read (hover: none) and never get the lock', () => {
    stubMatchMedia(false);
    expect(scrollLockOf('faithful', root())).toBeUndefined();
    expect(queries).toEqual([]);
  });
});
