// @vitest-environment jsdom
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MorphTween } from './index';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

type Write = { writer: string; prop: string; el: string };
const FRAMES = 48;
const STEP = 1000 / 60;

let root: Root | undefined;
let rafs: ((t: number) => void)[] = [];
let log: Write[] = [];
let restore: (() => void)[] = [];

const tagOf = (el: Element) => el.getAttribute('data-fw') ?? el.tagName.toLowerCase();

function wrap() {
  const proto = CSSStyleDeclaration.prototype;
  const set = proto.setProperty;
  proto.setProperty = function (this: CSSStyleDeclaration, prop: string, value: string | null, prio?: string) {
    const owner = [...document.querySelectorAll<HTMLElement>('[data-fw]')].find((e) => e.style === this);
    log.push({ writer: 'style.setProperty', prop, el: owner ? tagOf(owner) : '?' });
    return set.call(this, prop, value as string, prio as string);
  };
  restore.push(() => void (proto.setProperty = set));
  const mo = new MutationObserver((rs) => {
    for (const r of rs) if (r.attributeName && r.attributeName !== 'style') log.push({ writer: 'attribute', prop: r.attributeName, el: tagOf(r.target as Element) });
  });
  mo.observe(document.documentElement, { attributes: true, subtree: true });
  restore.push(() => mo.disconnect());
  return mo;
}

function page(variants: Record<string, string>, flip: boolean) {
  document.body.innerHTML = '<header data-fw="nav"></header><section data-fw="platform"></section>';
  document.documentElement.classList.toggle('is-flip', flip);
  (window as unknown as { __fw: unknown }).__fw = { config: { variants } };
  const platform = document.querySelector<HTMLElement>('[data-fw="platform"]')!;
  platform.getBoundingClientRect = () => ({ height: 900, bottom: 760 }) as DOMRect;
}

async function run(variants: Record<string, string>, flip: boolean): Promise<Write[][]> {
  act(() => root!.unmount());
  root = createRoot(document.createElement('div'));
  rafs = [];
  restore.forEach((f) => f());
  restore = [];
  vi.restoreAllMocks();
  page(variants, flip);
  const mo = wrap();
  act(() => root!.render(createElement(MorphTween, { variant: 'faithful' })));
  let now = 1000;
  vi.spyOn(performance, 'now').mockImplementation(() => now);
  const frames: Write[][] = [];
  window.dispatchEvent(new WheelEvent('wheel', { deltaY: 100, cancelable: true }));
  log = [];
  for (let i = 0; i < FRAMES; i++) {
    now += STEP;
    const cbs = rafs;
    rafs = [];
    for (const cb of cbs) cb(now);
    await Promise.resolve();
    mo.takeRecords().forEach((r) => r.attributeName && r.attributeName !== 'style' && log.push({ writer: 'attribute', prop: r.attributeName, el: tagOf(r.target as Element) }));
    frames.push(log);
    log = [];
  }
  return frames;
}

beforeEach(() => {
  rafs = [];
  log = [];
  vi.stubGlobal('requestAnimationFrame', (cb: (t: number) => void) => rafs.push(cb));
  vi.stubGlobal('cancelAnimationFrame', () => {});
  vi.stubGlobal(
    'IntersectionObserver',
    class {
      constructor(private cb: (e: { isIntersecting: boolean }[]) => void) {}
      observe() {
        this.cb([{ isIntersecting: true }]);
      }
      disconnect() {}
    },
  );
  vi.stubGlobal('matchMedia', () => ({ matches: false, addEventListener() {}, removeEventListener() {} }));
  root = createRoot(document.createElement('div'));
});

afterEach(() => {
  if (root) act(() => root!.unmount());
  root = undefined;
  restore.forEach((f) => f());
  restore = [];
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  document.documentElement.classList.remove('is-flip');
});

const perFrame = (frames: Write[][]) => frames.map((f) => f.length);
const keys = (frames: Write[][]) => [...new Set(frames.flat().filter((w) => w.prop !== 'data-fw-morph-tween').map((w) => `${w.writer} ${w.prop} ${w.el}`))].sort();

describe('the tween writes per frame (probe of the real MorphTween, jsdom, 48 frames at 60 Hz from one wheel push)', () => {
  it('base: --morph, data-fw-morph and --morph-fade every frame', async () => {
    const f = await run({}, false);
    expect(keys(f)).toEqual(expect.arrayContaining(['style.setProperty --morph nav', 'style.setProperty --morph-fade platform', 'attribute data-fw-morph nav']));
    expect(f.slice(2, 20).every((x) => x.length >= 3)).toBe(true);
  });

  it('flip, the tween as it was (no flip hook): the same writes with no reader', async () => {
    const f = await run({}, true);
    expect(keys(f)).toContain('style.setProperty --morph nav');
    expect(keys(f)).toContain('style.setProperty --morph-fade platform');
  });

  it('flip, morph.geom:on: only data-fw-morph per frame', async () => {
    const before = await run({}, true);
    const after = await run({ 'morph.geom': 'on' }, true);
    expect(keys(after)).toEqual(['attribute data-fw-morph nav']);
    const sum = (fs: Write[][]) => fs.reduce((a, x) => a + x.length, 0);
    expect(sum(after)).toBeLessThan(sum(before));
    const out = process.env.FW_STYLE_PROBE_OUT;
    if (out) {
      const base = await run({}, false);
      mkdirSync(dirname(out), { recursive: true });
      writeFileSync(
        out,
        JSON.stringify({ frames: FRAMES, base: { perFrame: perFrame(base), keys: keys(base) }, flipBefore: { perFrame: perFrame(before), keys: keys(before) }, flipAfter: { perFrame: perFrame(after), keys: keys(after) } }, null, 1),
      );
    }
  });

  it('a push down and back up ends with the same inline values as the base (the leaving frame writes)', async () => {
    const ends = async (variants: Record<string, string>, flip: boolean) => {
      await run(variants, flip);
      window.dispatchEvent(new WheelEvent('wheel', { deltaY: -100, cancelable: true }));
      let now = 5000;
      vi.spyOn(performance, 'now').mockImplementation(() => now);
      for (let i = 0; i < FRAMES; i++) {
        now += STEP;
        const cbs = rafs;
        rafs = [];
        for (const cb of cbs) cb(now);
      }
      const nav = document.querySelector<HTMLElement>('[data-fw="nav"]')!;
      const platform = document.querySelector<HTMLElement>('[data-fw="platform"]')!;
      return [nav.style.getPropertyValue('--morph'), nav.dataset.fwMorph, platform.style.getPropertyValue('--morph-fade')];
    };
    const base = await ends({}, false);
    expect(base[1]).toBe('0');
    expect(await ends({ 'morph.geom': 'on' }, true)).toEqual(base);
  });
});
