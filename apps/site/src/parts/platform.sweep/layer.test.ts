import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './layer';
import { pos } from './logic';

goldenConformance('platform-sweep-layer', {
  const: () => ({ periodMs: L.PERIOD_MS, flag: L.FLAG, variant: L.VARIANT, fromPct: L.FROM_PCT, budgetBytes: L.BUDGET_BYTES, layers: L.LAYERS }),
  layerX: (i) => ({ x: L.layerX({ w: i.w, t: i.t }), bg: L.bgOffset({ w: i.w, t: i.t }), css: L.layerXCss({ w: i.w, t: i.t }) }),
  shown: (i) => ({
    layer: L.color({ u: L.bandU({ w: i.w, x: L.layerX({ w: i.w, t: i.t }), v: i.v }) }),
    orig: L.color({ u: L.imageU({ v: i.v, p: pos({ t: i.t }) }) }),
  }),
  work: (i) => ({ orig: i.words as number, layer: 0 }),
});

describe('platform.sweep layer-sweep', () => {
  it('the layer offset equals the original background offset at every sampled time', () => {
    for (const w of [90, 230]) for (const t of [0, 1, 777, 2000, 3999.5, 4000, 12345]) expect(L.layerX({ w, t })).toBeCloseTo(L.bgOffset({ w, t }), 9);
  });
  it('the rounded keyframe stays within w / 1e6 px of the exact one', () => {
    for (const t of [0, 500, 2500, 3999]) expect(Math.abs(L.layerXCss({ w: 200, t }) - L.layerX({ w: 200, t }))).toBeLessThanOrEqual(200 / 1e6 + 1e-12);
  });
});
