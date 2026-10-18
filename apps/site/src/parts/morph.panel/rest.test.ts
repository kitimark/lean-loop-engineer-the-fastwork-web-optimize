import { describe, expect, it } from 'vitest';
import { fade, filterCss, filterO, filterV, radius } from './rest';

describe('morph.panel variant rest (Lean MorphPanelOpt)', () => {
  it('restates the #guard rows', () => {
    expect(fade(0)).toBe(1);
    expect(fade(11 / 20)).toBeCloseTo(0, 12);
    expect(fade(11 / 40)).toBeCloseTo(1 / 2, 12);
    expect(fade(-1)).toBeCloseTo(31 / 11, 12);
    expect(fade(2)).toBe(0);
    expect(radius(1)).toBe(0);
    expect(radius(1 / 2)).toBe(6);
    expect(radius(0)).toBe(12);
    expect(radius(2)).toBe(0);
    expect(filterV(1)).toEqual([]);
    expect(filterO(1)).toEqual([{ name: 'blur', args: [0] }]);
    expect(filterV(1 / 2)).toEqual(filterO(1 / 2));
    expect(filterV(fade(-3))).toEqual([]);
    expect(filterV(fade(1 / 100))).not.toEqual([]);
  });
  it('filterV_rest: at rest (r <= 0) the variant has no filter; elsewhere it equals the original', () => {
    for (const r of [-5, -1, -0.001, 0]) expect(filterV(fade(r))).toEqual(filterV(1)), expect(filterCss(fade(r))).toBe(filterCss(1));
    for (const r of [0.001, 0.1, 0.3, 0.55, 1]) {
      const phi = fade(r);
      if (radius(phi) > 0) expect(filterV(phi)).toEqual(filterO(phi));
    }
  });
});
