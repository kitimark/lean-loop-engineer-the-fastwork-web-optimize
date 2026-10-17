import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { createPanelWriter } from './driver';
import * as L from './logic';

describe('morph.panel logic', () => {
  it('closed state', () => {
    expect(L.panelOpacity(0)).toBe(0);
    expect(L.panelBlurPx(0)).toBe(12);
    expect(L.panelScale(0)).toBeCloseTo(0.96);
    expect(L.panelFlags(0)).toEqual({ scene: 'paused', ariaHidden: true, ctaTabindexOff: true, expanded: false });
  });
  it('thresholds are strict', () => {
    expect(L.sceneActive(0.001)).toBe(false);
    expect(L.sceneActive(0.0011)).toBe(true);
    expect(L.ariaHidden(0.35)).toBe(false);
    expect(L.ctaTabOff(0.55)).toBe(false);
    expect(L.expanded(0.92)).toBe(false);
    expect(L.expanded(0.9201)).toBe(true);
  });
  it('progress clamps at both ends', () => {
    expect(L.panelProgress(0.08)).toBe(0);
    expect(L.panelProgress(0.8)).toBe(1);
    expect(L.panelProgress(5)).toBe(1);
    expect(L.panelProgress(-1)).toBe(0);
  });
});

function fakeNode() {
  const log: string[] = [];
  return {
    log,
    node: {
      setAttribute: (n: string, v: string) => void log.push(`set ${n}=${v}`),
      removeAttribute: (n: string) => void log.push(`rm ${n}`),
    },
  };
}

describe('morph.panel writer', () => {
  it('first call writes every attribute, later calls only the ones that flipped', () => {
    const p = fakeNode();
    const c = fakeNode();
    const w = createPanelWriter({ panel: p.node, cta: c.node });
    w.apply(0);
    expect(p.log).toEqual(['set data-start-selling-scene=paused', 'set aria-hidden=true', 'rm data-expanded']);
    expect(c.log).toEqual(['set tabindex=-1']);
    p.log.length = 0;
    c.log.length = 0;
    w.apply(0.0005);
    expect(p.log).toEqual([]);
    w.apply(0.2);
    expect(p.log).toEqual(['set data-start-selling-scene=active']);
    p.log.length = 0;
    w.apply(0.4);
    expect(p.log).toEqual(['set aria-hidden=false']);
    expect(c.log).toEqual([]);
    w.apply(0.6);
    expect(c.log).toEqual(['rm tabindex']);
    w.apply(0.95);
    expect(p.log).toContain('set data-expanded=');
  });
});

goldenConformance('morph.panel', Object.fromEntries(
  Object.entries(L.GOLDEN_ARGS).map(([fn, names]) => [
    fn,
    (i: Record<string, unknown>) => (L as unknown as Record<string, (...a: unknown[]) => unknown>)[fn]!(...names.map((k) => i[k])),
  ]),
));

describe('morph.panel rest variant', () => {
  it('rest exactly when the blur radius is 0 (Lean rest_iff), toggle at morph 0.8', () => {
    expect(L.panelFilterState(0)).toBe('fade');
    expect(L.panelFilterState(0.79)).toBe('fade');
    expect(L.panelFilterState(0.8)).toBe('rest');
    expect(L.panelFilterState(1)).toBe('rest');
    for (const m of [0, 0.08, 0.3, 0.7999, 0.8, 0.95, 1]) expect(L.panelFilterState(m) === 'rest').toBe(L.panelBlurPx(m) === 0);
  });
  it('filter value and own layer per state', () => {
    expect(L.panelFilterValue(1)).toBe('none');
    expect(L.panelFilterValue(0)).toBe('blur(12px)');
    expect(L.panelOwnLayer(0.4)).toBe(true);
    expect(L.panelOwnLayer(0.9)).toBe(false);
  });
  it('writer sets data-fw-filter only in the variant and only at the toggle', () => {
    const attrs: Record<string, string> = {};
    const node = { setAttribute: (n: string, v: string) => void (attrs[n] = v), removeAttribute: (n: string) => void delete attrs[n] };
    const off = createPanelWriter({ panel: node, cta: null });
    off.apply(1);
    expect(attrs['data-fw-filter']).toBeUndefined();
    const w = createPanelWriter({ panel: node, cta: null }, { rest: true });
    w.apply(0.2);
    expect(attrs['data-fw-filter']).toBe('fade');
    w.apply(0.8);
    expect(attrs['data-fw-filter']).toBe('rest');
  });
});
