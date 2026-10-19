import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { exitFrame, pointerOff } from '../hero.exit/logic';
import { FAR_ROOT_MARGIN, countdownHidden, installHiddenGate, parseExit } from './hidden';
import { HeroCountdown } from './index';
import part from './part.json';

const root = resolve(__dirname, '../../../../..');
const lean = readFileSync(resolve(root, 'lean/Fw/Parts/HeroCountdownHidden.lean'), 'utf8');

interface Wire {
  num: string;
  den: string;
}
interface Row {
  zone: string;
  reduced: boolean;
  trackTop: Wire;
  trackHeight: Wire;
  vh: Wire;
  exit: Wire | null;
  pointerOff: boolean;
  far: boolean;
  hidden: boolean;
}
const num = (w: Wire): number => Number(w.num) / Number(w.den);
const rows = readFileSync(resolve(root, 'packages/contracts/golden/parts/hero.countdown.hidden.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);

describe('gate decision against the Lean golden (gate open/closed per zone)', () => {
  it('13 zones, both outcomes, the pointer-off zone stays open', () => {
    expect(rows).toHaveLength(13);
    expect(rows.some((r) => r.hidden)).toBe(true);
    expect(rows.some((r) => !r.hidden)).toBe(true);
    const p = rows.find((r) => r.zone === 'pointer-off')!;
    expect(p.pointerOff && !p.hidden).toBe(true);
  });
  for (const r of rows) {
    it(r.zone, () => {
      const written = r.exit === null ? '' : String(exitFrame(r.reduced, num(r.trackTop), num(r.trackHeight), num(r.vh)).opacity);
      const exit = parseExit(written);
      if (r.exit === null) expect(exit).toBeNull();
      else expect(exit).toBeCloseTo(num(r.exit), 12);
      expect(pointerOff(exit ?? 1)).toBe(r.pointerOff);
      expect(countdownHidden(exit, r.far)).toBe(r.hidden);
    });
  }
});

describe('constants and definitions come from the Lean source', () => {
  it('FAR_ROOT_MARGIN is `grow`: one viewport height above and below', () => {
    expect(lean).toContain('def grow (vp : Rect) : Rect := ⟨vp.x, vp.y - vp.h, vp.w, 3 * vp.h⟩');
    expect(FAR_ROOT_MARGIN).toBe('100% 0px');
  });
  it('countdownHidden is `gateHidden`', () => {
    expect(lean).toContain('def gateHidden (ex : Option Rat) (vp R : Rect) : Bool := decide (ex = some 0) || farOff vp R');
  });
  it('part.json names the Lean module and its own ledger key', () => {
    const v = part.variants['hidden-pause'] as { provenance: Record<string, string> };
    expect(v.provenance.lean).toBe('Fw.Parts.HeroCountdownHidden');
    expect(v.provenance.ledger).not.toMatch(/k25h/);
  });
});

describe('parseExit', () => {
  it('reads what hero.exit writes', () => {
    expect(parseExit('')).toBeNull();
    expect(parseExit('0')).toBe(0);
    expect(parseExit('1')).toBe(1);
    expect(parseExit('0.04')).toBe(0.04);
    expect(parseExit('1e-7')).toBe(1e-7);
    expect(parseExit('abc')).toBeNull();
  });
});

interface FakeEl {
  style: { transform: string; props: Map<string, string>; getPropertyValue(n: string): string };
  closest(sel: string): FakeEl | null;
}
const el = (): FakeEl => {
  const props = new Map<string, string>();
  return {
    style: { transform: '', props, getPropertyValue: (n) => props.get(n) ?? '' },
    closest: () => null,
  };
};

const harness = () => {
  const stage = el();
  const track = el();
  const clock = el();
  clock.closest = (sel) => (sel === '[data-splash]' ? stage : sel === '[data-fw="hero-exit"]' ? track : null);
  let moCb: (() => void) | null = null;
  let ioCb: ((e: Partial<IntersectionObserverEntry>[]) => void) | null = null;
  let ioOpts: IntersectionObserverInit | undefined;
  const MO = class {
    constructor(cb: () => void) {
      moCb = cb;
    }
    observe() {}
    disconnect() {}
  } as unknown as typeof MutationObserver;
  const IO = class {
    constructor(cb: (e: Partial<IntersectionObserverEntry>[]) => void, opts?: IntersectionObserverInit) {
      ioCb = cb;
      ioOpts = opts;
    }
    observe() {}
    disconnect() {}
  } as unknown as typeof IntersectionObserver;
  const g = installHiddenGate(clock as unknown as HTMLElement, IO, MO);
  const writeExit = (v: string) => {
    stage.style.props.set('--exit-opacity', v);
    moCb!();
  };
  const near = (yes: boolean) =>
    ioCb!([{ isIntersecting: yes, intersectionRect: { width: yes ? 10 : 0, height: yes ? 10 : 0 } as DOMRectReadOnly }]);
  return { g, writeExit, near, ioOpts: () => ioOpts };
};

describe('installHiddenGate (createWriteGate driven by the two signals)', () => {
  it('passes writes while open, holds them at exit 0, writes the latest on reopening (Lean first_visible_rewrites)', () => {
    const h = harness();
    const a = el();
    const w = h.g.wrap(a as unknown as HTMLElement);
    w.style.transform = 'translateY(1px)';
    expect(a.style.transform).toBe('translateY(1px)');
    h.writeExit('0.04');
    expect(h.g.hidden).toBe(false);
    h.writeExit('0');
    expect(h.g.hidden).toBe(true);
    w.style.transform = 'translateY(2px)';
    w.style.transform = 'translateY(3px)';
    expect(a.style.transform).toBe('translateY(1px)');
    expect(h.g.skipped).toBe(2);
    h.writeExit('0.5');
    expect(h.g.hidden).toBe(false);
    expect(a.style.transform).toBe('translateY(3px)');
  });
  it('the far signal closes alone and reopens with the latest value', () => {
    const h = harness();
    expect(h.ioOpts()).toEqual({ rootMargin: FAR_ROOT_MARGIN, threshold: [0] });
    const a = el();
    const w = h.g.wrap(a as unknown as HTMLElement);
    h.writeExit('1');
    h.near(false);
    expect(h.g.hidden).toBe(true);
    w.style.transform = 'translateY(4px)';
    expect(a.style.transform).toBe('');
    h.near(true);
    expect(a.style.transform).toBe('translateY(4px)');
  });
  it('stop opens the gate and flushes', () => {
    const h = harness();
    const a = el();
    const w = h.g.wrap(a as unknown as HTMLElement);
    h.writeExit('0');
    w.style.transform = 'translateY(5px)';
    h.g.stop();
    expect(a.style.transform).toBe('translateY(5px)');
  });
});

describe('hidden-pause server markup equals the faithful markup (the gate is client-only)', () => {
  const strip = (s: string) => s.replace(/data-fw-variant="[^"]*"/g, '');
  it('hero instance', () => {
    const a = renderToString(createElement(HeroCountdown, { variant: 'faithful', impl: 'plain' }));
    const b = renderToString(createElement(HeroCountdown, { variant: 'hidden-pause', impl: 'plain' }));
    expect(strip(b)).toBe(strip(a));
  });
});
