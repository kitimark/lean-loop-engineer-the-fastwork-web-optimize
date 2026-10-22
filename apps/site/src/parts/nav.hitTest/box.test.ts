import { describe, expect, it } from 'vitest';
import { clipRect, unionRect } from '../nav/box';
import { hitPoint } from './logic';
import { navProbeRect, probeFaithful, type ProbeEnv } from './probe';

interface Fake {
  classes: Set<string>;
  morph: string;
  rect: { left: number; top: number; width: number; height: number };
}

function nav(f: Fake): HTMLElement {
  return {
    dataset: { fwMorph: f.morph },
    classList: { contains: (c: string) => f.classes.has(c) },
    style: { pointerEvents: '' },
    getBoundingClientRect: () => f.rect,
  } as unknown as HTMLElement;
}

function env(w: number, h: number, seen: { x: number; y: number }[]): ProbeEnv {
  return {
    doc: {
      elementFromPoint: (x: number, y: number) => {
        seen.push({ x, y });
        return null;
      },
      elementsFromPoint: () => [],
      querySelector: () => null,
    },
    win: { getComputedStyle: (() => ({})) as unknown as Window['getComputedStyle'], innerHeight: h, innerWidth: w },
  };
}

const vp = { w: 390, h: 844 };
const union = unionRect(vp);
const base = (): Fake => ({ classes: new Set(['is-morphing']), morph: '0.5', rect: union });

describe('nav.hitTest probes the Lean box of a union-box nav', () => {
  it('uses the clip rect while the box applies', () => {
    expect(navProbeRect(nav(base()), env(vp.w, vp.h, []), true)).toEqual(clipRect(vp, 0.5));
  });
  it('probes the point of the original pill, not of the union box', () => {
    const seen: { x: number; y: number }[] = [];
    probeFaithful(nav(base()), env(vp.w, vp.h, seen), true);
    const want = hitPoint(clipRect(vp, 0.5));
    expect(seen).toEqual([want]);
    expect(want).not.toEqual(hitPoint(union));
  });
  it('reads the DOM rect at rest, with the locale menu open, and without the union box', () => {
    const e = env(vp.w, vp.h, []);
    const rest = base();
    rest.classes.clear();
    expect(navProbeRect(nav(rest), e, true)).toBe(rest.rect);
    const locale = base();
    locale.classes.add('is-locale-open');
    expect(navProbeRect(nav(locale), e, true)).toBe(locale.rect);
    const faithful = base();
    expect(navProbeRect(nav(faithful), e, false)).toBe(faithful.rect);
  });
});
