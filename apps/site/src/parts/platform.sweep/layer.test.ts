import { afterEach, describe, expect, it, vi } from 'vitest';
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
  tiled: (i) => {
    const w = i.w as number;
    const x = (i.v as number) * w;
    return {
      layer: L.color({ u: L.layerU({ w, y: x - L.layerX({ w, t: i.t as number }) }) }),
      orig: L.color({ u: L.repU({ w, x, p: pos({ t: i.t as number }) }) }),
    };
  },
  snap: (i) => {
    const a = { dpr: i.dpr as number, left: i.left as number, width: i.width as number };
    return { px: L.snapPx(a), w: L.snapW(a) };
  },
  work: (i) => ({ orig: i.words as number, layer: 0 }),
});

describe('platform.sweep layer-sweep', () => {
  it('the layer offset equals the original background offset at every sampled time', () => {
    for (const w of [90, 230]) for (const t of [0, 1, 777, 2000, 3999.5, 4000, 12345]) expect(L.layerX({ w, t })).toBeCloseTo(L.bgOffset({ w, t }), 9);
  });
  it('the rounded keyframe stays within w / 1e6 px of the exact one', () => {
    for (const t of [0, 500, 2500, 3999]) expect(Math.abs(L.layerXCss({ w: 200, t }) - L.layerX({ w: 200, t }))).toBeLessThanOrEqual(200 / 1e6 + 1e-12);
  });
  it('the layer reads the same colour as the original with repeat at the start seam', () => {
    for (const w of [100, 230]) expect(L.layerU({ w, y: w - L.layerX({ w, t: 0 }) })).toBeCloseTo(L.repU({ w, x: w, p: 1 }), 9);
  });
});

describe('watchLayerWidth', () => {
  afterEach(() => vi.unstubAllGlobals());
  const el = () => {
    const props = new Map<string, string>();
    return { props, style: { setProperty: (k: string, v: string) => props.set(k, v) }, getBoundingClientRect: () => ({ left: 20.4, width: 526.81 }) } as unknown as HTMLElement & { props: Map<string, string> };
  };
  const stub = (withDevice: boolean) => {
    let cb: ResizeObserverCallback = () => undefined;
    class RO {
      constructor(c: ResizeObserverCallback) {
        cb = c;
      }
      observe(_t: Element, o?: ResizeObserverOptions) {
        if (!withDevice && o?.box === 'device-pixel-content-box') throw new TypeError('unsupported');
      }
      disconnect() {}
    }
    vi.stubGlobal('ResizeObserver', RO);
    vi.stubGlobal('window', { devicePixelRatio: 2 });
    return (target: HTMLElement, size?: number) => cb([{ target, devicePixelContentBoxSize: size === undefined ? undefined : [{ inlineSize: size }] } as unknown as ResizeObserverEntry], {} as ResizeObserver);
  };
  it('uses the device-pixel count when the engine reports it', () => {
    const fire = stub(true);
    const w = el();
    L.watchLayerWidth([w]);
    fire(w, 1054);
    expect(w.props.get(L.LAYER_WIDTH_VAR)).toBe('3162px');
  });
  it('falls back to the rect through snapPx when the box option is rejected or absent', () => {
    const fire = stub(false);
    const w = el();
    L.watchLayerWidth([w]);
    fire(w);
    expect(w.props.get(L.LAYER_WIDTH_VAR)).toBe(`${(6 * L.snapPx({ dpr: 2, left: 20.4, width: 526.81 })) / 2}px`);
  });
});
