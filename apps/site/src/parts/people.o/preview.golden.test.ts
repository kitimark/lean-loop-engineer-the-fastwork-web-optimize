import { describe, expect, it } from 'vitest';
import { decodeRat, diff, readGolden } from '../../engine/golden.testutil';
import * as P from './preview';

const golden = readGolden('people-o-preview', 'main');

describe('people.o:preview-translate golden', () => {
  it('every golden fn is covered', () => {
    expect(new Set(golden.map((g) => g.fn))).toEqual(new Set(['regime', 'snapDev', 'step', 'layoutPasses']));
  });

  it('regime equals the Lean regime', () => {
    for (const g of golden.filter((x) => x.fn === 'regime')) {
      const i = decodeRat(g.in) as { vh: number; t: number; b: number };
      expect(P.regime(i), JSON.stringify(g.in)).toBe(g.out);
    }
  });

  it('snapDev rows are device-pixel rounding half up', () => {
    for (const g of golden.filter((x) => x.fn === 'snapDev')) {
      const i = decodeRat(g.in) as { d: number; v: number };
      expect(Math.floor(i.v * i.d + 0.5), JSON.stringify(g.in)).toBe(g.out);
    }
  });

  it('step equals the Lean step, keep decision included', () => {
    const rows = golden.filter((x) => x.fn === 'step');
    expect(rows.length).toBeGreaterThan(100);
    for (const g of rows) {
      const i = decodeRat(g.in) as { d: number; held: P.Held; input: P.Held; y: number };
      const o = decodeRat(g.out) as { keep: boolean; out: P.Step };
      expect(P.keep(i), JSON.stringify(g.in)).toBe(o.keep);
      expect(diff(P.step(i), o.out), JSON.stringify(g.in)).toBeNull();
    }
  });

  it('kept frames write nothing, and layout leaves them (Lean layoutPasses 0)', () => {
    const lp = (engine: string, variant: string, kept: boolean) =>
      golden.find((g) => g.fn === 'layoutPasses' && g.in.engine === engine && g.in.variant === variant && g.in.kept === kept)!.out;
    for (const engine of ['chromium', 'webkit']) {
      expect(lp(engine, 'translate', true)).toBe(0);
      expect(lp(engine, 'translate', false)).toBe(1);
      expect(lp(engine, 'faithful', true)).toBe(1);
    }
    const kept = golden.filter((x) => x.fn === 'step' && (x.out as { keep: boolean }).keep);
    expect(kept.length).toBeGreaterThan(20);
    for (const g of kept) expect((decodeRat(g.out) as { out: P.Step }).out.write).toBe(false);
  });
});
