import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { buildAnims, evalAt, gridKnots, keyframes, selector, TIME_END, type Eng, type Layout, type Prop } from './tracks';

/** Fw.Parts.MorphGeom: the knot tables and `sample` lines of packages/contracts/golden/morph-geom.jsonl. */
const lines = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/morph-geom.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as { fn: string; in: Record<string, unknown>; out: unknown });

const M = [0, 0.01, 0.05, 0.08, 0.15, 0.2, 0.32, 0.5, 0.55, 0.8, 1];

/** Lean `Ctx.sample`. */
function sample(w: number, eng: Eng): Layout {
  const ph = w <= 640;
  const cols = ph ? 3 : 5;
  return {
    eng,
    a: 0,
    b: 1,
    inset: ph ? 16 : 24,
    logoW: ph ? 120 : 160,
    lw: ph ? 120 : 144,
    w0: ph ? 152 : 176,
    gL: 0,
    imgs: Array.from({ length: cols }, () => [[0, 200], [200, 200], [400, 200]]),
  };
}

describe('morph.geom tracks against the Lean golden', () => {
  it('the grid knots equal the golden', () => {
    const rows = lines.filter((l) => l.fn === 'knots');
    expect(rows.length).toBe(12);
    for (const r of rows) {
      const got = gridKnots({ w: r.in.w as number, h: r.in.h as number });
      const want = (r.out as { grid: number[] }).grid;
      expect(got.length).toBe(want.length);
      got.forEach((x, k) => expect(Math.abs(x - want[k])).toBeLessThan(1e-8));
    }
  });

  it('every sample line is reproduced within 1e-6', () => {
    const rows = lines.filter((l) => l.fn === 'sample');
    expect(rows.length).toBe(653);
    const cache = new Map<string, ReturnType<typeof buildAnims>>();
    for (const r of rows) {
      const i = r.in as { w: number; h: number; eng: Eng; el: string; i: number; j: number; prop: Prop; ks: string };
      const key = `${i.w}x${i.h}:${i.eng}`;
      if (!cache.has(key)) cache.set(key, buildAnims({ w: i.w, h: i.h }, sample(i.w, i.eng)));
      const a = cache.get(key)!.find((x) => x.el === i.el && x.i === i.i && x.j === i.j && x.prop === i.prop);
      expect(a, `${key} ${i.el} ${i.prop}`).toBeDefined();
      expect(a!.ks).toBe(i.ks);
      const want = r.out as number[][];
      expect(a!.values.length).toBe(want.length);
      want.forEach((col, f) =>
        col.forEach((x, p) => {
          const at = a!.ks === 'time' ? M[p] * TIME_END : M[p];
          expect(Math.abs(evalAt(a!, f, at) - x), `${key} ${i.el} ${i.prop} f${f} m${M[p]}`).toBeLessThan(1e-6);
        }),
      );
    }
  });

  it('keyframes keep one function-list shape, sorted offsets 0..1 and the selector contract', () => {
    for (const eng of ['webkit', 'chromium'] as const) {
      for (const [w, h] of [[390, 844], [1280, 800]]) {
        const as = buildAnims({ w, h }, sample(w, eng));
        const seen = new Set<string>();
        for (const a of as) {
          const kf = keyframes(a);
          expect(kf[0].offset).toBe(0);
          expect(kf[kf.length - 1].offset).toBe(1);
          for (let k = 1; k < kf.length; k++) expect(kf[k].offset).toBeGreaterThan(kf[k - 1].offset);
          const id = `${selector(a)}|${a.prop}`;
          expect(seen.has(id)).toBe(false);
          seen.add(id);
          const shape = (s: string) => s.replace(/-?\d+(\.\d+)?/g, '#');
          const first = shape(String(kf[0][a.prop]));
          for (const f of kf) expect(shape(String(f[a.prop]))).toBe(first);
        }
      }
    }
  });
});
