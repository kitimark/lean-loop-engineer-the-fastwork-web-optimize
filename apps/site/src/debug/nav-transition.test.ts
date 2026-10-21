// @vitest-environment jsdom
// The nav transition recorder (src/debug/nav-transition.ts): off unless the URL says `fw-debug=nav-transition`; when on, it records
// the order of the class flip, the base `--morph` writes and the nav's own transition events.
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Nav } from '../parts/nav';
import { DEBUG_GLOBAL, HOT_MS, installNavTransitionDebug, MAX_ROWS, navDebugOn, type DebugEnv, type DebugLog } from './nav-transition';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const ON = '?fw=morph.tween:waapi&fw-debug=nav-transition';

describe('navDebugOn: the only reader of the query', () => {
  it.each([
    ['', false],
    ['?', false],
    ['?fw=morph.tween:waapi', false],
    ['?preset=v2-proved', false],
    ['?fw-debug=', false],
    ['?fw-debug=other', false],
    ['?fw-debug=nav-transition', true],
    ['?fw=morph.tween:waapi&fw-debug=nav-transition', true],
    ['?fw-debug=other,nav-transition', true],
    ['?fw-debug=other&fw-debug=nav-transition', true],
    ['?fw-debug=nav-transitions', false],
  ])('%j -> %s', (search, want) => {
    expect(navDebugOn(search)).toBe(want);
  });
});

/** A recorder environment with a manual clock, manual frames and a fake ResizeObserver; MutationObserver is jsdom's. */
function fakeEnv() {
  const store: Record<string, unknown> = {};
  let now = 0;
  const frames = new Map<number, (ts: number) => void>();
  let nextId = 1;
  let sizeCb: ((entries: unknown[]) => void) | undefined;
  const env: DebugEnv = {
    now: () => now,
    raf: (cb) => {
      frames.set(nextId, cb);
      return nextId++;
    },
    cancelRaf: (id) => void frames.delete(id),
    store,
    mutationObserver: MutationObserver,
    resizeObserver: class {
      constructor(cb: (entries: unknown[]) => void) {
        sizeCb = cb;
      }
      observe() {}
      disconnect() {
        sizeCb = undefined;
      }
    } as unknown as typeof ResizeObserver,
  };
  return {
    env,
    store,
    at: (t: number) => void (now = t),
    frame: (ts: number) => {
      const cbs = [...frames.values()];
      frames.clear();
      for (const cb of cbs) cb(ts);
    },
    size: (w: number, h: number) => sizeCb?.([{ borderBoxSize: [{ inlineSize: w, blockSize: h }] }]),
    pendingFrames: () => frames.size,
    hasSizeObserver: () => sizeCb !== undefined,
  };
}

const flush = () => Promise.resolve();
const log = (store: Record<string, unknown>) => (store[DEBUG_GLOBAL] as { navTransition: DebugLog }).navTransition;
let nav: HTMLElement;

beforeEach(() => {
  nav = document.createElement('header');
  document.body.appendChild(nav);
});
afterEach(() => nav.remove());

describe('off by default', () => {
  it.each(['', '?fw=morph.tween:waapi', '?preset=v2-proved', '?fw-debug=nav-transitions'])('%j: installs nothing', (search) => {
    const f = fakeEnv();
    const add = vi.spyOn(nav, 'addEventListener');
    expect(installNavTransitionDebug(search, nav, f.env)).toBeNull();
    expect(DEBUG_GLOBAL in f.store).toBe(false);
    expect(add).not.toHaveBeenCalled();
    expect(f.pendingFrames()).toBe(0);
    expect(f.hasSizeObserver()).toBe(false);
  });

  it('a mounted Nav on the default URL defines no window.__fwDebug and adds no nav listener for transitions', () => {
    window.matchMedia = ((q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} })) as unknown as typeof window.matchMedia;
    expect(location.search).toBe('');
    const calls: string[] = [];
    const orig = HTMLElement.prototype.addEventListener;
    HTMLElement.prototype.addEventListener = function (this: HTMLElement, type: string, ...rest: unknown[]) {
      // React delegates every event type on its root container; only the nav element itself is of interest.
      if (this.dataset.fw === 'nav') calls.push(type);
      return (orig as (...a: unknown[]) => void).call(this, type, ...rest);
    } as typeof orig;
    const host = document.createElement('div');
    document.body.appendChild(host);
    const root: Root = createRoot(host);
    try {
      act(() => root.render(createElement(Nav, { variant: 'faithful' })));
      expect((window as unknown as Record<string, unknown>)[DEBUG_GLOBAL]).toBeUndefined();
      expect(host.querySelector('[data-fw="nav"]')).not.toBeNull();
      expect(calls.filter((t) => t.startsWith('transition'))).toEqual([]);
      act(() => root.unmount());
    } finally {
      HTMLElement.prototype.addEventListener = orig;
      host.remove();
    }
  });
});

