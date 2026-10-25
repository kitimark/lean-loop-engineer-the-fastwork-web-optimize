import { describe, expect, it } from 'vitest';
import { decodeRat, readGolden } from '../../engine/golden.testutil';
import { drawnEdges, scaleApplies, scaleVars, sxAt, txAt } from './scale';

const golden = readGolden('morph.columns.final-scale', 'main');

describe('morph.columns:final-scale golden (Lean MorphColumnsScale)', () => {
  it('per-viewport constants equal the Lean rows', () => {
    const rows = golden.filter((g) => g.fn === 'vars');
    expect(rows.length).toBeGreaterThan(8);
    for (const g of rows) {
      const w = (g.in as { w: number }).w;
      const out = decodeRat(g.out) as { applies: boolean; n: number; cf: number; a: number; d: number };
      const v = scaleVars(w);
      expect(scaleApplies(w), String(w)).toBe(out.applies);
      expect(v.n).toBe(out.n);
      expect(v.cf).toBeCloseTo(out.cf, 9);
      expect(v.a).toBeCloseTo(out.a, 9);
      expect(v.d).toBeCloseTo(out.d, 9);
    }
  });

  it('the CSS arithmetic gives the Lean scale and translate, and the drawn edges equal the base layout edges', () => {
    const rows = golden.filter((g) => g.fn === 'frame');
    expect(rows.length).toBeGreaterThan(90);
    for (const g of rows) {
      const { w, mm } = g.in as { w: number; mm: number };
      const out = decodeRat(g.out) as { sx: number; tx: number[]; baseLeft: number[]; baseRight: number[] };
      const v = scaleVars(w);
      const m = mm / 1000;
      expect(sxAt(v, m), JSON.stringify(g.in)).toBeCloseTo(out.sx, 9);
      out.tx.forEach((t, i) => {
        expect(txAt(v, m, i)).toBeCloseTo(t, 9);
        const [l, r] = drawnEdges(v, m, i);
        expect(l, `${JSON.stringify(g.in)} col ${i}`).toBeCloseTo(out.baseLeft[i]!, 7);
        expect(r, `${JSON.stringify(g.in)} col ${i}`).toBeCloseTo(out.baseRight[i]!, 7);
      });
    }
  });
});
