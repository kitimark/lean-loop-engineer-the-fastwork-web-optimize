import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { exitFrame, pointerOff } from '../hero.exit/logic';
import { countdownHidden, gatedInstance, installHiddenGate, parseExit } from './hidden';
import { HeroCountdown } from './index';
import part from './part.json';

const root = resolve(__dirname, '../../../../..');
const lean = readFileSync(resolve(root, 'lean/Fw/Parts/HeroCountdownHidden.lean'), 'utf8');
const indexSrc = readFileSync(resolve(__dirname, 'index.tsx'), 'utf8');

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
      expect(countdownHidden(exit)).toBe(r.hidden);
    });
  }
});

describe('constants and definitions come from the Lean source', () => {
  it('countdownHidden is `gateHidden` (exit branch only, no distance branch)', () => {
    expect(lean).toContain('def gateHidden (ex : Option Rat) : Bool := decide (ex = some 0)');
    expect(lean).not.toContain('def farOff');
  });
  it('gatedInstance is the Lean `gatedInstance` and drives the component', () => {
    expect(lean).toContain('def gatedInstance (variant fwId : String) : Bool := variant == "hidden-pause" && fwId == "hero-countdown"');
    expect(indexSrc).toContain('const hiddenPause = gatedInstance(variant, fwId);');
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
  const clock = el();
  clock.closest = (sel) => (sel === '[data-splash]' ? stage : null);
  let moCb: (() => void) | null = null;
  const MO = class {
    constructor(cb: () => void) {
      moCb = cb;
    }
    observe() {}
    disconnect() {}
  } as unknown as typeof MutationObserver;
  const g = installHiddenGate(clock as unknown as HTMLElement, MO);
  const writeExit = (v: string) => {
    stage.style.props.set('--exit-opacity', v);
    moCb!();
  };
  return { g, writeExit };
};

describe('installHiddenGate (createWriteGate driven by the exit signal)', () => {
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
  it('a jump back to the top reopens on the same exit read (no distance signal can hold it)', () => {
    const h = harness();
    const a = el();
    const w = h.g.wrap(a as unknown as HTMLElement);
    h.writeExit('0');
    w.style.transform = 'translateY(4px)';
    expect(a.style.transform).toBe('');
    h.writeExit('1');
    expect(h.g.hidden).toBe(false);
    expect(a.style.transform).toBe('translateY(4px)');
  });
  it('without a stage ancestor the gate stays open', () => {
    const clock = el();
    const MO = class {
      constructor() {
        throw new Error('no observer without a stage');
      }
    } as unknown as typeof MutationObserver;
    const g = installHiddenGate(clock as unknown as HTMLElement, MO);
    const a = el();
    g.wrap(a as unknown as HTMLElement).style.transform = 'translateY(6px)';
    expect(g.hidden).toBe(false);
    expect(a.style.transform).toBe('translateY(6px)');
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

describe('gatedInstance (Lean #guard cases): only the hero instance is gated', () => {
  it('hero with hidden-pause is gated', () => {
    expect(gatedInstance('hidden-pause', 'hero-countdown')).toBe(true);
  });
  it('morph instance with hidden-pause stays ungated (morph.countdown keeps its own gate)', () => {
    expect(gatedInstance('hidden-pause', 'morph-countdown')).toBe(false);
  });
  it('hero with another variant is not gated', () => {
    expect(gatedInstance('faithful', 'hero-countdown')).toBe(false);
    expect(gatedInstance('strip', 'hero-countdown')).toBe(false);
  });
});
