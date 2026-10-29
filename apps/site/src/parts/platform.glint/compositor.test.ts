import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';
import { LAYER, compositorKeyframes, compositorTiming } from './compositor';
import gen from './compositor.gen';
import * as L from './logic';

const golden = readFileSync(new URL('../../../../../packages/contracts/golden/parts/platform-glint-compositor.jsonl', import.meta.url), 'utf8')
  .trim()
  .split('\n')
  .map((l) => decodeRat(JSON.parse(l)) as { fn: string; in: Record<string, unknown>; out: any });
const of = (fn: string) => golden.filter((l) => l.fn === fn);

/** CSS keyframe evaluation: linear between the offsets, as the animation runs with easing linear. */
function shiftAt(side: L.Side, elapsed: number): number {
  const kf = gen.keyframes[side];
  const u = ((elapsed / gen.durMs) % 1 + 1) % 1;
  const k = Math.min(kf.length - 2, kf.findIndex((x, i) => u >= x.offset && u < kf[i + 1]!.offset));
  const a = kf[k]!;
  const b = kf[k + 1]!;
  return a.tx + (b.tx - a.tx) * ((u - a.offset) / (b.offset - a.offset));
}

describe('platform.glint:compositor against the Lean golden', () => {
  it('the layer geometry and timing are the golden constants', () => {
    const c = of('glint.compositor.const')[0]!.out;
    expect(LAYER).toEqual({ left: c.layerLeft, width: c.layerWidth });
    expect(compositorTiming()).toEqual({ duration: c.durMs, iterations: Infinity, easing: 'linear' });
    expect(c.durMs).toBe(L.DUR_MS);
  });

  it('the keyframes are the golden keyframes (offset k/5, translateX px)', () => {
    for (const side of ['left', 'right'] as const) {
      const g = of('glint.compositor.keyframes').find((l) => l.in.side === side)!.out as Array<{ offset: number; tx: number }>;
      expect(compositorKeyframes(side)).toEqual(g.map((k) => ({ offset: k.offset, transform: `translateX(${k.tx}px)` })));
    }
  });

  it('the keyframes are the original x1 values plus 200 (restated in logic.ts)', () => {
    for (const side of ['left', 'right'] as const) expect(gen.keyframes[side].map((k) => k.tx)).toEqual(L.X1[side].map((x) => x + 200));
  });

  it('every golden sample: the fixed layer shifted by the keyframes puts each stop where the original gradient does', () => {
    expect(of('glint.compositor.stops').length).toBeGreaterThan(30);
    for (const l of of('glint.compositor.stops')) {
      const side = l.in.side as L.Side;
      const e = l.in.elapsed as number;
      const [x1, x2] = L.sample({ side, elapsed: e });
      const orig = gen.stopOffsets.map((o) => x1 + o * (x2 - x1));
      const variant = gen.stopOffsets.map((o) => LAYER.left + o * LAYER.width + shiftAt(side, e));
      for (let i = 0; i < orig.length; i++) {
        expect(orig[i]).toBeCloseTo(l.out.orig[i], 9);
        expect(variant[i]).toBeCloseTo(l.out.variant[i], 9);
        expect(variant[i]).toBeCloseTo(orig[i]!, 9);
      }
    }
  });

  it('the animation set has no SMIL and no per-frame write', () => {
    const s = of('glint.compositor.set')[0]!.out;
    expect(s).toEqual({ variantSmil: 0, variantWrites: 0, faithfulWrites: 4 });
  });

  it('the CSS module restates the layer: left, width and the six stop offsets', () => {
    const css = readFileSync(new URL('../platform/visuals.module.css', import.meta.url), 'utf8');
    const block = /\.glintLayer \{([^}]*)\}/s.exec(css)![1]!;
    expect(block).toContain(`left: ${LAYER.left}px`);
    expect(block).toContain(`width: ${LAYER.width}px`);
    const pct = [...block.matchAll(/\) (\d+)%/g)].map((m) => Number(m[1]) / 100);
    expect(pct).toEqual(gen.stopOffsets);
  });
});
