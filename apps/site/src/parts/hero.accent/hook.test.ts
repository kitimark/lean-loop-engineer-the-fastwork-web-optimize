// @vitest-environment jsdom
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { act, createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToString } from 'react-dom/server';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const started = vi.fn();
vi.mock('./driver', () => ({ startAccentChain: (o: unknown) => (started(o), { setVisible: () => {}, stop: () => {} }) }));
vi.mock('../../engine/clock', () => ({ getClock: () => ({}) }));

import { HeroAccent } from './index';
import { accentHookSet, chainStarts } from './hook';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const root = resolve(__dirname, '../../../../..');
const golden = readFileSync(resolve(root, 'packages/contracts/golden/gate/path-pix.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Record<string, unknown>);

describe('accent hook against the Lean golden (Fw.Gate.PathPix.hookSet, chainStarts)', () => {
  const hooks = golden.filter((g) => g.kind === 'hook');
  const gates = golden.filter((g) => g.kind === 'chainStarts');
  it('has 16 search rows and the 4 gate rows', () => {
    expect(hooks).toHaveLength(16);
    expect(gates).toHaveLength(4);
  });
  for (const g of hooks) it(`search ${JSON.stringify(g.search)}`, () => expect(accentHookSet(g.search as string)).toBe(g.hook));
  for (const g of gates) it(`reduce ${g.reduce} hook ${g.hook}`, () => expect(chainStarts(g.reduce as boolean, g.hook as boolean)).toBe(g.starts));
});

describe('the hook is inert when unset (the faithful page is unchanged)', () => {
  let host: HTMLDivElement;
  beforeEach(() => {
    started.mockClear();
    host = document.createElement('div');
    document.body.appendChild(host);
    (globalThis as { IntersectionObserver?: unknown }).IntersectionObserver = class {
      observe() {}
      disconnect() {}
    };
    window.matchMedia = ((q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} })) as unknown as typeof window.matchMedia;
  });
  afterEach(() => {
    host.remove();
    window.history.replaceState({}, '', '/');
  });

  const mount = (search: string) => {
    window.history.replaceState({}, '', `/${search}`);
    const r = createRoot(host);
    act(() => r.render(createElement(HeroAccent, { variant: 'faithful' })));
    return r;
  };
  const ssr = renderToString(createElement(HeroAccent, { variant: 'faithful' }));

  it('unset: the chain starts once and the DOM is the server markup', () => {
    mount('');
    expect(started).toHaveBeenCalledTimes(1);
    expect(host.innerHTML).toBe(ssr);
    expect(host.querySelector('[data-fw-pin]')).toBeNull();
  });

  it('other parameters (a flag) leave it unset', () => {
    mount('?fw=hero.exit:threaded');
    expect(started).toHaveBeenCalledTimes(1);
    expect(host.innerHTML).toBe(ssr);
  });

  it('set: no chain, and the only DOM difference is the pin attribute', () => {
    mount('?fwpin=accent');
    expect(started).not.toHaveBeenCalled();
    expect(host.querySelector('[data-fw-pin]')?.getAttribute('data-fw-pin')).toBe('accent');
    expect(host.innerHTML.replace(' data-fw-pin="accent"', '')).toBe(ssr);
  });

  it('set together with a flag: still no chain', () => {
    mount('?fw=hero.exit:threaded&fwpin=accent');
    expect(started).not.toHaveBeenCalled();
  });
});
