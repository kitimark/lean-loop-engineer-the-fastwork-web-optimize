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