describe('on: ?fw-debug=nav-transition', () => {
  it('a mounted Nav on ?fw-debug=nav-transition defines window.__fwDebug.navTransition and records its flip (the wiring in nav/index.tsx)', async () => {
    window.matchMedia = ((q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} })) as unknown as typeof window.matchMedia;
    history.replaceState(null, '', '/?fw-debug=nav-transition');
    const host = document.createElement('div');
    document.body.appendChild(host);
    const root: Root = createRoot(host);
    try {
      act(() => root.render(createElement(Nav, { variant: 'faithful' })));
      const bag = (window as unknown as Record<string, { navTransition?: DebugLog }>)[DEBUG_GLOBAL];
      expect(bag?.navTransition?.rows).toEqual([]);
      const el = host.querySelector<HTMLElement>('[data-fw="nav"]')!;
      el.setAttribute('data-fw-morph', '0.4');
      await act(async () => { await Promise.resolve(); });
      expect(bag?.navTransition?.rows.some((r) => r.k === 'data' && r.v === '0.4')).toBe(true);
      act(() => root.unmount());
    } finally {
      history.replaceState(null, '', '/');
      delete (window as unknown as Record<string, unknown>)[DEBUG_GLOBAL];
      host.remove();
    }
  });

  it('records the data write, the class flip and the base write of separate tasks in the order they were written', async () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    expect(off).not.toBeNull();
    nav.classList.add('is-morphing');
    f.at(10);
    await flush();
    nav.setAttribute('data-fw-morph', '0.5');
    nav.style.setProperty('--morph', '0.5');
    f.at(20);
    await flush();
    nav.setAttribute('data-fw-morph', '0');
    nav.classList.remove('is-morphing');
    nav.style.setProperty('--morph', '0');
    f.at(30);
    await flush();
    const rows = log(f.store).rows;
    expect(rows.map((r) => [r.k, r.t])).toEqual([
      ['cls', 10],
      ['data', 20],
      ['base', 20],
      ['data', 30],
      ['cls', 30],
      ['base', 30],
    ]);
    expect(rows[0]).toMatchObject({ k: 'cls', on: true });
    expect(rows[5]).toMatchObject({ k: 'base', v: '0' });
    off?.();
  });

  it('one row per MutationRecord in record order: --morph, then the class, then data-fw-morph in ONE task give base, cls, data', async () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    f.at(7);
    nav.style.setProperty('--morph', '0.4');
    nav.classList.add('is-morphing');
    nav.setAttribute('data-fw-morph', '0.4');
    await flush();
    expect(log(f.store).rows).toEqual([
      { k: 'base', t: 7, v: '0.4' },
      { k: 'cls', t: 7, on: true },
      { k: 'data', t: 7, v: '0.4' },
    ]);
    off?.();
  });

  it('the other order of the same three writes gives the other order of rows (the order is not fixed by the recorder)', async () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    nav.setAttribute('data-fw-morph', '0.4');
    nav.classList.add('is-morphing');
    nav.style.setProperty('--morph', '0.4');
    await flush();
    expect(log(f.store).rows.map((r) => r.k)).toEqual(['data', 'cls', 'base']);
    off?.();
  });

  it('records of one attribute keep their own values and interleave with the others: base 0.5, cls on, base 0.6, cls off', async () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    nav.style.setProperty('--morph', '0.5');
    nav.classList.add('is-morphing');
    nav.style.setProperty('--morph', '0.6');
    nav.classList.remove('is-morphing');
    await flush();
    expect(log(f.store).rows.map((r) => (r.k === 'base' ? `base:${r.v}` : r.k === 'cls' ? `cls:${r.on}` : r.k))).toEqual([
      'base:0.5',
      'cls:true',
      'base:0.6',
      'cls:false',
    ]);
    off?.();
  });

  it('a record that changes nothing the recorder watches gives no row (another class, another property, the same value)', async () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    nav.classList.add('is-on-dark');
    nav.style.setProperty('--other', '1');
    nav.setAttribute('data-fw-morph', '0');
    await flush();
    expect(log(f.store).rows.map((r) => r.k)).toEqual(['data']);
    nav.setAttribute('data-fw-morph', '0');
    await flush();
    expect(log(f.store).rows).toHaveLength(1);
    off?.();
  });

  it('a sampler read is a row between the writes it falls between: base, read, cls (the read takes the queued records first)', async () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    const read = (f.store[DEBUG_GLOBAL] as { navTransitionRead?: () => void }).navTransitionRead!;
    f.at(10);
    nav.dispatchEvent(new Event('transitionrun')); // hot
    f.at(20);
    nav.style.setProperty('--morph', '0.5');
    read(); // same task as the write: the base record is logged before the read
    nav.classList.add('is-morphing');
    await flush();
    expect(log(f.store).rows.map((r) => r.k)).toEqual(['tr', 'base', 'read', 'cls']);
    off?.();
  });

  it('a read while cold logs nothing, and the function is gone after the disposer', async () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    const bag = f.store[DEBUG_GLOBAL] as { navTransitionRead?: () => void };
    bag.navTransitionRead!();
    expect(log(f.store).rows).toEqual([]);
    off?.();
    expect(bag.navTransitionRead).toBeUndefined();
  });

  it('records the nav own transition events and ignores a child bubbling one', () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    const child = nav.appendChild(document.createElement('a'));
    const fire = (el: Element, type: string, prop: string, elapsed: number) => {
      const e = new Event(type, { bubbles: true });
      Object.assign(e, { propertyName: prop, elapsedTime: elapsed });
      el.dispatchEvent(e);
    };
    f.at(5);
    fire(nav, 'transitionrun', 'width', 0);
    fire(nav, 'transitionstart', 'width', 0);
    fire(child, 'transitionrun', 'opacity', 0);
    f.at(700);
    fire(nav, 'transitioncancel', 'width', 0.3);
    fire(nav, 'transitionend', 'width', 0.68);
    const rows = log(f.store).rows;
    expect(rows.map((r) => (r.k === 'tr' ? `${r.type}:${r.prop}:${r.el}` : r.k))).toEqual([
      'transitionrun:width:0',
      'transitionstart:width:0',
      'transitioncancel:width:0.3',
      'transitionend:width:0.68',
    ]);
    off?.();
    fire(nav, 'transitionrun', 'width', 0);
    expect(log(f.store).rows).toHaveLength(4);
  });

  it('runs the frame loop only while hot: none while cold, one per frame until HOT_MS after the last nav row, re-armed by the next row', () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    expect(f.pendingFrames()).toBe(0); // cold: no rAF is registered at install
    f.at(1);
    f.frame(1); // nothing to run
    f.size(984, 56); // cold size: not logged
    expect(log(f.store).rows).toEqual([]);
    expect(f.pendingFrames()).toBe(0);
    f.at(100);
    nav.dispatchEvent(new Event('transitionrun')); // a nav row heats the recorder and starts the loop
    expect(f.pendingFrames()).toBe(1);
    f.at(116);
    f.frame(116);
    f.size(985, 56);
    expect(f.pendingFrames()).toBe(1);
    f.at(100 + HOT_MS - 1);
    f.frame(100 + HOT_MS - 1);
    expect(f.pendingFrames()).toBe(1);
    f.at(100 + HOT_MS); // the first frame at or past hotUntil logs nothing and does not re-register
    f.frame(100 + HOT_MS);
    expect(f.pendingFrames()).toBe(0);
    f.size(986, 56);
    expect(log(f.store).rows.map((r) => r.k)).toEqual(['tr', 'raf', 'size', 'raf']);
    f.at(5000);
    nav.dispatchEvent(new Event('transitionrun')); // re-armed by the next nav row
    expect(f.pendingFrames()).toBe(1);
    off?.();
    expect(f.pendingFrames()).toBe(0);
  });

  it('a nav row while the loop runs does not start a second loop', () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    f.at(10);
    nav.dispatchEvent(new Event('transitionrun'));
    f.at(20);
    nav.dispatchEvent(new Event('transitionstart'));
    expect(f.pendingFrames()).toBe(1);
    off?.();
  });

  it('keeps at most MAX_ROWS rows and counts the rest', () => {
    const f = fakeEnv();
    const off = installNavTransitionDebug(ON, nav, f.env);
    for (let i = 0; i < MAX_ROWS + 7; i++) nav.dispatchEvent(new Event('transitionrun'));
    expect(log(f.store).rows).toHaveLength(MAX_ROWS);
    expect(log(f.store).dropped).toBe(7);
    off?.();
  });
});
